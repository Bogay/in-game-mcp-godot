extends MCPTool

func get_tool_name() -> String:
    return "get_performance_metrics"

func get_description() -> String:
    return "Returns real-time engine performance metrics and telemetry (FPS, memory usage, node count, draw calls)."

func get_input_schema() -> Dictionary:
    # No inputs required, returns current metrics
    return {
        "type": "object",
        "properties": {},
        "required": []
    }

func execute(_args: Dictionary) -> Dictionary:
    var metrics = {}
    
    if Engine.is_editor_hint():
        metrics["mode"] = "editor"
    else:
        metrics["mode"] = "game"
        
    metrics["fps"] = Performance.get_monitor(Performance.TIME_FPS)
    metrics["process_time_seconds"] = Performance.get_monitor(Performance.TIME_PROCESS)
    metrics["physics_process_time_seconds"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
    
    # Memory Metrics
    metrics["static_memory_bytes"] = Performance.get_monitor(Performance.MEMORY_STATIC)
    metrics["static_memory_max_bytes"] = Performance.get_monitor(Performance.MEMORY_STATIC_MAX)
    
    # Scene/Object Count Metrics
    metrics["node_count"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
    metrics["orphan_node_count"] = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
    metrics["object_count"] = Performance.get_monitor(Performance.OBJECT_COUNT)
    
    # Rendering Metrics
    metrics["draw_calls_per_frame"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
    metrics["video_memory_used_bytes"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
    
    # General Info
    metrics["godot_version"] = Engine.get_version_info()["string"]
    metrics["target_fps"] = Engine.max_fps
    
    return {
        "isError": false,
        "content": [
            {
                "type": "text",
                "text": JSON.stringify(metrics, "  ")
            }
        ]
    }
