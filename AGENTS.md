# AGENTS.md - In-Game Model Context Protocol (MCP) Server

This document defines the architecture, technical stack, file structural guidelines, and rigid coding conventions for the in-game MCP Server implementation in Godot 4. All AI agents altering or expanding this codebase must strictly adhere to these patterns.

---

## 1. Project Overview & Goals

The objective of this project is to build a high-performance, low-latency, and event-driven **Model Context Protocol (MCP)** server natively inside the Godot 4 engine. This server exposes the live game state, scene topology, telemetry, visual widgets, and execution hooks to external LLM clients (such as Claude or Cursor) via local SSE (Server-Sent Events) or WebSocket bridges.

### Core Goals:
* **Observability:** Allow external AI agents to discover, query, and map the runtime engine state safely without blowing past LLM context boundaries.
* **Controlled Mutation:** Provide real-time state mutation and method invocation that honors the engine's frame-lifecycle and threading rules.
* **Modularity:** Maintain a lightweight, decoupled system where developers can add or remove AI tools and resources with minimal boilerplate.
* **Cross-Language Support:** Allow seamless tool and resource definitions from both GDScript and C# codebases.
* **Visual Telemetry (MCP Apps):** Support iframe-embedded HTML pages inside client applications for rich interactive visual widgets.

---

## 2. Target Technical Stack

* **Game Engine:** Godot 4.x (Standard or .NET/Mono Edition)
* **Languages:** GDScript 2.0 & C#
* **Network Transport Layer:** Dynamic selection between standard Server-Sent Events (SSE via `TCPServer`/HTTP) and raw WebSockets (`WebSocketPeer`).
* **Wire Protocol:** JSON-RPC 2.0 compliant payload handling via UTF-8 string/buffer conversions.

---

## 3. System Architecture & Component Design

The server utilizes a decoupled architecture routing requests to specialized registries managed by the main Autoload singleton.

```
[External AI Client] <--- Standard I/O / Network ---> [Transport Layer (SSE / WS)]
                                                             |
                                                             v
                                                 +-----------------------+
                                                 |  MCPServer (Autoload) |
                                                 +-----------------------+
                                                             |
                                            +----------------+----------------+
                                            v                                 v
                                 +-----------------------+         +-----------------------+
                                 |     Tool Registry     |         |   Resource Registry   |
                                 +-----------------------+         +-----------------------+
                                            |                                 |
                          +-----------------+-----------------+             +-+---------+
                          v                 v                 v             v           v
                   +------------+    +------------+    +------------+  +---------+  +---------+
                   | Static Node|    |   Dynamic  |    |  C# Decoup.|  | Static  |  | Dynamic |
                   | Tools (GD) |    | Lambdas/Fn |    | Tools (.NET)|  | Resource|  | Lambda  |
                   +------------+    +------------+    +------------+  +---------+  +---------+
```

### Key Capabilities Required:
1. **Dynamic Toolsets and Resources (`list_changed`):** The server must support runtime changes to its capabilities. When context shifts, tools or resources are added/removed, and a JSON-RPC notification (`notifications/tools/list_changed` or `notifications/resources/list_changed`) without an `id` field must immediately alert the client to trigger re-discovery.
2. **First-Class Functions (`Callable` Wrapper):** Thin wrapper classes (`DynamicMCPTool` and `DynamicMCPResource`) handle registering capabilities on-the-fly using GDScript Lambdas to avoid writing explicit files for simple bindings.
3. **Cross-Language Bridging:** The server must accept C# delegate mappings passed through `Callable.From<T>` or read decoupled node schemas via duck-typing logic checking for standard lifecycle hooks in both PascalCase and snake_case.
4. **Interactive App Integration:** Allow attaching metadata UI links to tools and registering HTML pages with MIME type `text/html;profile=mcp-app` to display visual controls inside the LLM client.

---

## 4. Specific Coding Standards & Constraints

### A. Engine Threading Safety (The Execution Rule)
* **Constraint:** AI network polling occurs asynchronously or in a non-blocking loop. Any operations altering node states, instantiating objects, editing tree layouts, or switching scenes **MUST NOT** execute during a background thread slice.
* **Standard:** Wrap all active mutators, logic hooks, or scene changes inside a `.call_deferred()` invocation or yield to the next idle frame using `await get_tree().process_frame` to respect frame stability constraints.

### B. Serialization and Strict Data Typing
* **Constraint:** GDScript engine-specialized data types (`Vector2`, `Vector3`, `Transform2D`, `Color`) cannot be serialized directly by standard JSON engines.
* **Standard:**
  * Every tool's input schema must conform to explicit, structured JSON parameters.
  * When writing tools in **C#**, you **MUST NOT** use generic C# types (`System.Collections.Generic.Dictionary`). You must exclusively use `Godot.Collections.Dictionary` and `Godot.Collections.Array` to maintain native Variant compliance over the interop layer.

### C. Guarding the Context Window
* **Constraint:** Exposing the entire game configuration tree layout will immediately cause an LLM context overflow or network stutter.
* **Standard:** Any tool querying topology must enforce pagination, depth-clipping, or regional spatial/group filters (e.g., limiting object collection inspection to specific ranges or node types).

### D. Strict Conformance Testing & Schema Validity
* **Constraint:** The official `@modelcontextprotocol/conformance` test suite strictly validates that all registered tools advertise a valid JSON Schema object. Tool schemas cannot be empty dictionaries (`{}`) and must specify at least `"type": "object"`.
* **Standard:**
  * When declaring custom tools, ensure `get_input_schema()` returns a dictionary with `"type": "object"`.
  * The server provides safety fallback normalization on registry paths to guarantee conformance for empty or partial user-provided schemas.
  * Run the conformance suite locally with `./run_conformance_tests.sh` to ensure any changes are fully compliant before submitting.

---

## 5. Directory & File Structure

Implementations must be organized precisely under the following structure inside the Godot `res://` directory:

```text
res://
├── run_conformance_tests.sh         # Headless conformance test runner bash script
└── addons/
    └── mcp_server/
        ├── plugin.cfg               # Editor plugin descriptor
        ├── mcp_plugin.gd            # Editor plugin registration script
        ├── mcp_server.gd            # Core Autoload managing server loops and connections
        ├── dynamic_mcp_tool.gd      # Dynamic tool wrapper for inline Lambdas
        ├── dynamic_mcp_resource.gd  # Dynamic resource wrapper for inline Lambdas
        │
        ├── core/                    # Core protocol base classes
        │   ├── mcp_base_transport.gd      # Abstract base class for server transport
        │   ├── mcp_websocket_transport.gd # WebSocket server transport
        │   ├── mcp_sse_transport.gd       # SSE / HTTP server transport
        │   ├── mcp_protocol_handler.gd    # Handshake, request parser, and session mapper
        │   ├── mcp_tool.gd                # Base class interface for static script tools
        │   ├── mcp_tool_registry.gd       # Handles static/dynamic tool registry
        │   ├── mcp_resource.gd            # Base class interface for static script resources
        │   ├── mcp_resource_registry.gd   # Handles static/dynamic resource registry
        │   └── mcp_command_group.gd       # Base descriptor class for custom groups
        │
        ├── tools/                   # Pre-packaged observability tools
        │   ├── tool_get_tree.gd     # Highly scoped scene structural investigator
        │   ├── tool_inspect_node.gd # Safe runtime node variant property scanner
        │   └── tool_get_metrics.gd  # Client status performance/telemetry reporter
        │
        └── examples/                # Demo configurations & scenes
            ├── sample_registration.gd     # Exemplary usage of the GDScript runtime API
            ├── CSharpToolExample.cs       # Reference layout for a decoupled C# module
            ├── demo_game.tscn             # Playable 2D RPG Demo Game scene
            ├── demo_game.gd               # 2D RPG gameplay logic & tools
            ├── aoe_demo.tscn              # Playable 2D RTS AoE Demo scene
            ├── aoe_demo.gd                # 2D RTS gameplay logic & tools
            ├── mcp_app_demo.tscn          # Visual MCP visual widget demonstration scene
            ├── mcp_app_demo.gd            # Interactive visual app backend
            ├── conformance_test_runner.tscn # Conformance testing scene
            └── conformance_test_runner.gd # Conformance mock implementations
```

---

## 6. Standard Code Templates

### Base Tool Struct ([mcp_tool.gd](file:///home/bogay/workspace/in-game-mcp-godot/addons/mcp_server/core/mcp_tool.gd))

```gdscript
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

func to_manifest() -> Dictionary:
    return {
        "name": get_tool_name(),
        "description": get_description(),
        "inputSchema": get_input_schema()
    }
```

### Base Resource Struct ([mcp_resource.gd](file:///home/bogay/workspace/in-game-mcp-godot/addons/mcp_server/core/mcp_resource.gd))

```gdscript
extends Node
class_name MCPResource

func get_uri() -> String:
    return "proto://unnamed"

func get_name() -> String:
    return "Unnamed Resource"

func get_description() -> String:
    return ""

func get_mime_type() -> String:
    return "text/plain"

func read() -> Dictionary:
    return { "text": "" }

func to_manifest() -> Dictionary:
    var manifest = {
        "uri": get_uri(),
        "name": get_name(),
        "mimeType": get_mime_type()
    }
    var desc = get_description()
    if desc != "":
        manifest["description"] = desc
    return manifest
```

### Thin Wrapper Registry Signatures ([mcp_server.gd](file:///home/bogay/workspace/in-game-mcp-godot/addons/mcp_server/mcp_server.gd))

```gdscript
# Tool Registration
func register_function(tool_name: String, desc: String, schema: Dictionary, target: Callable, metadata: Dictionary = {}) -> void:
    tool_registry.register_function(tool_name, desc, schema, target, metadata)

# Resource Registration
func register_dynamic_resource(uri: String, name: String, mime_type: String, desc: String, read_callback: Callable) -> void:
    resource_registry.register_dynamic_resource(uri, name, mime_type, desc, read_callback)
```
