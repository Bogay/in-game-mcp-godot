extends Node

## Example scene script demonstrating how to register tools with the MCPServer Autoload.

func _ready() -> void:
    # 1. Register the pre-packaged static tools
    # It is recommended to add tools as children of this node so their lifecycle is managed.
    var tree_tool = load("res://addons/mcp_server/tools/tool_get_tree.gd").new()
    add_child(tree_tool)
    MCPServer.register_tool(tree_tool)
    
    var inspect_tool = load("res://addons/mcp_server/tools/tool_inspect_node.gd").new()
    add_child(inspect_tool)
    MCPServer.register_tool(inspect_tool)
    
    var metrics_tool = load("res://addons/mcp_server/tools/tool_get_metrics.gd").new()
    add_child(metrics_tool)
    MCPServer.register_tool(metrics_tool)
    
    # 2. Register a dynamic lambda tool using the first-class Callable wrapper
    MCPServer.register_function(
        "spawn_item",
        "Spawns a specific item at a target coordinate.",
        {
            "type": "object",
            "properties": {
                "item_id": { "type": "string", "description": "The identifier of the item to spawn" },
                "count": { "type": "integer", "description": "The quantity to spawn", "default": 1 },
                "position": {
                    "type": "array",
                    "items": { "type": "number" },
                    "description": "Optional X/Y coordinates as a 2-element array [x, y]"
                }
            },
            "required": ["item_id"]
        },
        _on_spawn_item # Can point to a method or pass a direct lambda: func(args): ...
    )
    
    # 3. Register a command group to group tools under a common prefix namespace
    var admin_group = MCPCommandGroup.new()
    admin_group.prefix = "admin/"
    admin_group.description = "Administrator and debugging controls."
    add_child(admin_group)
    
    # Create a simple custom tool inside the admin group
    var restart_tool = RestartGameTool.new()
    admin_group.add_child(restart_tool)
    
    # Registering the group will register 'restart_tool' under the name "admin/restart_game"
    MCPServer.register_command_group(admin_group)
    
    # 4. Register a dynamic resource demonstrating state observation
    MCPServer.register_dynamic_resource(
        "godot://game/status",
        "Godot Game Status",
        "application/json",
        "Live status metrics of the Godot engine instance.",
        func() -> String:
            var status = {
                "fps": Engine.get_frames_per_second(),
                "static_memory": OS.get_static_memory_usage(),
                "time": Time.get_time_string_from_system()
            }
            return JSON.stringify(status)
    )
    
    print("[MCP Example] Sample registrations completed successfully.")

func _on_spawn_item(args: Dictionary) -> Dictionary:
    var item_id = args.get("item_id", "potion")
    var count = int(args.get("count", 1))
    var pos_arr = args.get("position", [0.0, 0.0])
    
    var target_pos = Vector2(pos_arr[0], pos_arr[1])
    
    # Safe deferral pattern (Execution Rule):
    # Altering the active scene state must occur deferred or on the next idle frame.
    call_deferred("_deferred_spawn", item_id, count, target_pos)
    
    return {
        "isError": false,
        "content": [
            {
                "type": "text",
                "text": "Spawn request accepted. Spawning %d instance(s) of '%s' at position %s." % [count, item_id, target_pos]
            }
        ]
    }

func _deferred_spawn(item_id: String, count: int, pos: Vector2) -> void:
    # Perform actual scene modification here:
    print("[MCP Demo] Spawning %d of %s at %s" % [count, item_id, pos])


# --- Inline Custom Tool class for the group demo ---
class RestartGameTool extends MCPTool:
    func get_tool_name() -> String:
        return "restart_game"
        
    func get_description() -> String:
        return "Reboots the current scene tree to its initial state."
        
    func execute(_args: Dictionary) -> Dictionary:
        # Execution Rule: Defer scene reloading to avoid mid-frame errors
        get_tree().call_deferred("reload_current_scene")
        return {
            "isError": false,
            "content": [{"type": "text", "text": "Game scene reload has been deferred to the next frame."}]
        }
