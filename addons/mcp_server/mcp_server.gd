extends Node

## Core Autoload for the Godot In-Game Model Context Protocol (MCP) Server.
## Manages incoming client connections over WebSockets, processes JSON-RPC 2.0,
## and routes requests to registered tools.

signal tools_changed()
signal tool_called(tool_name: String, arguments: Dictionary, response: Dictionary)

@export_enum("WebSocket", "SSE") var transport: String = "SSE"
@export var port: int = 9090
@export var bind_address: String = "127.0.0.1"
@export var auto_start: bool = true

var tcp_server := TCPServer.new()
var connected_peers: Array[WebSocketPeer] = []

# HTTP / SSE Specific States
var pending_http_clients: Array = []
var sse_sessions: Dictionary = {}

# Handshake states: 0 = Uninitialized, 1 = Initializing, 2 = Initialized
var ws_handshake_states: Dictionary = {}
var sse_handshake_states: Dictionary = {}
var _tool_name_regex: RegEx

## Registered tools registry: tool_name -> Object/Node (duck-typed for get_tool_name/execute)
var available_tools: Dictionary = {}

## Cached tool manifests list for rapid lookup on tools/list requests
var cached_manifests: Array = []

class ProxyMCPTool extends MCPTool:
    var _base_tool: Object
    var _custom_name: String
    
    func _init(base_tool: Object, custom_name: String) -> void:
        _base_tool = base_tool
        _custom_name = custom_name
        
    func get_tool_name() -> String:
        return _custom_name
        
    func get_description() -> String:
        if _base_tool.has_method("get_description"):
            return _base_tool.get_description()
        elif _base_tool.has_method("GetDescription"):
            return _base_tool.GetDescription()
        return "No description."
        
    func get_input_schema() -> Dictionary:
        if _base_tool.has_method("get_input_schema"):
            return _base_tool.get_input_schema()
        elif _base_tool.has_method("GetInputSchema"):
            return _base_tool.GetInputSchema()
        return { "type": "object", "properties": {}, "required": [] }
        
    func execute(args: Dictionary) -> Dictionary:
        if _base_tool.has_method("execute"):
            @warning_ignore("redundant_await")
            return await _base_tool.execute(args)
        elif _base_tool.has_method("Execute"):
            @warning_ignore("redundant_await")
            return await _base_tool.Execute(args)
        return { "isError": true, "content": [{"type": "text", "text": "Not Implemented"}] }

func _ready() -> void:
    _tool_name_regex = RegEx.new()
    _tool_name_regex.compile("^[a-zA-Z0-9_-]+$")
    tools_changed.connect(_on_tools_changed)
    if auto_start:
        start_server()

func _process(_delta: float) -> void:
    if transport == "WebSocket":
        _process_websocket()
    else:
        _process_sse()

func _process_websocket() -> void:
    # 1. Accept new raw TCP connections and handshake upgrade to WebSocket
    if tcp_server.is_listening() and tcp_server.is_connection_available():
        var tcp_peer = tcp_server.take_connection()
        if tcp_peer:
            var ws_peer = WebSocketPeer.new()
            var err = ws_peer.accept_stream(tcp_peer)
            if err == OK:
                connected_peers.append(ws_peer)
                ws_handshake_states[ws_peer] = 0
                print("[MCP Server] New client connection pending handshake...")
            else:
                push_error("[MCP Server] Failed to accept WebSocket stream: %d" % err)
                
    # 2. Poll and parse frames from all connected peers
    var active_peers: Array[WebSocketPeer] = []
    for peer in connected_peers:
        peer.poll()
        var state = peer.get_ready_state()
        if state == WebSocketPeer.STATE_OPEN:
            active_peers.append(peer)
            while peer.get_available_packet_count() > 0:
                var packet = peer.get_packet()
                var text = packet.get_string_from_utf8()
                _handle_message(peer, text)
        elif state == WebSocketPeer.STATE_CONNECTING:
            active_peers.append(peer)
        elif state == WebSocketPeer.STATE_CLOSING:
            active_peers.append(peer)
        else:
            print("[MCP Server] Client connection closed.")
            if peer in ws_handshake_states:
                ws_handshake_states.erase(peer)
            
    connected_peers = active_peers

func _process_sse() -> void:
    # 1. Accept new incoming HTTP connections
    if tcp_server.is_listening() and tcp_server.is_connection_available():
        var tcp_peer = tcp_server.take_connection()
        if tcp_peer:
            print("[MCP Server DEBUG] Accepted connection from ", tcp_peer.get_connected_host(), ":", tcp_peer.get_connected_port())
            pending_http_clients.append({
                "socket": tcp_peer,
                "buffer": PackedByteArray(),
                "header_parsed": false,
                "content_length": 0,
                "method": "",
                "path": "",
                "session_id": ""
            })
            
    # 2. Poll and parse pending HTTP client request streams
    var still_pending: Array = []
    for client in pending_http_clients:
        var socket = client.socket as StreamPeerTCP
        socket.poll()
        var status = socket.get_status()
        if status != StreamPeerTCP.STATUS_CONNECTED:
            print("[MCP Server DEBUG] Client disconnected before header parsed")
            continue
            
        var avail = socket.get_available_bytes()
        if avail > 0:
            var read_res = socket.get_partial_data(avail)
            if read_res[0] == OK:
                client.buffer.append_array(read_res[1])
                print("[MCP Server DEBUG] Read ", avail, " bytes. Buffer size now: ", client.buffer.size())
                
        if not client.header_parsed:
            var header_end = _find_double_newline(client.buffer)
            if header_end != -1:
                var header_bytes = client.buffer.slice(0, header_end)
                var header_str = header_bytes.get_string_from_utf8()
                print("[MCP Server DEBUG] Header completed. Content:\n", header_str)
                client.buffer = client.buffer.slice(header_end + 4)
                client.header_parsed = true
                _parse_http_header(client, header_str)
                
        if client.header_parsed:
            var is_options = (client.method == "OPTIONS")
            var is_get_sse = (client.method == "GET" and client.path.begins_with("/sse"))
            var is_post_msg = (client.method == "POST" and (client.path.begins_with("/message") or client.path.begins_with("/sse")))
            
            if is_options:
                _send_http_options_response(socket)
                continue
            elif is_get_sse:
                _upgrade_to_sse(client)
                continue
            elif is_post_msg:
                if client.buffer.size() >= client.content_length:
                    var body_bytes = client.buffer.slice(0, client.content_length)
                    var body_str = body_bytes.get_string_from_utf8()
                    print("[MCP Server DEBUG] POST request received. Path: ", client.path, ", Body: ", body_str)
                    _handle_http_post_async(client, body_str)
                    continue
            else:
                print("[MCP Server DEBUG] Unsupported request. Method: ", client.method, ", Path: ", client.path)
                var err_resp = (
                    "HTTP/1.1 404 Not Found\r\n" +
                    "Access-Control-Allow-Origin: *\r\n" +
                    "Content-Length: 9\r\n" +
                    "Connection: close\r\n\r\n" +
                    "Not Found"
                )
                socket.put_data(err_resp.to_utf8_buffer())
                socket.disconnect_from_host()
                continue
                    
        still_pending.append(client)
        
    pending_http_clients = still_pending
    
    # 3. Monitor active SSE streams to drop closed ones
    var active_sse = {}
    for sid in sse_sessions:
        var peer = sse_sessions[sid] as StreamPeerTCP
        peer.poll()
        if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
            active_sse[sid] = peer
        else:
            if sid in sse_handshake_states:
                sse_handshake_states.erase(sid)
    sse_sessions = active_sse

func _find_double_newline(buf: PackedByteArray) -> int:
    var limit = buf.size() - 3
    for i in range(0, limit):
        if buf[i] == 13 and buf[i+1] == 10 and buf[i+2] == 13 and buf[i+3] == 10:
            return i
    return -1

func _parse_http_header(client: Dictionary, header_str: String) -> void:
    var lines = header_str.split("\r\n")
    if lines.size() > 0:
        var req_line = lines[0].split(" ")
        if req_line.size() >= 2:
            client.method = req_line[0]
            client.path = req_line[1]
            
    for i in range(1, lines.size()):
        var line = lines[i]
        var colon = line.find(":")
        if colon != -1:
            var key = line.substr(0, colon).strip_edges().to_lower()
            var val = line.substr(colon + 1).strip_edges()
            if key == "content-length":
                client.content_length = int(val)
            elif key == "mcp-session-id":
                client.session_id = val

func _send_http_options_response(socket: StreamPeerTCP) -> void:
    var resp = (
        "HTTP/1.1 204 No Content\r\n" +
        "Access-Control-Allow-Origin: *\r\n" +
        "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" +
        "Access-Control-Allow-Headers: Content-Type\r\n" +
        "Content-Length: 0\r\n" +
        "Connection: close\r\n\r\n"
    )
    socket.put_data(resp.to_utf8_buffer())
    socket.disconnect_from_host()

func _get_session_id(client: Dictionary) -> String:
    var session_id = ""
    if client.has("session_id") and client.session_id != "":
        session_id = client.session_id
    else:
        var path = client.get("path", "") as String
        var query_idx = path.find("?")
        if query_idx != -1:
            var query = path.substr(query_idx + 1)
            var params = query.split("&")
            for param in params:
                var pair = param.split("=")
                if pair.size() == 2 and (pair[0] == "session_id" or pair[0] == "sessionId"):
                    session_id = pair[1]
    return session_id

func _upgrade_to_sse(client: Dictionary) -> void:
    var socket = client.socket as StreamPeerTCP
    var session_id = _get_session_id(client)
    if session_id == "":
        session_id = str(randi() % 1000000)
        
    var resp = (
        "HTTP/1.1 200 OK\r\n" +
        "Content-Type: text/event-stream\r\n" +
        "Cache-Control: no-cache\r\n" +
        "Connection: keep-alive\r\n" +
        "Access-Control-Allow-Origin: *\r\n" +
        "Access-Control-Allow-Headers: *\r\n" +
        "Access-Control-Allow-Methods: *\r\n\r\n"
    )
    socket.put_data(resp.to_utf8_buffer())
    
    var is_new_legacy = (_get_session_id(client) == "")
    if is_new_legacy:
        var endpoint_event = "event: endpoint\ndata: /message?sessionId=" + session_id + "\n\n"
        socket.put_data(endpoint_event.to_utf8_buffer())
        
    sse_sessions[session_id] = socket
    if not sse_handshake_states.has(session_id):
        sse_handshake_states[session_id] = 0
    print("[MCP Server] Upgraded client connection to HTTP/SSE. Session ID: ", session_id)

func _handle_http_post_async(client: Dictionary, body_str: String) -> void:
    var socket = client.socket as StreamPeerTCP
    var path = client.path as String
    var session_id = _get_session_id(client)
    var is_legacy = path.begins_with("/message")
    
    if is_legacy:
        if session_id == "" or not sse_sessions.has(session_id):
            var err_resp = (
                "HTTP/1.1 400 Bad Request\r\n" +
                "Access-Control-Allow-Origin: *\r\n" +
                "Access-Control-Allow-Headers: *\r\n" +
                "Access-Control-Allow-Methods: *\r\n" +
                "Content-Length: 35\r\n" +
                "Connection: close\r\n\r\n" +
                "Missing or invalid SSE session_id\n"
            )
            socket.put_data(err_resp.to_utf8_buffer())
            socket.disconnect_from_host()
            return

        # Respond immediately with 202 Accepted for legacy SSE POSTs
        var resp = (
            "HTTP/1.1 202 Accepted\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Access-Control-Allow-Headers: *\r\n" +
            "Access-Control-Allow-Methods: *\r\n" +
            "Content-Length: 0\r\n" +
            "Connection: close\r\n\r\n"
        )
        socket.put_data(resp.to_utf8_buffer())
        socket.disconnect_from_host()
        
        var json = JSON.new()
        var err = json.parse(body_str)
        if err == OK:
            var data = json.get_data()
            if data is Dictionary:
                print("[MCP Server DEBUG] Processing single message. Session ID: ", session_id, ", Data: ", data)
                var resp_dict = await _process_single_message(null, session_id, data)
                print("[MCP Server DEBUG] Single message response: ", resp_dict)
                if resp_dict != null:
                    _send_to_sse(session_id, resp_dict)
            elif data is Array:
                var responses: Array = []
                for item in data:
                    if item is Dictionary:
                        print("[MCP Server DEBUG] Processing batch item. Session ID: ", session_id, ", Item: ", item)
                        var resp_item = await _process_single_message(null, session_id, item)
                        print("[MCP Server DEBUG] Batch item response: ", resp_item)
                        if resp_item != null:
                            responses.append(resp_item)
                if not responses.is_empty():
                    _send_to_sse(session_id, responses)
    else:
        # Streamable HTTP (unified endpoint POST to /sse)
        var json = JSON.new()
        var err = json.parse(body_str)
        if err != OK:
            var err_resp = (
                "HTTP/1.1 400 Bad Request\r\n" +
                "Access-Control-Allow-Origin: *\r\n" +
                "Content-Length: 12\r\n" +
                "Connection: close\r\n\r\n" +
                "Parse error\n"
            )
            socket.put_data(err_resp.to_utf8_buffer())
            socket.disconnect_from_host()
            return
            
        var data = json.get_data()
        var method = ""
        if data is Dictionary:
            method = data.get("method", "")
        elif data is Array and data.size() > 0 and data[0] is Dictionary:
            method = data[0].get("method", "")
            
        if method == "initialize":
            if session_id == "":
                session_id = str(randi() % 1000000)
            sse_handshake_states[session_id] = 0
            print("[MCP Server DEBUG] Streamable HTTP session created: ", session_id)
        elif session_id == "" or not sse_handshake_states.has(session_id):
            var err_resp = (
                "HTTP/1.1 400 Bad Request\r\n" +
                "Access-Control-Allow-Origin: *\r\n" +
                "Content-Length: 33\r\n" +
                "Connection: close\r\n\r\n" +
                "Session not found or invalid ID\n"
            )
            socket.put_data(err_resp.to_utf8_buffer())
            socket.disconnect_from_host()
            return
            
        var resp_payload = null
        if data is Dictionary:
            print("[MCP Server DEBUG] Streamable POST processing: ", data)
            resp_payload = await _process_single_message(null, session_id, data)
            print("[MCP Server DEBUG] Streamable POST response: ", resp_payload)
        elif data is Array:
            var responses: Array = []
            for item in data:
                if item is Dictionary:
                    print("[MCP Server DEBUG] Streamable POST batch processing: ", item)
                    var resp_item = await _process_single_message(null, session_id, item)
                    print("[MCP Server DEBUG] Streamable POST batch response: ", resp_item)
                    if resp_item != null:
                        responses.append(resp_item)
            if not responses.is_empty():
                resp_payload = responses
                
        var resp_body = ""
        if resp_payload != null:
            resp_body = JSON.stringify(resp_payload)
            
        var status_line = "HTTP/1.1 200 OK\r\n"
        if resp_body == "":
            status_line = "HTTP/1.1 204 No Content\r\n"
            
        var http_resp = (
            status_line +
            "Content-Type: application/json\r\n" +
            "Content-Length: " + str(resp_body.to_utf8_buffer().size()) + "\r\n" +
            "Mcp-Session-Id: " + session_id + "\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Access-Control-Allow-Headers: *\r\n" +
            "Access-Control-Allow-Methods: *\r\n" +
            "Connection: close\r\n\r\n" +
            resp_body
        )
        socket.put_data(http_resp.to_utf8_buffer())
        socket.disconnect_from_host()

func _send_to_sse(session_id: String, payload: Variant) -> void:
    var msg = "event: message\ndata: " + JSON.stringify(payload) + "\n\n"
    var raw_data = msg.to_utf8_buffer()
    print("[MCP Server DEBUG] _send_to_sse. Session ID: '", session_id, "', Payload: ", payload, ", MSG: ", msg.replace("\n", "\\n"))
    
    if session_id == "":
        for sid in sse_sessions:
            var peer = sse_sessions[sid] as StreamPeerTCP
            if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
                peer.put_data(raw_data)
        return
        
    var peer = sse_sessions.get(session_id) as StreamPeerTCP
    if peer and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
        peer.put_data(raw_data)
    else:
        if session_id in sse_sessions:
            sse_sessions.erase(session_id)
        if session_id in sse_handshake_states:
            sse_handshake_states.erase(session_id)

## Starts the TCP server to listen for incoming connections.
func start_server() -> bool:
    if tcp_server.is_listening():
        return true
    var err = tcp_server.listen(port, bind_address)
    if err != OK:
        push_error("[MCP Server] Failed to listen on %s:%d (error code %d)" % [bind_address, port, err])
        return false
    if transport == "WebSocket":
        print("[MCP Server] Server listening on ws://%s:%d" % [bind_address, port])
    else:
        print("[MCP Server] Server listening on http://%s:%d/sse" % [bind_address, port])
    return true

## Stops the server and closes all active client connections.
func stop_server() -> void:
    tcp_server.stop()
    for peer in connected_peers:
        peer.close()
    connected_peers.clear()
    
    for client in pending_http_clients:
        var socket = client.socket as StreamPeerTCP
        socket.disconnect_from_host()
    pending_http_clients.clear()
    
    for sid in sse_sessions:
        var peer = sse_sessions[sid] as StreamPeerTCP
        peer.disconnect_from_host()
    sse_sessions.clear()
    
    ws_handshake_states.clear()
    sse_handshake_states.clear()
    
    print("[MCP Server] Server stopped.")

# --- Tool Registration ---

## Registers a standard MCPTool or any duck-typed object implementing execute and get_tool_name
func register_tool(tool: Object) -> void:
    if not tool:
        push_error("[MCP Server] Cannot register null tool.")
        return
    if not ((tool.has_method("execute") or tool.has_method("Execute")) and (tool.has_method("get_tool_name") or tool.has_method("GetToolName"))):
        push_error("[MCP Server] Tool registration failed. Object must implement get_tool_name and execute methods.")
        return
    var tool_name = _get_duck_tool_name(tool)
    if not _validate_tool_name(tool_name):
        push_error("[MCP Server] Tool registration failed. Tool name '%s' must match '^[a-zA-Z0-9_-]{1,64}$'." % tool_name)
        return
    available_tools[tool_name] = tool
    _rebuild_manifests()

## Unregisters a registered tool by reference.
func unregister_tool(tool: Object) -> void:
    if not tool:
        return
    var tool_name = _get_duck_tool_name(tool)
    if available_tools.has(tool_name) and available_tools[tool_name] == tool:
        available_tools.erase(tool_name)
        _rebuild_manifests()

## Unregisters a registered tool by its name.
func unregister_tool_name(tool_name: String) -> void:
    if available_tools.has(tool_name):
        available_tools.erase(tool_name)
        _rebuild_manifests()

## Thin wrapper registry for lambdas and inline functions
func register_function(tool_name: String, desc: String, schema: Dictionary, target: Callable) -> void:
    if not _validate_tool_name(tool_name):
        push_error("[MCP Server] Function registration failed. Tool name '%s' must match '^[a-zA-Z0-9_-]{1,64}$'." % tool_name)
        return
    var dynamic_tool = DynamicMCPTool.new(tool_name, desc, schema, target)
    available_tools[tool_name] = dynamic_tool
    cached_manifests.append(dynamic_tool.to_manifest())
    tools_changed.emit()

## Registers all child tools found within an MCPCommandGroup
func register_command_group(group: MCPCommandGroup) -> void:
    if not group:
        return
    for tool in group.get_tools():
        var tool_name = _get_duck_tool_name(tool)
        if group.prefix != "":
            tool_name = group.prefix + tool_name
        if not _validate_tool_name(tool_name):
            push_error("[MCP Server] Command group tool registration failed. Tool name '%s' must match '^[a-zA-Z0-9_-]{1,64}$'." % tool_name)
            continue
        var proxy = ProxyMCPTool.new(tool, tool_name)
        available_tools[tool_name] = proxy
    _rebuild_manifests()

## Unregisters all child tools of an MCPCommandGroup
func unregister_command_group(group: MCPCommandGroup) -> void:
    if not group:
        return
    var changed := false
    for tool in group.get_tools():
        var tool_name = _get_duck_tool_name(tool)
        if group.prefix != "":
            tool_name = group.prefix + tool_name
        if available_tools.has(tool_name):
            available_tools.erase(tool_name)
            changed = true
    if changed:
        _rebuild_manifests()

# --- Internal Helpers ---

func _validate_tool_name(tool_name: String) -> bool:
    if tool_name.length() == 0 or tool_name.length() > 64:
        return false
    return _tool_name_regex.search(tool_name) != null

func _rebuild_manifests() -> void:
    cached_manifests.clear()
    for tool_name in available_tools:
        var tool = available_tools[tool_name]
        cached_manifests.append(_get_duck_manifest(tool))
    tools_changed.emit()

func _on_tools_changed() -> void:
    var notification = {
        "jsonrpc": "2.0",
        "method": "notifications/tools/list_changed"
    }
    _broadcast(notification)

func _broadcast(message: Dictionary) -> void:
    var text = JSON.stringify(message)
    for peer in connected_peers:
        if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
            peer.send_text(text)
    _send_to_sse("", message)

func _get_duck_tool_name(tool: Object) -> String:
    if tool.has_method("get_tool_name"):
        return tool.get_tool_name()
    elif tool.has_method("GetToolName"):
        return tool.GetToolName()
    return "unnamed_tool"

func _get_duck_description(tool: Object) -> String:
    if tool.has_method("get_description"):
        return tool.get_description()
    elif tool.has_method("GetDescription"):
        return tool.GetDescription()
    return "No description."

func _get_duck_input_schema(tool: Object) -> Dictionary:
    if tool.has_method("get_input_schema"):
        return tool.get_input_schema()
    elif tool.has_method("GetInputSchema"):
        return tool.GetInputSchema()
    return { "type": "object", "properties": {}, "required": [] }

func _get_duck_manifest(tool: Object) -> Dictionary:
    if tool.has_method("to_manifest"):
        return tool.to_manifest()
    elif tool.has_method("ToManifest"):
        return tool.ToManifest()
    return {
        "name": _get_duck_tool_name(tool),
        "description": _get_duck_description(tool),
        "inputSchema": _get_duck_input_schema(tool)
    }

func _execute_duck_tool(tool: Object, args: Dictionary) -> Dictionary:
    if tool.has_method("execute"):
        @warning_ignore("redundant_await")
        return await tool.execute(args)
    elif tool.has_method("Execute"):
        @warning_ignore("redundant_await")
        return await tool.Execute(args)
    return { "isError": true, "content": [{"type": "text", "text": "Not Implemented"}] }

# --- JSON-RPC 2.0 Messaging Pipeline ---

func _handle_message(peer: WebSocketPeer, text: String) -> void:
    var json = JSON.new()
    var err = json.parse(text)
    if err != OK:
        _send_error(peer, null, -32700, "Parse error: " + json.get_error_message())
        return
        
    var data = json.get_data()
    if data is Array:
        # Batch Request processing
        var responses: Array = []
        for item in data:
            if item is Dictionary:
                var resp = await _process_single_message(peer, "", item)
                if resp != null:
                    responses.append(resp)
        if not responses.is_empty():
            peer.send_text(JSON.stringify(responses))
    elif data is Dictionary:
        # Single Request/Notification processing
        var resp = await _process_single_message(peer, "", data)
        if resp != null:
            peer.send_text(JSON.stringify(resp))
    else:
        _send_error(peer, null, -32600, "Invalid Request")

func _process_single_message(peer: WebSocketPeer, session_id: String, message: Dictionary) -> Variant:
    if message.get("jsonrpc", "") != "2.0":
        return _make_error_dict(message.get("id"), -32600, "Invalid Request: Missing or invalid jsonrpc version")
        
    var method = message.get("method", "")
    if method == "":
        return _make_error_dict(message.get("id"), -32600, "Invalid Request: Missing method name")
        
    var has_id = message.has("id")
    var id = message.get("id")
    
    # Determine current handshake state
    var current_state = 0
    if peer != null:
        current_state = ws_handshake_states.get(peer, 0)
    else:
        current_state = sse_handshake_states.get(session_id, 0)
        
    # Enforce initialization handshake
    if method != "initialize" and method != "notifications/initialized":
        if current_state != 2:
            if has_id:
                return _make_error_dict(id, -32002, "Server is not initialized. Complete initialization handshake first.")
            else:
                return null
    
    match method:
        "initialize":
            if not has_id:
                return null
            
            if peer != null:
                ws_handshake_states[peer] = 1
            else:
                if session_id != "":
                    sse_handshake_states[session_id] = 1
                    
            return {
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {
                        "tools": {
                            "listChanged": true
                        }
                    },
                    "serverInfo": {
                        "name": "godot-in-game-mcp-server",
                        "version": "1.0.0"
                    }
                }
            }
        "notifications/initialized":
            if peer != null:
                ws_handshake_states[peer] = 2
            else:
                if session_id != "":
                    sse_handshake_states[session_id] = 2
            return null
        "tools/list":
            if not has_id:
                return null
            return {
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "tools": cached_manifests
                }
            }
        "tools/call":
            if not has_id:
                return null
            var params = message.get("params", {})
            var tool_name = params.get("name", "")
            var arguments = params.get("arguments", {})
            
            if tool_name == "":
                return _make_error_dict(id, -32602, "Invalid params: Missing tool name")
                
            if not available_tools.has(tool_name):
                return _make_error_dict(id, -32601, "Method not found: Tool '%s' is not registered" % tool_name)
                
            var tool = available_tools[tool_name]
            var execution_result = await _execute_duck_tool(tool, arguments)
            
            if not (execution_result is Dictionary):
                execution_result = {
                    "isError": true,
                    "content": [{"type": "text", "text": "Tool did not return a valid dictionary response"}]
                }
            
            tool_called.emit(tool_name, arguments, execution_result)
                
            return {
                "jsonrpc": "2.0",
                "id": id,
                "result": execution_result
            }
        _:
            if has_id:
                return _make_error_dict(id, -32601, "Method not found: %s" % method)
            return null

func _make_error_dict(id: Variant, code: int, message: String) -> Dictionary:
    return {
        "jsonrpc": "2.0",
        "id": id,
        "error": {
            "code": code,
            "message": message
        }
    }

func _send_error(peer: WebSocketPeer, id: Variant, code: int, message: String) -> void:
    var err_dict = _make_error_dict(id, code, message)
    peer.send_text(JSON.stringify(err_dict))
