extends MCPTool
class_name DynamicMCPTool

var _tool_name: String
var _description: String
var _schema: Dictionary
var _target: Callable
var _metadata: Dictionary

func _init(p_tool_name: String, p_description: String, p_schema: Dictionary, p_target: Callable, p_metadata: Dictionary = {}) -> void:
    _tool_name = p_tool_name
    _description = p_description
    _schema = p_schema
    _target = p_target
    _metadata = p_metadata

func get_tool_name() -> String:
    return _tool_name

func get_description() -> String:
    return _description

func get_tool_metadata() -> Dictionary:
    return _metadata

func get_input_schema() -> Dictionary:
    if _schema.is_empty() or not _schema.has("type"):
        var full_schema = { "type": "object", "properties": {}, "required": [] }
        full_schema.merge(_schema, true)
        return full_schema
    return _schema

func execute(args: Dictionary) -> Dictionary:
    if not _target.is_valid():
        return {
            "isError": true,
            "content": [{"type": "text", "text": "Target Callable is no longer valid or has been freed."}]
        }
    
    @warning_ignore("redundant_await")
    var result = await _target.call(args)
    
    if result is Dictionary:
        return result
        
    return {
        "isError": false,
        "content": [{"type": "text", "text": str(result)}]
    }
