extends "res://addons/mcp_server/core/mcp_base_transport.gd"

var tcp_server := TCPServer.new()
var pending_http_clients: Array = []
var sse_sessions: Dictionary = {}

func start(port: int, bind_address: String) -> bool:
    if tcp_server.is_listening():
        return true
    var err = tcp_server.listen(port, bind_address)
    if err != OK:
        push_error("[MCP SSE Transport] Failed to listen on %s:%d (error code %d)" % [bind_address, port, err])
        return false
    print("[MCP SSE Transport] Listening on http://%s:%d/sse" % [bind_address, port])
    return true

func stop() -> void:
    tcp_server.stop()
    for client in pending_http_clients:
        var socket = client.socket as StreamPeerTCP
        socket.disconnect_from_host()
    pending_http_clients.clear()
    
    for sid in sse_sessions:
        var peer = sse_sessions[sid] as StreamPeerTCP
        peer.disconnect_from_host()
    sse_sessions.clear()
    print("[MCP SSE Transport] Stopped.")

func poll() -> void:
    # 1. Accept new incoming HTTP connections
    if tcp_server.is_listening() and tcp_server.is_connection_available():
        var tcp_peer = tcp_server.take_connection()
        if tcp_peer:
            pending_http_clients.append({
                "socket": tcp_peer,
                "buffer": PackedByteArray(),
                "header_parsed": false,
                "content_length": 0,
                "method": "",
                "path": "",
                "session_id": "",
                "host": "",
                "origin": ""
            })
            
    # 2. Poll and parse pending HTTP client request streams
    var still_pending: Array = []
    for client in pending_http_clients:
        var socket = client.socket as StreamPeerTCP
        socket.poll()
        var status = socket.get_status()
        if status != StreamPeerTCP.STATUS_CONNECTED:
            continue
            
        var avail = socket.get_available_bytes()
        if avail > 0:
            var read_res = socket.get_partial_data(avail)
            if read_res[0] == OK:
                client.buffer.append_array(read_res[1])
                
        if not client.header_parsed:
            var header_end = _find_double_newline(client.buffer)
            if header_end != -1:
                var header_bytes = client.buffer.slice(0, header_end)
                var header_str = header_bytes.get_string_from_utf8()
                client.buffer = client.buffer.slice(header_end + 4)
                client.header_parsed = true
                _parse_http_header(client, header_str)
                
        if client.header_parsed:
            if not _validate_host_and_origin(client):
                var origin = client.get("origin", "*") as String
                if origin == "":
                    origin = "*"
                var forbidden_resp = (
                    "HTTP/1.1 403 Forbidden\r\n" +
                    "Access-Control-Allow-Origin: " + origin + "\r\n" +
                    "Access-Control-Allow-Headers: *\r\n" +
                    "Access-Control-Allow-Methods: *\r\n" +
                    "Access-Control-Allow-Credentials: true\r\n" +
                    "Content-Length: 9\r\n" +
                    "Connection: close\r\n\r\n" +
                    "Forbidden"
                )
                socket.put_data(forbidden_resp.to_utf8_buffer())
                socket.disconnect_from_host()
                continue
                
            var is_options = (client.method == "OPTIONS")
            var is_get_sse = (client.method == "GET" and client.path.begins_with("/sse"))
            var is_post_msg = (client.method == "POST" and (client.path.begins_with("/message") or client.path.begins_with("/sse")))
            
            if is_options:
                _send_http_options_response(socket, client)
                continue
            elif is_get_sse:
                _upgrade_to_sse(client)
                continue
            elif is_post_msg:
                if client.buffer.size() >= client.content_length:
                    var body_bytes = client.buffer.slice(0, client.content_length)
                    var body_str = body_bytes.get_string_from_utf8()
                    _handle_http_post_async(client, body_str)
                    continue
            else:
                var origin = client.get("origin", "*") as String
                if origin == "":
                    origin = "*"
                var err_resp = (
                    "HTTP/1.1 404 Not Found\r\n" +
                    "Access-Control-Allow-Origin: " + origin + "\r\n" +
                    "Access-Control-Allow-Headers: *\r\n" +
                    "Access-Control-Allow-Methods: *\r\n" +
                    "Access-Control-Allow-Credentials: true\r\n" +
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
            elif key == "host":
                client.host = val
            elif key == "origin":
                client.origin = val

func _send_http_options_response(socket: StreamPeerTCP, client: Dictionary) -> void:
    var origin = client.get("origin", "*") as String
    if origin == "":
        origin = "*"
    var resp = (
        "HTTP/1.1 204 No Content\r\n" +
        "Access-Control-Allow-Origin: " + origin + "\r\n" +
        "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" +
        "Access-Control-Allow-Headers: *\r\n" +
        "Access-Control-Allow-Credentials: true\r\n" +
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
        
    var origin = client.get("origin", "*") as String
    if origin == "":
        origin = "*"
        
    var resp = (
        "HTTP/1.1 200 OK\r\n" +
        "Content-Type: text/event-stream\r\n" +
        "Cache-Control: no-cache\r\n" +
        "Connection: keep-alive\r\n" +
        "Access-Control-Allow-Origin: " + origin + "\r\n" +
        "Access-Control-Allow-Headers: *\r\n" +
        "Access-Control-Allow-Methods: *\r\n" +
        "Access-Control-Allow-Credentials: true\r\n\r\n"
    )
    socket.put_data(resp.to_utf8_buffer())
    
    var is_new_legacy = (_get_session_id(client) == "")
    if is_new_legacy:
        var endpoint_event = "event: endpoint\ndata: /message?sessionId=" + session_id + "\n\n"
        socket.put_data(endpoint_event.to_utf8_buffer())
        
    sse_sessions[session_id] = socket
    print("[MCP SSE Transport] Upgraded client connection to HTTP/SSE. Session ID: ", session_id)

func _handle_http_post_async(client: Dictionary, body_str: String) -> void:
    var socket = client.socket as StreamPeerTCP
    var path = client.path as String
    var session_id = _get_session_id(client)
    var is_legacy = path.begins_with("/message")
    
    var origin = client.get("origin", "*") as String
    if origin == "":
        origin = "*"
        
    if is_legacy:
        if session_id == "" or not sse_sessions.has(session_id):
            var err_resp = (
                "HTTP/1.1 400 Bad Request\r\n" +
                "Access-Control-Allow-Origin: " + origin + "\r\n" +
                "Access-Control-Allow-Headers: *\r\n" +
                "Access-Control-Allow-Methods: *\r\n" +
                "Access-Control-Allow-Credentials: true\r\n" +
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
            "Access-Control-Allow-Origin: " + origin + "\r\n" +
            "Access-Control-Allow-Headers: *\r\n" +
            "Access-Control-Allow-Methods: *\r\n" +
            "Access-Control-Allow-Credentials: true\r\n" +
            "Content-Length: 0\r\n" +
            "Connection: close\r\n\r\n"
        )
        socket.put_data(resp.to_utf8_buffer())
        socket.disconnect_from_host()
        
        message_received.emit(
            session_id,
            body_str,
            func(response_text: String):
                var json = JSON.new()
                if json.parse(response_text) == OK:
                    _send_to_sse(session_id, json.get_data())
        )
    else:
        # Streamable HTTP (unified endpoint POST to /sse)
        if session_id == "":
            session_id = str(randi() % 1000000)
            
        message_received.emit(
            session_id,
            body_str,
            func(response_text: String):
                _send_http_post_response(socket, session_id, response_text, origin)
        )

func _send_http_post_response(socket: StreamPeerTCP, session_id: String, response_text: String, origin: String = "*") -> void:
    var resp_body = response_text
    var status_line = "HTTP/1.1 200 OK\r\n"
    if resp_body == "":
        status_line = "HTTP/1.1 202 Accepted\r\n"
        
    var http_resp = (
        status_line +
        "Content-Type: application/json\r\n" +
        "Content-Length: " + str(resp_body.to_utf8_buffer().size()) + "\r\n" +
        "Mcp-Session-Id: " + session_id + "\r\n" +
        "Access-Control-Allow-Origin: " + origin + "\r\n" +
        "Access-Control-Allow-Headers: *\r\n" +
        "Access-Control-Allow-Methods: *\r\n" +
        "Access-Control-Allow-Credentials: true\r\n" +
        "Connection: close\r\n\r\n" +
        resp_body
    )
    socket.put_data(http_resp.to_utf8_buffer())
    socket.disconnect_from_host()

func _send_to_sse(session_id: String, payload: Variant) -> void:
    var msg = "event: message\ndata: " + JSON.stringify(payload) + "\n\n"
    var raw_data = msg.to_utf8_buffer()
    
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

func broadcast(message: Dictionary) -> void:
    _send_to_sse("", message)

func send_to_client(session_id: String, message: Dictionary) -> void:
    _send_to_sse(session_id, message)

func _validate_host_and_origin(client: Dictionary) -> bool:
    var host_val = client.get("host", "") as String
    var origin_val = client.get("origin", "") as String
    
    if host_val != "" and not _is_allowed_host(host_val):
        return false
    if origin_val != "" and not _is_allowed_host(origin_val):
        return false
        
    return true

func _is_allowed_host(val: String) -> bool:
    var clean = val.strip_edges().to_lower()
    if clean == "":
        return true
        
    # Strip scheme if present
    if clean.begins_with("http://"):
        clean = clean.substr(7)
    elif clean.begins_with("https://"):
        clean = clean.substr(8)
        
    # Extract host part (remove port)
    var host_part = clean
    if clean.begins_with("["):
        var close_bracket = clean.find("]")
        if close_bracket != -1:
            host_part = clean.substr(0, close_bracket + 1)
        else:
            host_part = clean
    else:
        var colon = clean.find(":")
        if colon != -1:
            host_part = clean.substr(0, colon)
            
    # Remove brackets for comparison
    var host_unbracketed = host_part
    if host_part.begins_with("[") and host_part.ends_with("]"):
        host_unbracketed = host_part.substr(1, host_part.length() - 2)
        
    for allowed in MCPServer.allowed_hosts:
        var allowed_clean = allowed.strip_edges().to_lower()
        if allowed_clean == "*" or host_part == allowed_clean or host_unbracketed == allowed_clean:
            return true
            
    return false
