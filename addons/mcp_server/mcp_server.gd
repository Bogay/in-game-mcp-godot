extends Node

## Core Autoload for the Godot In-Game Model Context Protocol (MCP) Server.
## Acts as the main orchestrator, dynamically loading and managing transport,
## registry, and JSON-RPC protocol layers.

signal tools_changed()
signal tool_called(tool_name: String, arguments: Dictionary, response: Dictionary)
signal resources_changed()

@export_enum("WebSocket", "SSE") var transport: String = "SSE"
@export var port: int = 9090
@export var bind_address: String = "127.0.0.1"
@export var allowed_hosts: PackedStringArray = ["localhost", "127.0.0.1", "[::1]", "::1"]
@export var auto_start: bool = true
@export var conformance_mode: bool = false:
    set(val):
        conformance_mode = val
        if protocol_handler:
            protocol_handler.conformance_mode = val

# Helper component preloads
const MCPToolRegistryClass = preload("res://addons/mcp_server/core/mcp_tool_registry.gd")
const MCPResourceRegistryClass = preload("res://addons/mcp_server/core/mcp_resource_registry.gd")
const MCPProtocolHandlerClass = preload("res://addons/mcp_server/core/mcp_protocol_handler.gd")
const MCPWebSocketTransportClass = preload("res://addons/mcp_server/core/mcp_websocket_transport.gd")
const MCPSSETransportClass = preload("res://addons/mcp_server/core/mcp_sse_transport.gd")

## Core Sub-components
var tool_registry = MCPToolRegistryClass.new()
var resource_registry = MCPResourceRegistryClass.new()
var protocol_handler = MCPProtocolHandlerClass.new(tool_registry, resource_registry)
var active_transport: RefCounted

## Backwards compatibility accessors for external tools and scenes
var available_tools: Dictionary:
    get: return tool_registry.available_tools

var cached_manifests: Array:
    get: return tool_registry.cached_manifests

var connected_peers: Array:
    get:
        if active_transport:
            if "connected_peers" in active_transport:
                return active_transport.connected_peers
            elif "sse_sessions" in active_transport:
                return active_transport.sse_sessions.values()
        return []

func _ready() -> void:
    _load_config()
    protocol_handler.conformance_mode = conformance_mode
    
    # 1. Wire internal component signals up to the Autoload's public signals
    tool_registry.tools_changed.connect(func(): tools_changed.emit())
    resource_registry.resources_changed.connect(func(): resources_changed.emit())
    
    protocol_handler.tool_called.connect(
        func(tool_name: String, arguments: Dictionary, response: Dictionary):
            tool_called.emit(tool_name, arguments, response)
    )
    protocol_handler.request_sent.connect(
        func(session_id: String, payload: Dictionary):
            if active_transport:
                active_transport.send_to_client(session_id, payload)
    )
    tools_changed.connect(_on_tools_changed)
    resources_changed.connect(_on_resources_changed)
    
    # 2. Automatically start the server if configured
    if auto_start:
        start_server()

func _load_config() -> void:
    # 1. Load from ProjectSettings if defined
    if ProjectSettings.has_setting("mcp_server/transport"):
        transport = ProjectSettings.get_setting("mcp_server/transport")
    if ProjectSettings.has_setting("mcp_server/port"):
        port = ProjectSettings.get_setting("mcp_server/port")
    if ProjectSettings.has_setting("mcp_server/bind_address"):
        bind_address = ProjectSettings.get_setting("mcp_server/bind_address")
    if ProjectSettings.has_setting("mcp_server/allowed_hosts"):
        allowed_hosts = ProjectSettings.get_setting("mcp_server/allowed_hosts")
    if ProjectSettings.has_setting("mcp_server/auto_start"):
        auto_start = ProjectSettings.get_setting("mcp_server/auto_start")
    if ProjectSettings.has_setting("mcp_server/conformance_mode"):
        conformance_mode = ProjectSettings.get_setting("mcp_server/conformance_mode")

    # 2. Load from Environment Variables (higher priority)
    if OS.has_environment("MCP_TRANSPORT"):
        transport = OS.get_environment("MCP_TRANSPORT")
    if OS.has_environment("MCP_PORT"):
        port = OS.get_environment("MCP_PORT").to_int()
    if OS.has_environment("MCP_BIND_ADDRESS"):
        bind_address = OS.get_environment("MCP_BIND_ADDRESS")
    if OS.has_environment("MCP_ALLOWED_HOSTS"):
        allowed_hosts = OS.get_environment("MCP_ALLOWED_HOSTS").split(",")
    if OS.has_environment("MCP_AUTO_START"):
        auto_start = OS.get_environment("MCP_AUTO_START").to_lower() in ["true", "1", "yes"]
    if OS.has_environment("MCP_CONFORMANCE_MODE"):
        conformance_mode = OS.get_environment("MCP_CONFORMANCE_MODE").to_lower() in ["true", "1", "yes"]

    # 3. Load from Command-line Arguments (highest priority)
    for arg in OS.get_cmdline_args():
        if arg.begins_with("--mcp-transport="):
            transport = arg.substr("--mcp-transport=".length())
        elif arg.begins_with("--mcp-port="):
            port = arg.substr("--mcp-port=".length()).to_int()
        elif arg.begins_with("--mcp-bind-address="):
            bind_address = arg.substr("--mcp-bind-address=".length())
        elif arg.begins_with("--mcp-allowed-hosts="):
            allowed_hosts = arg.substr("--mcp-allowed-hosts=".length()).split(",")
        elif arg.begins_with("--mcp-auto-start="):
            var val = arg.substr("--mcp-auto-start=".length()).to_lower()
            auto_start = val in ["true", "1", "yes"]
        elif arg.begins_with("--mcp-conformance-mode="):
            var val = arg.substr("--mcp-conformance-mode=".length()).to_lower()
            conformance_mode = val in ["true", "1", "yes"]

func _process(_delta: float) -> void:
    if active_transport:
        active_transport.poll()

## Starts the active transport and begins listening for incoming client connections.
func start_server() -> bool:
    if active_transport:
        return true
        
    # Instantiate the correct transport layer
    if transport == "WebSocket":
        active_transport = MCPWebSocketTransportClass.new()
    else:
        active_transport = MCPSSETransportClass.new()
        
    # Wire incoming transport messages to the protocol processor
    active_transport.message_received.connect(
        func(session_id: String, text: String, responder: Callable):
            var response_text = await protocol_handler.process_message(session_id, text)
            responder.call(response_text)
    )
    
    var success = active_transport.start(port, bind_address)
    if not success:
        active_transport = null
        return false
    return true

## Stops the active transport and shuts down all active client connections.
func stop_server() -> void:
    if active_transport:
        active_transport.stop()
        active_transport = null
        
    protocol_handler.handshake_states.clear()
    print("[MCP Server] Server stopped.")

# --- Tool Registration (Delegates to Tool Registry) ---

## Registers a standard MCPTool or any duck-typed object implementing execute and get_tool_name
func register_tool(tool: Object) -> void:
    tool_registry.register_tool(tool)

## Unregisters a registered tool by reference.
func unregister_tool(tool: Object) -> void:
    tool_registry.unregister_tool(tool)

## Unregisters a registered tool by its name.
func unregister_tool_name(tool_name: String) -> void:
    tool_registry.unregister_tool_name(tool_name)

## Thin wrapper registry for lambdas and inline functions
func register_function(tool_name: String, desc: String, schema: Dictionary, target: Callable, metadata: Dictionary = {}) -> void:
    tool_registry.register_function(tool_name, desc, schema, target, metadata)

## Registers all child tools found within an MCPCommandGroup
func register_command_group(group: MCPCommandGroup) -> void:
    tool_registry.register_command_group(group)

## Unregisters all child tools of an MCPCommandGroup
func unregister_command_group(group: MCPCommandGroup) -> void:
    tool_registry.unregister_command_group(group)

# --- Broadcast and Notifications ---

func _on_tools_changed() -> void:
    var notification = {
        "jsonrpc": "2.0",
        "method": "notifications/tools/list_changed"
    }
    _broadcast(notification)

func _on_resources_changed() -> void:
    var notification = {
        "jsonrpc": "2.0",
        "method": "notifications/resources/list_changed"
    }
    _broadcast(notification)

## Registers a custom MCPResource script object in the registry
func register_resource(resource: Object) -> void:
    resource_registry.register_resource(resource)

## Unregisters an MCPResource object
func unregister_resource(resource: Object) -> void:
    resource_registry.unregister_resource(resource)

## Unregisters a resource by its URI
func unregister_resource_uri(uri: String) -> void:
    resource_registry.unregister_uri(uri)

## Registers a resource dynamically using an inline read callback lambda
func register_dynamic_resource(uri: String, name: String, mime_type: String, desc: String, read_callback: Callable) -> void:
    resource_registry.register_dynamic_resource(uri, name, mime_type, desc, read_callback)

func _broadcast(message: Dictionary) -> void:
    if active_transport:
        active_transport.broadcast(message)

# --- Conformance and Utility APIs ---

## Sends a log message notification to all connected clients
func send_log_message(level: String, data: Variant, logger: String = "") -> void:
    var params = {
        "level": level,
        "data": data
    }
    if logger != "":
        params["logger"] = logger
    var msg = {
        "jsonrpc": "2.0",
        "method": "notifications/message",
        "params": params
    }
    _broadcast(msg)

## Sends a progress notification to all connected clients
func send_progress(progress_token: Variant, progress: float, total: float) -> void:
    var msg = {
        "jsonrpc": "2.0",
        "method": "notifications/progress",
        "params": {
            "progressToken": progress_token,
            "progress": progress,
            "total": total
        }
    }
    _broadcast(msg)

## Sends a request message to a client session and awaits the response
func send_client_request(session_id: String, method: String, params: Dictionary) -> Dictionary:
    var result = await protocol_handler.send_request(session_id, method, params)
    return result
