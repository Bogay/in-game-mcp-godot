extends Node
class_name MCPTool

func get_tool_name() -> String:
    return "unnamed_tool"

func get_description() -> String:
    return "No description."

func get_input_schema() -> Dictionary:
    return { "type": "object", "properties": {}, "required": [] }

func execute(_args: Dictionary) -> Dictionary:
    return { "isError": true, "content": [{"type": "text", "text": "Not Implemented"}] }

func get_tool_metadata() -> Dictionary:
    return {}

func to_manifest() -> Dictionary:
    var manifest = {
        "name": get_tool_name(),
        "description": get_description(),
        "inputSchema": get_input_schema()
    }
    var meta = get_tool_metadata()
    if not meta.is_empty():
        manifest["_meta"] = meta
    return manifest
