@tool
extends EditorPlugin

const AUTOLOAD_NAME = "MCPServer"
const AUTOLOAD_PATH = "res://addons/mcp_server/mcp_server.gd"

func _enter_tree() -> void:
    add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
    print("[MCP Server Plugin] Registered Autoload singleton: ", AUTOLOAD_NAME)

func _exit_tree() -> void:
    remove_autoload_singleton(AUTOLOAD_NAME)
    print("[MCP Server Plugin] Unregistered Autoload singleton: ", AUTOLOAD_NAME)
