extends RefCounted

# Emitted when a client message is received.
# The responder callable should be called with the response string (if any).
signal message_received(session_id: String, text: String, responder: Callable)

func start(_port: int, _bind_address: String) -> bool:
    return false

func stop() -> void:
    pass

func poll() -> void:
    pass
