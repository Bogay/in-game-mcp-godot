extends Node
class_name MCPCommandGroup

## Optional prefix to prepend to all tools in this group (e.g., "admin_" -> "admin_kick")
@export var prefix: String = ""

## A short description explaining what this group of tools is for
@export_multiline var description: String = ""

## Scans child nodes to collect all tools belonging to this group.
func get_tools() -> Array[Node]:
    var tools: Array[Node] = []
    for child in get_children():
        if child.has_method("get_tool_name") and child.has_method("execute"):
            tools.append(child)
    return tools
