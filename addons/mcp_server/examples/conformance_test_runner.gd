extends Node

func _ready() -> void:
    print("[Conformance Runner] Starting test environment...")
    
    # 1. Enable conformance mode to advertise prompts/resources and enable mock behaviors
    MCPServer.conformance_mode = true
    
    # 2. Register all conformance mock tools
    _register_conformance_tools()
    
    print("[Conformance Runner] Ready. Waiting for conformance tests to connect on port %d..." % MCPServer.port)

func _register_conformance_tools() -> void:
    # A. Simple Text
    MCPServer.register_function(
        "test_simple_text",
        "Returns a simple text response.",
        {},
        func(_args: Dictionary) -> Dictionary:
            return {
                "isError": false,
                "content": [{"type": "text", "text": "This is a simple text response for testing."}]
            }
    )
    
    # B. Image Content
    MCPServer.register_function(
        "test_image_content",
        "Returns a 1x1 red PNG image.",
        {},
        func(_args: Dictionary) -> Dictionary:
            return {
                "isError": false,
                "content": [{
                    "type": "image",
                    "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
                    "mimeType": "image/png"
                }]
            }
    )
    
    # C. Audio Content
    MCPServer.register_function(
        "test_audio_content",
        "Returns a minimal WAV audio file.",
        {},
        func(_args: Dictionary) -> Dictionary:
            return {
                "isError": false,
                "content": [{
                    "type": "audio",
                    "data": "UklGRigAAABXQVZFZm10IBIAAAABAAEARKwAAIhYAQACABAAAABkYXRhAgAAAAAA",
                    "mimeType": "audio/wav"
                }]
            }
    )
    
    # D. Embedded Resource
    MCPServer.register_function(
        "test_embedded_resource",
        "Returns an embedded resource.",
        {},
        func(_args: Dictionary) -> Dictionary:
            return {
                "isError": false,
                "content": [{
                    "type": "resource",
                    "resource": {
                        "uri": "test://embedded-resource",
                        "mimeType": "text/plain",
                        "text": "Embedded resource text"
                    }
                }]
            }
    )
    
    # E. Multiple Content Types
    MCPServer.register_function(
        "test_multiple_content_types",
        "Returns multiple content blocks.",
        {},
        func(_args: Dictionary) -> Dictionary:
            return {
                "isError": false,
                "content": [
                    { "type": "text", "text": "Some text content" },
                    {
                        "type": "image",
                        "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
                        "mimeType": "image/png"
                    },
                    {
                        "type": "resource",
                        "resource": {
                            "uri": "test://res",
                            "mimeType": "text/plain",
                            "text": "Resource content"
                        }
                    }
                ]
            }
    )
    
    # F. Tool with Logging
    MCPServer.register_function(
        "test_tool_with_logging",
        "Sends log messages during execution.",
        {},
        func(_args: Dictionary) -> Dictionary:
            for i in range(3):
                MCPServer.send_log_message("debug", "Log message %d from tool execution" % (i + 1), "conformance")
                await get_tree().create_timer(0.05).timeout
            return {
                "isError": false,
                "content": [{"type": "text", "text": "Logging test completed successfully"}]
            }
    )
    
    # G. Error Handling
    MCPServer.register_function(
        "test_error_handling",
        "Fails intentionally with an error.",
        {},
        func(_args: Dictionary) -> Dictionary:
            return {
                "isError": true,
                "content": [{"type": "text", "text": "An intentional test error occurred."}]
            }
    )
    
    # H. Tool with Progress
    MCPServer.register_function(
        "test_tool_with_progress",
        "Sends progress updates during execution.",
        {},
        func(args: Dictionary) -> Dictionary:
            var meta = args.get("_meta", {})
            var token = meta.get("progressToken")
            if token != null:
                for i in range(3):
                    MCPServer.send_progress(token, float(i + 1), 3.0)
                    await get_tree().create_timer(0.05).timeout
            return {
                "isError": false,
                "content": [{"type": "text", "text": "Progress test completed successfully"}]
            }
    )
    
    # I. Sampling
    MCPServer.register_function(
        "test_sampling",
        "Requests sampling from client.",
        {
            "type": "object",
            "properties": {
                "prompt": { "type": "string" }
            },
            "required": ["prompt"]
        },
        func(args: Dictionary) -> Dictionary:
            var meta = args.get("_meta", {})
            var session_id = meta.get("session_id", "")
            var prompt = args.get("prompt", "")
            
            var result = await MCPServer.send_client_request(session_id, "sampling/createMessage", {
                "messages": [
                    {
                        "role": "user",
                        "content": { "type": "text", "text": prompt }
                    }
                ],
                "maxTokens": 100
            })
            
            # The client response structure is: result: { role: "assistant", content: { type: "text", text: "..." }, ... }
            var client_result = result.get("result", {})
            var content = client_result.get("content", {})
            
            return {
                "isError": false,
                "content": [content]
            }
    )
    
    # J. Elicitation (User input)
    MCPServer.register_function(
        "test_elicitation",
        "Requests user input/elicitation.",
        {
            "type": "object",
            "properties": {
                "message": { "type": "string" }
            },
            "required": ["message"]
        },
        func(args: Dictionary) -> Dictionary:
            var meta = args.get("_meta", {})
            var session_id = meta.get("session_id", "")
            var msg = args.get("message", "")
            
            var result = await MCPServer.send_client_request(session_id, "elicitation/create", {
                "message": msg,
                "requestedSchema": {
                    "type": "object",
                    "properties": {
                        "username": { "type": "string" },
                        "email": { "type": "string" }
                    }
                }
            })
            
            # Client returns result: { action: "accept", content: { username: "...", email: "..." } }
            var client_result = result.get("result", {})
            var content = client_result.get("content", {})
            
            return {
                "isError": false,
                "content": [{"type": "text", "text": JSON.stringify(content)}]
            }
    )
    
    # K. Elicitation defaults
    MCPServer.register_function(
        "test_elicitation_sep1034_defaults",
        "Requests elicitation with default values.",
        {},
        func(args: Dictionary) -> Dictionary:
            var meta = args.get("_meta", {})
            var session_id = meta.get("session_id", "")
            
            var result = await MCPServer.send_client_request(session_id, "elicitation/create", {
                "message": "Please confirm elicitation defaults",
                "requestedSchema": {
                    "type": "object",
                    "properties": {
                        "name": { "type": "string", "default": "John Doe" },
                        "age": { "type": "integer", "default": 30 },
                        "score": { "type": "number", "default": 95.5 },
                        "status": { "type": "string", "enum": ["active", "inactive", "pending"], "default": "active" },
                        "verified": { "type": "boolean", "default": true }
                    }
                }
            })
            
            return {
                "isError": false,
                "content": [{"type": "text", "text": "Success"}]
            }
    )
    
    # L. Elicitation enums
    MCPServer.register_function(
        "test_elicitation_sep1330_enums",
        "Requests elicitation with enum schemas.",
        {},
        func(args: Dictionary) -> Dictionary:
            var meta = args.get("_meta", {})
            var session_id = meta.get("session_id", "")
            
            var result = await MCPServer.send_client_request(session_id, "elicitation/create", {
                "message": "Please confirm elicitation enums",
                "requestedSchema": {
                    "type": "object",
                    "properties": {
                        "untitledSingle": { "type": "string", "enum": ["option1", "option2"] },
                        "titledSingle": {
                            "type": "string",
                            "oneOf": [
                                { "const": "value1", "title": "Title 1" },
                                { "const": "value2", "title": "Title 2" }
                            ]
                        },
                        "legacyEnum": {
                            "type": "string",
                            "enum": ["opt1", "opt2"],
                            "enumNames": ["Opt Title 1", "Opt Title 2"]
                        },
                        "untitledMulti": {
                            "type": "array",
                            "items": { "type": "string", "enum": ["option1", "option2"] }
                        },
                        "titledMulti": {
                            "type": "array",
                            "items": {
                                "type": "string",
                                "anyOf": [
                                    { "const": "value1", "title": "Title 1" },
                                    { "const": "value2", "title": "Title 2" }
                                ]
                            }
                        }
                    }
                }
            })
            
            return {
                "isError": false,
                "content": [{"type": "text", "text": "Success"}]
            }
    )
