extends "res://addons/mcp_server/core/mcp_base_transport.gd"

var tcp_server := TCPServer.new()
var connected_peers: Array[WebSocketPeer] = []

func start(port: int, bind_address: String) -> bool:
    if tcp_server.is_listening():
        return true
    var err = tcp_server.listen(port, bind_address)
    if err != OK:
        push_error("[MCP WebSocket Transport] Failed to listen on %s:%d (error code %d)" % [bind_address, port, err])
        return false
    print("[MCP WebSocket Transport] Listening on ws://%s:%d" % [bind_address, port])
    return true

func stop() -> void:
    tcp_server.stop()
    for peer in connected_peers:
        peer.close()
    connected_peers.clear()
    print("[MCP WebSocket Transport] Stopped.")

func poll() -> void:
    # 1. Accept new raw TCP connections and handshake upgrade to WebSocket
    if tcp_server.is_listening() and tcp_server.is_connection_available():
        var tcp_peer = tcp_server.take_connection()
        if tcp_peer:
            var ws_peer = WebSocketPeer.new()
            var err = ws_peer.accept_stream(tcp_peer)
            if err == OK:
                connected_peers.append(ws_peer)
                print("[MCP WebSocket Transport] New client connection pending handshake...")
            else:
                push_error("[MCP WebSocket Transport] Failed to accept WebSocket stream: %d" % err)
                
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
                var session_id = str(peer.get_instance_id())
                message_received.emit(
                    session_id, 
                    text, 
                    func(response_text: String): 
                        if response_text != "" and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
                            peer.send_text(response_text)
                )
        elif state == WebSocketPeer.STATE_CONNECTING:
            active_peers.append(peer)
        elif state == WebSocketPeer.STATE_CLOSING:
            active_peers.append(peer)
        else:
            print("[MCP WebSocket Transport] Client connection closed.")
            
    connected_peers = active_peers

func broadcast(message: Dictionary) -> void:
    var text = JSON.stringify(message)
    for peer in connected_peers:
        if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
            peer.send_text(text)

func send_to_client(session_id: String, message: Dictionary) -> void:
    var text = JSON.stringify(message)
    for peer in connected_peers:
        if str(peer.get_instance_id()) == session_id:
            if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
                peer.send_text(text)
            break
