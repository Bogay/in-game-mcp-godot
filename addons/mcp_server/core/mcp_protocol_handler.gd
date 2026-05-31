extends RefCounted

signal tool_called(tool_name: String, arguments: Dictionary, response: Dictionary)

# Handshake states: 0 = Uninitialized, 1 = Initializing, 2 = Initialized
var handshake_states: Dictionary = {}

var tool_registry: RefCounted

func _init(p_tool_registry: RefCounted) -> void:
    tool_registry = p_tool_registry

func process_message(session_id: String, text: String) -> String:
    var json = JSON.new()
    var err = json.parse(text)
    if err != OK:
        var err_dict = _make_error_dict(null, -32700, "Parse error: " + json.get_error_message())
        return JSON.stringify(err_dict)
        
    var data = json.get_data()
    if data is Array:
        # Batch Request processing
        var responses: Array = []
        for item in data:
            if item is Dictionary:
                var resp = await _process_single_message(session_id, item)
                if resp != null:
                    responses.append(resp)
        if not responses.is_empty():
            return JSON.stringify(responses)
    elif data is Dictionary:
        # Single Request/Notification processing
        var resp = await _process_single_message(session_id, data)
        if resp != null:
            return JSON.stringify(resp)
            
    return ""

func _process_single_message(session_id: String, message: Dictionary) -> Variant:
    if message.get("jsonrpc", "") != "2.0":
        return _make_error_dict(message.get("id"), -32600, "Invalid Request: Missing or invalid jsonrpc version")
        
    var method = message.get("method", "")
    if method == "":
        return _make_error_dict(message.get("id"), -32600, "Invalid Request: Missing method name")
        
    var has_id = message.has("id")
    var id = message.get("id")
    
    # Determine current handshake state
    var current_state = handshake_states.get(session_id, 0)
        
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
            
            handshake_states[session_id] = 1
                    
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
            handshake_states[session_id] = 2
            return null
        "tools/list":
            if not has_id:
                return null
            return {
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "tools": tool_registry.cached_manifests
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
                
            if not tool_registry.available_tools.has(tool_name):
                return _make_error_dict(id, -32601, "Method not found: Tool '%s' is not registered" % tool_name)
                
            var tool = tool_registry.available_tools[tool_name]
            var execution_result = await tool_registry.execute_duck_tool(tool, arguments)
            
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
