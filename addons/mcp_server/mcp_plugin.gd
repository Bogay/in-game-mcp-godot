@tool
extends EditorPlugin

const AUTOLOAD_NAME = "MCPServer"
const AUTOLOAD_PATH = "res://addons/mcp_server/mcp_server.gd"

func _enter_tree() -> void:
    add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
    _add_project_settings()
    print("[MCP Server Plugin] Registered Autoload singleton: ", AUTOLOAD_NAME)

func _exit_tree() -> void:
    remove_autoload_singleton(AUTOLOAD_NAME)
    print("[MCP Server Plugin] Unregistered Autoload singleton: ", AUTOLOAD_NAME)

func _add_project_settings() -> void:
    _add_setting("mcp_server/transport", "SSE", TYPE_STRING, PROPERTY_HINT_ENUM, "WebSocket,SSE")
    _add_setting("mcp_server/port", 9090, TYPE_INT, PROPERTY_HINT_RANGE, "1,65535")
    _add_setting("mcp_server/bind_address", "127.0.0.1", TYPE_STRING)
    _add_setting("mcp_server/allowed_hosts", PackedStringArray(["localhost", "127.0.0.1", "[::1]", "::1"]), TYPE_PACKED_STRING_ARRAY)
    _add_setting("mcp_server/auto_start", true, TYPE_BOOL)
    _add_setting("mcp_server/conformance_mode", false, TYPE_BOOL)
    ProjectSettings.save()

func _add_setting(name: String, default_value: Variant, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
    if not ProjectSettings.has_setting(name):
        ProjectSettings.set_setting(name, default_value)
    
    var info = {
        "name": name,
        "type": type,
        "hint": hint,
        "hint_string": hint_string
    }
    ProjectSettings.add_property_info(info)
    ProjectSettings.set_initial_value(name, default_value)
