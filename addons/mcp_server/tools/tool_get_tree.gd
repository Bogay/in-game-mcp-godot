extends MCPTool

func get_tool_name() -> String:
    return "get_scene_tree"

func get_description() -> String:
    return "Lists the active scene tree node hierarchy with strict depth-limiting, class filtering, and pagination."

func get_input_schema() -> Dictionary:
    return {
        "type": "object",
        "properties": {
            "root_path": {
                "type": "string",
                "description": "Absolute path to start listing from (e.g. '/root' or a relative path from the tool). Defaults to the scene root."
            },
            "max_depth": {
                "type": "integer",
                "description": "Maximum tree depth to search. Default is 2. Max is 5.",
                "default": 2
            },
            "node_type": {
                "type": "string",
                "description": "Filter by class name (e.g., 'CharacterBody2D', 'Sprite3D')."
            },
            "group": {
                "type": "string",
                "description": "Filter by group name."
            },
            "page": {
                "type": "integer",
                "description": "Page number to return (1-indexed). Defaults to 1.",
                "default": 1
            },
            "page_size": {
                "type": "integer",
                "description": "Number of results per page. Default 50. Max 100.",
                "default": 50
            }
        },
        "required": []
    }

func execute(args: Dictionary) -> Dictionary:
    # 1. Resolve root node
    var root_path = args.get("root_path", "")
    var root_node: Node = null
    
    if root_path != "":
        root_node = get_node_or_null(root_path)
        if not root_node and is_inside_tree():
            root_node = get_tree().root.get_node_or_null(root_path)
    else:
        if is_inside_tree():
            root_node = get_tree().root
            # If there is a current scene, start there instead of raw Viewport root for a cleaner list
            if get_tree().current_scene:
                root_node = get_tree().current_scene
                
    if not root_node:
        return {
            "isError": true,
            "content": [{"type": "text", "text": "Root path '%s' could not be resolved." % root_path}]
        }
        
    # 2. Extract arguments
    var max_depth: int = clampi(int(args.get("max_depth", 2)), 1, 5)
    var node_type: String = args.get("node_type", "")
    var group: String = args.get("group", "")
    var page: int = max(1, int(args.get("page", 1)))
    var page_size: int = clampi(int(args.get("page_size", 50)), 1, 100)
    
    # 3. Recursively collect nodes
    var collected: Array[Dictionary] = []
    _traverse(root_node, 0, max_depth, node_type, group, collected)
    
    # 4. Paginate results
    var total_items = collected.size()
    var total_pages = int(ceil(float(total_items) / page_size))
    if total_pages == 0:
        total_pages = 1
        
    var start_idx = (page - 1) * page_size
    var paginated: Array = []
    
    if start_idx < total_items:
        var end_idx = min(start_idx + page_size, total_items)
        paginated = collected.slice(start_idx, end_idx)
        
    var result_metadata = {
        "page": page,
        "page_size": page_size,
        "total_items": total_items,
        "total_pages": total_pages,
        "nodes": paginated
    }
    
    return {
        "isError": false,
        "content": [
            {
                "type": "text",
                "text": JSON.stringify(result_metadata, "  ")
            }
        ]
    }

func _traverse(node: Node, current_depth: int, max_depth: int, type_filter: String, group_filter: String, collected: Array[Dictionary]) -> void:
    if not node:
        return
        
    # Check filters
    var match_type = true
    if type_filter != "":
        match_type = node.is_class(type_filter) or (node.get_script() and node.get_script().get_instance_base_type() == type_filter)
        
    var match_group = true
    if group_filter != "":
        match_group = node.is_in_group(group_filter)
        
    if match_type and match_group:
        var info = {
            "name": node.name,
            "path": str(node.get_path()),
            "class": node.get_class(),
            "child_count": node.get_child_count(),
            "has_script": node.get_script() != null
        }
        collected.append(info)
        
    if current_depth < max_depth:
        for child in node.get_children():
            _traverse(child, current_depth + 1, max_depth, type_filter, group_filter, collected)
