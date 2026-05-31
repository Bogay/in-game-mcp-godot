# AGENTS.md - In-Game Model Context Protocol (MCP) Server

This document defines the architecture, technical stack, file structural guidelines, and rigid coding conventions for the in-game MCP Server implementation in Godot 4. All AI agents altering or expanding this codebase must strictly adhere to these patterns.

---

## 1. Project Overview & Goals

The objective of this project is to build a high-performance, low-latency, and event-driven **Model Context Protocol (MCP)** server natively inside the Godot 4 engine. This server exposes the live game state, scene topology, telemetry, and execution hooks to external LLM clients (such as Claude or Cursor) via a local WebSocket bridge.

### Core Goals:
* **Observability:** Allow external AI agents to discover, query, and map the runtime engine state safely without blowing past LLM context boundaries.
* **Controlled Mutation:** Provide real-time state mutation and method invocation that honors the engine's frame-lifecycle and threading rules.
* **Modularity:** Maintain a lightweight, decoupled system where developers can add or remove AI tools with minimal boilerplate.
* **Cross-Language Support:** Allow seamless tool definition from both GDScript and C# codebases.

---

## 2. Target Technical Stack

* **Game Engine:** Godot 4.x (Standard or .NET/Mono Edition)
* **Languages:** GDScript 2.0 & C#
* **Network Transport Layer:** Natively managed `TCPServer` upgrading raw streams to `WebSocketPeer`.
* **Wire Protocol:** JSON-RPC 2.0 compliant payload handling via UTF-8 string/buffer conversions.

---

## 3. System Architecture & Component Design

The server transitions away from monolithic routing systems in favor of a highly modular **Command Pattern** hybrid layout.


```

[External AI Client] <--- Standard I/O ---> [Node.js / Python Bridge]
|
WebSocket (Port: 9090)
|
v
+---------------------------+
|    MCPServer (Autoload)   |
+---------------------------+
|
+----------------------+----------------------+
|                      |                      |
v                      v                      v
+-----------------+    +-----------------+    +-----------------+
|   Static Class  |    |  Dynamic Tools  |    |     C# Tools    |
|     Tool Nodes  |    |  (Lambdas/Funcs)|    |  (Callable.From)|
+-----------------+    +-----------------+    +-----------------+

```

### Key Capabilities Required:
1. **Dynamic Toolsets (`notifications/tools/list_changed`):** The server must support runtime changes to its capabilities. When context shifts (e.g., player switches game states), tools are added/removed, and a JSON-RPC notification (`notifications/tools/list_changed`) without an `id` field must immediately alert the client to trigger re-discovery.
2. **First-Class Functions (`Callable` Wrapper):** A thin wrapper class (`DynamicMCPTool`) handles registering tools on-the-fly using Lambdas to avoid writing explicit files for simple 1-to-1 method bindings.
3. **Cross-Language Bridging:** The server must accept C# delegate mappings passed through `Callable.From<T>` or read decoupled node schemas via duck-typing logic checking for standard lifecycle hooks (`get_tool_name`, `execute`).

---

## 4. Specific Coding Standards & Constraints

### A. Engine Threading Safety (The Execution Rule)
* **Constraint:** AI network polling occurs asynchronously via the network socket loop. Any operations altering node states, instances, tree layouts, or switching scenes **MUST NOT** execute during a background slice or raw frame step.
* **Standard:** Wrap all active mutators, logic hooks, or scene changes inside a `.call_deferred()` invocation or batch them for the next immediate idle frame.

### B. Serialization and Strict Data Typing
* **Constraint:** GDScript engine specialized data types (`Vector2`, `Vector3`, `Transform2D`, `Color`) cannot be parsed by default JSON engines.
* **Standard:** * Every tool's input schema must conform to explicit, structured JSON parameters.
    * When writing tools in **C#**, you **MUST NOT** use generic C# types (`System.Collections.Generic.Dictionary`). You must exclusively use `Godot.Collections.Dictionary` and `Godot.Collections.Array` to maintain native Variant compliance over the interop layer.

### C. Guarding the Context Window
* **Constraint:** Exposing the entire game configuration tree layout will immediately cause an LLM context overflow or network stutter.
* **Standard:** Any tool querying topology must enforce pagination, depth-clipping, or regional spatial/group filters (e.g., limiting object collection inspection to specific ranges or node types).

---

## 5. Directory & File Structure

Implementations must be organized precisely under the following structure inside the Godot `res://` directory:

```text
res://
└── addons/
    └── mcp_server/
        |-- plugin.cfg                 # Editor plugin descriptor
        |-- mcp_server.gd              # Core Autoload managing TCP/WebSocket loops
        |-- dynamic_mcp_tool.gd        # Dynamic tool wrapper for inline Lambdas
        |
        +-- core/                      # Core base classes
        |   |-- mcp_tool.gd            # Base class interface for static script tools
        |   +-- mcp_command_group.gd   # Base descriptor class for custom groups
        |
        +-- tools/                     # Pre-packaged observability tools
        |   |-- tool_get_tree.gd       # Highly scoped scene structural investigator
        |   |-- tool_inspect_node.gd   # Safe runtime node variant property scanner
        |   └── tool_get_metrics.gd    # Client status performance/telemetry reporter
        |
        └── examples/                  # Demo configurations
            |-- sample_registration.gd # Exemplary usage of the lambda runtime API
            └── CSharpToolExample.cs   # Reference layout for a decoupled C# module

```

---

## 6. Standard Code Templates

### Base Tool Struct (`mcp_tool.gd`)

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

### Thin Wrapper Registry Signature (`mcp_server.gd`)

```gdscript
func register_function(tool_name: String, desc: String, schema: Dictionary, target: Callable) -> void:
    var dynamic_tool = DynamicMCPTool.new(tool_name, desc, schema, target)
    available_tools[tool_name] = dynamic_tool
    cached_manifests.append(dynamic_tool.to_manifest())
    tools_changed.emit() # Fires notifications/tools/list_changed

```
