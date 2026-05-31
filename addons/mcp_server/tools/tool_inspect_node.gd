extends MCPTool

func get_tool_name() -> String:
    return "inspect_node"

func get_description() -> String:
    return "Inspects the runtime state, groups, and properties of a specific Node in the scene tree."

func get_input_schema() -> Dictionary:
    return {
        "type": "object",
        "properties": {
            "node_path": {
                "type": "string",
                "description": "Absolute path to the node to inspect (e.g., '/root/Main/Player')."
            },
            "filter": {
                "type": "string",
                "description": "Property filter mode: 'script_only' (shows script variables, default), 'essential' (script variables + position/rotation/scale), 'all' (all engine properties).",
                "default": "script_only"
            }
        },
        "required": ["node_path"]
    }

func execute(args: Dictionary) -> Dictionary:
    var node_path = args.get("node_path", "")
    if node_path == "":
        return {
            "isError": true,
            "content": [{"type": "text", "text": "Argument 'node_path' is required."}]
        }
        
    var node: Node = null
    if is_inside_tree():
        node = get_node_or_null(node_path)
        if not node:
            node = get_tree().root.get_node_or_null(node_path)
            
    if not node:
        return {
            "isError": true,
            "content": [{"type": "text", "text": "Node at path '%s' not found." % node_path}]
        }
        
    var filter_mode = args.get("filter", "script_only")
    
    # Collect metadata
    var info = {
        "name": node.name,
        "path": str(node.get_path()),
        "class": node.get_class(),
        "groups": node.get_groups(),
        "script": str(node.get_script()) if node.get_script() else null,
        "properties": {}
    }
    
    # Collect properties based on filter
    var properties = {}
    var essential_keys = ["position", "rotation", "scale", "visible", "velocity", "rotation_degrees", "global_position"]
    
    for prop in node.get_property_list():
        var name = prop.get("name", "")
        var usage = prop.get("usage", 0)
        
        if name == "" or name.begins_with("metadata/") or name == "script":
            continue
            
        var is_script_var = (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) > 0
        var is_essential = name in essential_keys
        
        var should_include = false
        if filter_mode == "all":
            should_include = (usage & PROPERTY_USAGE_DEFAULT) > 0 or is_script_var
        elif filter_mode == "essential":
            should_include = is_script_var or is_essential
        else: # script_only
            should_include = is_script_var
            
        if should_include:
            var val = node.get(name)
            properties[name] = _serialize_variant(val)
            
    info["properties"] = properties
    
    return {
        "isError": false,
        "content": [
            {
                "type": "text",
                "text": JSON.stringify(info, "  ")
            }
        ]
    }

func _serialize_variant(val: Variant) -> Variant:
    match typeof(val):
        TYPE_NIL:
            return null
        TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
            return val
        TYPE_VECTOR2, TYPE_VECTOR2I:
            return [val.x, val.y]
        TYPE_VECTOR3, TYPE_VECTOR3I:
            return [val.x, val.y, val.z]
        TYPE_VECTOR4, TYPE_VECTOR4I:
            return [val.x, val.y, val.z, val.w]
        TYPE_COLOR:
            return { "r": val.r, "g": val.g, "b": val.b, "a": val.a, "hex": val.to_html() }
        TYPE_RECT2, TYPE_RECT2I:
            return { "position": [val.position.x, val.position.y], "size": [val.size.x, val.size.y] }
        TYPE_TRANSFORM2D:
            return { "x": [val.x.x, val.x.y], "y": [val.y.x, val.y.y], "origin": [val.origin.x, val.origin.y] }
        TYPE_TRANSFORM3D:
            return {
                "basis": [[val.basis.x.x, val.basis.x.y, val.basis.x.z], [val.basis.y.x, val.basis.y.y, val.basis.y.z], [val.basis.z.x, val.basis.z.y, val.basis.z.z]],
                "origin": [val.origin.x, val.origin.y, val.origin.z]
            }
        TYPE_QUATERNION:
            return [val.x, val.y, val.z, val.w]
        TYPE_ARRAY:
            var arr = []
            for item in val:
                arr.append(_serialize_variant(item))
            return arr
        TYPE_DICTIONARY:
            var dict = {}
            for key in val:
                dict[str(key)] = _serialize_variant(val[key])
            return dict
        TYPE_OBJECT:
            if val == null:
                return null
            return { "class": val.get_class(), "id": val.get_instance_id(), "name": val.name if "name" in val else "" }
        _:
            return str(val)
