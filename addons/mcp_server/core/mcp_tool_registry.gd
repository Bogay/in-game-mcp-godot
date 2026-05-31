extends RefCounted

signal tools_changed()

## Registered tools registry: tool_name -> Object/Node (duck-typed)
var available_tools: Dictionary = {}

## Cached tool manifests list
var cached_manifests: Array = []

var _tool_name_regex: RegEx

# Nested ProxyMCPTool helper
class ProxyMCPTool extends MCPTool:
    var _base_tool: Object
    var _custom_name: String
    
    func _init(base_tool: Object, custom_name: String) -> void:
        _base_tool = base_tool
        _custom_name = custom_name
        
    func get_tool_name() -> String:
        return _custom_name
        
    func get_description() -> String:
        if _base_tool.has_method("get_description"):
            return _base_tool.get_description()
        elif _base_tool.has_method("GetDescription"):
            return _base_tool.GetDescription()
        return "No description."
        
    func get_input_schema() -> Dictionary:
        var schema: Dictionary = {}
        if _base_tool.has_method("get_input_schema"):
            schema = _base_tool.get_input_schema()
        elif _base_tool.has_method("GetInputSchema"):
            schema = _base_tool.GetInputSchema()
        else:
            return { "type": "object", "properties": {}, "required": [] }
            
        if schema.is_empty() or not schema.has("type"):
            var full_schema = { "type": "object", "properties": {}, "required": [] }
            full_schema.merge(schema, true)
            return full_schema
        return schema
        
    func execute(args: Dictionary) -> Dictionary:
        if _base_tool.has_method("execute"):
            @warning_ignore("redundant_await")
            return await _base_tool.execute(args)
        elif _base_tool.has_method("Execute"):
            @warning_ignore("redundant_await")
            return await _base_tool.Execute(args)
        return { "isError": true, "content": [{"type": "text", "text": "Not Implemented"}] }

func _init() -> void:
    _tool_name_regex = RegEx.new()
    _tool_name_regex.compile("^[a-zA-Z0-9_-]+$")

func register_tool(tool: Object) -> void:
    if not tool:
        push_error("[MCP Tool Registry] Cannot register null tool.")
        return
    if not ((tool.has_method("execute") or tool.has_method("Execute")) and (tool.has_method("get_tool_name") or tool.has_method("GetToolName"))):
        push_error("[MCP Tool Registry] Tool registration failed. Object must implement get_tool_name and execute methods.")
        return
    var tool_name = _get_duck_tool_name(tool)
    if not _validate_tool_name(tool_name):
        push_error("[MCP Tool Registry] Tool registration failed. Tool name '%s' must match '^[a-zA-Z0-9_-]{1,64}$'." % tool_name)
        return
    available_tools[tool_name] = tool
    _rebuild_manifests()

func unregister_tool(tool: Object) -> void:
    if not tool:
        return
    var tool_name = _get_duck_tool_name(tool)
    if available_tools.has(tool_name) and available_tools[tool_name] == tool:
        available_tools.erase(tool_name)
        _rebuild_manifests()

func unregister_tool_name(tool_name: String) -> void:
    if available_tools.has(tool_name):
        available_tools.erase(tool_name)
        _rebuild_manifests()

func register_function(tool_name: String, desc: String, schema: Dictionary, target: Callable) -> void:
    if not _validate_tool_name(tool_name):
        push_error("[MCP Tool Registry] Function registration failed. Tool name '%s' must match '^[a-zA-Z0-9_-]{1,64}$'." % tool_name)
        return
    var dynamic_tool = DynamicMCPTool.new(tool_name, desc, schema, target)
    available_tools[tool_name] = dynamic_tool
    cached_manifests.append(dynamic_tool.to_manifest())
    tools_changed.emit()

func register_command_group(group: MCPCommandGroup) -> void:
    if not group:
        return
    for tool in group.get_tools():
        var tool_name = _get_duck_tool_name(tool)
        if group.prefix != "":
            tool_name = group.prefix + tool_name
        if not _validate_tool_name(tool_name):
            push_error("[MCP Tool Registry] Command group tool registration failed. Tool name '%s' must match '^[a-zA-Z0-9_-]{1,64}$'." % tool_name)
            continue
        var proxy = ProxyMCPTool.new(tool, tool_name)
        available_tools[tool_name] = proxy
    _rebuild_manifests()

func unregister_command_group(group: MCPCommandGroup) -> void:
    if not group:
        return
    var changed := false
    for tool in group.get_tools():
        var tool_name = _get_duck_tool_name(tool)
        if group.prefix != "":
            tool_name = group.prefix + tool_name
        if available_tools.has(tool_name):
            available_tools.erase(tool_name)
            changed = true
    if changed:
        _rebuild_manifests()

func _validate_tool_name(tool_name: String) -> bool:
    if tool_name.length() == 0 or tool_name.length() > 64:
        return false
    return _tool_name_regex.search(tool_name) != null

func _rebuild_manifests() -> void:
    cached_manifests.clear()
    for tool_name in available_tools:
        var tool = available_tools[tool_name]
        cached_manifests.append(_get_duck_manifest(tool))
    tools_changed.emit()

func _get_duck_tool_name(tool: Object) -> String:
    if tool.has_method("get_tool_name"):
        return tool.get_tool_name()
    elif tool.has_method("GetToolName"):
        return tool.GetToolName()
    return "unnamed_tool"

func _get_duck_description(tool: Object) -> String:
    if tool.has_method("get_description"):
        return tool.get_description()
    elif tool.has_method("GetDescription"):
        return tool.GetDescription()
    return "No description."

func _get_duck_input_schema(tool: Object) -> Dictionary:
    var schema: Dictionary = {}
    if tool.has_method("get_input_schema"):
        schema = tool.get_input_schema()
    elif tool.has_method("GetInputSchema"):
        schema = tool.GetInputSchema()
    else:
        return { "type": "object", "properties": {}, "required": [] }
        
    if schema.is_empty() or not schema.has("type"):
        var full_schema = { "type": "object", "properties": {}, "required": [] }
        full_schema.merge(schema, true)
        return full_schema
    return schema

func _get_duck_manifest(tool: Object) -> Dictionary:
    if tool.has_method("to_manifest"):
        return tool.to_manifest()
    elif tool.has_method("ToManifest"):
        return tool.ToManifest()
    return {
        "name": _get_duck_tool_name(tool),
        "description": _get_duck_description(tool),
        "inputSchema": _get_duck_input_schema(tool)
    }

func execute_duck_tool(tool: Object, args: Dictionary) -> Dictionary:
    if tool.has_method("execute"):
        @warning_ignore("redundant_await")
        return await tool.execute(args)
    elif tool.has_method("Execute"):
        @warning_ignore("redundant_await")
        return await tool.Execute(args)
    return { "isError": true, "content": [{"type": "text", "text": "Not Implemented"}] }
