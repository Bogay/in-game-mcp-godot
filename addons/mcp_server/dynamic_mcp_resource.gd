extends "res://addons/mcp_server/core/mcp_resource.gd"
class_name DynamicMCPResource

var _uri: String
var _name: String
var _mime_type: String
var _description: String
var _read_callback: Callable

func _init(p_uri: String, p_name: String, p_mime_type: String, p_description: String, p_read_callback: Callable) -> void:
    _uri = p_uri
    _name = p_name
    _mime_type = p_mime_type
    _description = p_description
    _read_callback = p_read_callback

func get_uri() -> String:
    return _uri

func get_name() -> String:
    return _name

func get_mime_type() -> String:
    return _mime_type

func get_description() -> String:
    return _description

func read() -> Dictionary:
    if not _read_callback.is_valid():
        return { "text": "Read callback is invalid or has been freed." }
        
    @warning_ignore("redundant_await")
    var result = await _read_callback.call()
    
    if result is Dictionary:
        return result
    elif result is String:
        return { "text": result }
    elif result is PackedByteArray:
        return { "blob": Marshalls.raw_to_base64(result) }
        
    return { "text": str(result) }
