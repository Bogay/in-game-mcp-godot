# Godot In-Game Model Context Protocol (MCP) Server

A native, high-performance, and event-driven **Model Context Protocol (MCP)** server built inside the Godot 4 engine. This addon exposes the live game state, scene topology, telemetry, visual widgets, and execution hooks to external LLM clients (such as Claude Desktop, Cursor, or custom agents) over both WebSocket and SSE transport layers.

---

## ✨ Features

- **Dual Transport Layers:** Supports standard Server-Sent Events (**SSE** over HTTP) and raw **WebSockets** (configurable in Inspector or via `--mcp-transport`).
- **Dynamic Tool Registry (`notifications/tools/list_changed`):** Fully supports runtime changes to capabilities. Instantly alerts external clients of tool additions or removals to trigger real-time rediscovery.
- **MCP Resources System:** Expose live game variables, configuration sheets, or telemetry via [mcp_resource.gd](file:///home/bogay/workspace/in-game-mcp-godot/addons/mcp_server/core/mcp_resource.gd). Automatically triggers `notifications/resources/list_changed` notifications.
- **Interactive MCP Apps (Visual Telemetry):** Expose interactive HTML/CSS/JS panels (with profile `text/html;profile=mcp-app`). Allows bidirectional tool invocations using parent-window `postMessage` communication.
- **Engine Threading Safety:** Guards the frame execution loop. Ensures all state mutations and scene changes occur safely on the main thread via deferred execution (`.call_deferred()`) or idle frame yielding.
- **Cross-Language Bridging:** Accept C# delegate mappings passed through `Callable.From<T>` and duck-typed node layouts checking for PascalCase (`GetToolName`/`Execute`/`GetUri`) and snake_case (`get_tool_name`/`execute`/`get_uri`) lifecycle hooks.
- **Context Window Protection:** Built-in tools enforce pagination, depth-clipping, and filtering to prevent blowing past the LLM's prompt context limit.
- **Conformance Test Suite Support:** Runs headlessly via `./run_conformance_tests.sh` to validate compliance with the official `@modelcontextprotocol/conformance` test suite.

---

## 📁 File Structure

The workspace includes the automated test script and the plugin code located under [addons/mcp_server/](file:///home/bogay/workspace/in-game-mcp-godot/addons/mcp_server/):

```text
res://
├── run_conformance_tests.sh         # Headless script for conformance testing
└── addons/mcp_server/
    ├── plugin.cfg                   # Editor plugin descriptor
    ├── mcp_plugin.gd                # Editor plugin registration script
    ├── mcp_server.gd                # Core Autoload managing server loops and connections
    ├── dynamic_mcp_tool.gd          # Wrapper class for dynamic/inline tool lambdas
    ├── dynamic_mcp_resource.gd      # Wrapper class for dynamic/inline resource lambdas
    │
    ├── core/                        # Protocol & Transport Layer
    │   ├── mcp_base_transport.gd    # Abstract transport base
    │   ├── mcp_websocket_transport.gd # WebSocket transport implementation
    │   ├── mcp_sse_transport.gd     # HTTP Server-Sent Events (SSE) transport implementation
    │   ├── mcp_protocol_handler.gd  # JSON-RPC request and handshake controller
    │   ├── mcp_tool.gd              # Base class interface for static script tools
    │   ├── mcp_tool_registry.gd     # Dynamic and static tool manager
    │   ├── mcp_resource.gd          # Base class interface for static script resources
    │   ├── mcp_resource_registry.gd # Dynamic and static resource manager
    │   └── mcp_command_group.gd     # Base class for custom tool namespaces
    │
    ├── tools/                       # Pre-packaged observability tools
    │   ├── tool_get_tree.gd         # Depth-clipped scene tree scanner
    │   ├── tool_inspect_node.gd     # Property inspector with variant-to-JSON serialization
    │   └── tool_get_metrics.gd      # Engine performance and telemetry reporter
    │
    └── examples/                    # Integration references & Playable demos
        ├── sample_registration.gd   # Standard tool/group/resource registration reference
        ├── CSharpToolExample.cs     # C# decoupled tool example using Godot.Collections
        ├── demo_game.tscn           # Playable 2D RPG Demo Game scene
        ├── demo_game.gd             # 2D RPG gameplay logic & tools
        ├── aoe_demo.tscn            # Playable 2D RTS AoE Demo scene (Multi-agent/Human)
        ├── aoe_demo.gd              # 2D RTS gameplay logic & tools
        ├── mcp_app_demo.tscn        # MCP App demonstration scene
        ├── mcp_app_demo.gd          # Interactive HTML Control Center provider
        ├── conformance_test_runner.tscn # Headless conformance test helper scene
        └── conformance_test_runner.gd # Mock tools/prompts provider for validation
```

---

## 🎮 Playable Demonstration Scenes

This project includes multiple demonstration environments showcasing different paradigms:

### 1. 2D RPG Demo (`demo_game.tscn`)
A classic RPG playground containing a controllable blue Player character, red enemies, and gold coins.
- **Manual controls:** Move with `WASD` or Arrow keys.
- **AI hooks:** Exposes tools to query player state (`get_player_status`), spawn enemies (`spawn_enemy`), teleport (`teleport_player`), give items (`give_item`), and heal (`heal_player`).

### 2. 2D RTS AoE Demo (`aoe_demo.tscn`)
An Age of Empires-style real-time strategy environment illustrating multi-agent and human player coexistence.
- **Manual controls:** Drag-select units to move or mine resources (Wood, Gold, Food). Build Town Centers, Houses, or Barracks.
- **AI hooks:** Exposes RTS tools (`aoe_get_game_state`, `aoe_command_units`, `aoe_spawn_unit`, `aoe_place_building`).

### 3. MCP Visual App Demo (`mcp_app_demo.tscn`)
Exposes an interactive HTML Visual Control Center.
- **Visuals:** Renders a gorgeous Tailwind CSS real-time telemetry panel inside supporting MCP clients (such as Cursor or Claude).
- **Control Bridge:** Clients load the resource `ui://demo/panel` which contains custom buttons. Clicking buttons calls the `postMessage` API to trigger in-game mutations like `app_demo_spawn` or `app_demo_slowmo`.

---

## 🚀 Installation & Setup

1. Copy the `addons/mcp_server` folder into your Godot project's `addons/` directory.
2. Open your project in the Godot Editor.
3. Navigate to **Project Settings** -> **Plugins** and set **In-Game MCP Server** status to **Enabled**.
4. The addon automatically registers `MCPServer` as a global Autoload singleton.

### Configuration Hierarchy

Server settings are evaluated in the following order of precedence (highest to lowest):

1. **Command-Line Arguments:**
   - `--mcp-transport=WebSocket` or `--mcp-transport=SSE`
   - `--mcp-port=9090`
   - `--mcp-bind-address=127.0.0.1`
   - `--mcp-allowed-hosts=localhost,127.0.0.1`
   - `--mcp-auto-start=true`
   - `--mcp-conformance-mode=true`
2. **Environment Variables:**
   - `MCP_TRANSPORT`
   - `MCP_PORT`
   - `MCP_BIND_ADDRESS`
   - `MCP_ALLOWED_HOSTS`
   - `MCP_AUTO_START`
   - `MCP_CONFORMANCE_MODE`
3. **Project Settings:** Options configured via the Godot Project Settings inspector under `mcp_server/*`.
4. **Script Defaults:** Managed internally by [mcp_server.gd](file:///home/bogay/workspace/in-game-mcp-godot/addons/mcp_server/mcp_server.gd).

---

## 🛠️ Tool & Resource Registration

### 1. Static Script Tools
Extend the [MCPTool](file:///home/bogay/workspace/in-game-mcp-godot/addons/mcp_server/core/mcp_tool.gd) class and implement the lifecycle methods:

```gdscript
# my_tool.gd
extends MCPTool

func get_tool_name() -> String:
    return "player_get_health"

func get_description() -> String:
    return "Returns the health points of the main player character."

func get_input_schema() -> Dictionary:
    return {
        "type": "object",
        "properties": {
            "player_id": { "type": "string", "description": "Optional specific player ID" }
        }
    }

func execute(args: Dictionary) -> Dictionary:
    var player = get_tree().get_first_node_in_group("player")
    if not player:
        return { "isError": true, "content": [{"type": "text", "text": "Player not found."}] }
    return {
        "isError": false,
        "content": [{"type": "text", "text": "Player health is: %d" % player.health}]
    }
```
**Registration:**
```gdscript
var health_tool = load("res://my_tool.gd").new()
add_child(health_tool)
MCPServer.register_tool(health_tool)
```

### 2. Dynamic Lambda Functions
Register simple method bindings on-the-fly without creating custom files:

```gdscript
MCPServer.register_function(
    "heal_player",
    "Heals the player character by a specific amount.",
    {
        "type": "object",
        "properties": {
            "amount": { "type": "integer", "description": "HP points to restore", "default": 10 }
        }
    },
    func(args: Dictionary) -> Dictionary:
        var amount = int(args.get("amount", 10))
        # Perform modification safely deferred (Execution Rule)
        call_deferred("_deferred_heal", amount)
        return {
            "isError": false,
            "content": [{"type": "text", "text": "Heal command queued."}]
        }
)
```

### 3. Command Groups with Prefixes
Group multiple tools under a common prefix namespace (e.g. `admin/restart_game`, `admin/spawn_boss`):

```gdscript
var admin_group = MCPCommandGroup.new()
admin_group.prefix = "admin/"
admin_group.description = "Debugging and administration utilities."
add_child(admin_group)

# Add custom MCPTool nodes as children
admin_group.add_child(RestartTool.new())
admin_group.add_child(SpawnTool.new())

# Registers all child tools under the "admin/" namespace
MCPServer.register_command_group(admin_group)
```

### 4. C# Decoupled Modules
Because of the server's duck-typing architecture, C# scripts do not need to inherit from `MCPTool`. You must exclusively use `Godot.Collections.Dictionary` and `Godot.Collections.Array` to maintain interop Variant safety:

```csharp
using Godot;
using Godot.Collections;

namespace MCPServer.Examples;

public partial class MyCSGameTool : Node
{
    public string GetToolName() => "get_game_version";
    public string GetDescription() => "Gets current build string.";
    public Dictionary GetInputSchema() => new Dictionary { { "type", "object" } };

    public Dictionary Execute(Dictionary args)
    {
        return new Dictionary
        {
            { "isError", false },
            { "content", new Array { new Dictionary { { "type", "text" }, { "text", "Build version: 1.0.4-beta" } } } }
        };
    }
}
```
**Registration:**
```csharp
var myTool = new MyCSGameTool();
AddChild(myTool);
GetNode("/root/MCPServer").Call("register_tool", myTool);
```

### 5. Registering Resources
You can expose static resource scripts or register dynamic lambda resources:

```gdscript
# Static Resource
var resource_node = MyStaticResource.new()
add_child(resource_node)
MCPServer.register_resource(resource_node)

# Dynamic Resource (Inline callback)
MCPServer.register_dynamic_resource(
    "godot://game/fps",
    "Engine FPS",
    "text/plain",
    "Provides current real-time frames per second.",
    func() -> String:
        return str(Engine.get_frames_per_second())
)
```

---

## 📡 Protocol Specification Support

The server supports standard JSON-RPC 2.0 frames:

| Method / Notification | Type | Purpose |
| :--- | :--- | :--- |
| `initialize` | Request | Setup handshake, exchange capabilities and protocol versions. |
| `notifications/initialized` | Notification | Inform server that connection is established. |
| `ping` | Request | Keep-alive check. |
| `logging/setLevel` | Request | Sets logger severity filters. |
| `completion/complete` | Request | Requests input autocompletion. |
| `tools/list` | Request | Discovers all available tools and parameters schemas. |
| `tools/call` | Request | Executes a tool using arguments and yields back contents. |
| `notifications/tools/list_changed` | Notification | Broadcasted from server when a tool is added/removed. |
| `resources/list` | Request | Lists all registered observational resources. |
| `resources/read` | Request | Retrieves the contents of a specific resource. |
| `resources/subscribe` | Request | Establishes a subscription to a resource. |
| `resources/unsubscribe` | Request | Removes a subscription to a resource. |
| `notifications/resources/list_changed` | Notification | Broadcasted from server when a resource is added/removed. |
| `prompts/list` | Request | Lists mock validation prompts (in conformance mode). |
| `prompts/get` | Request | Fetches a specific mock prompt (in conformance mode). |
| `notifications/message` | Notification | Server-bound logging streams to clients. |
| `notifications/progress` | Notification | Server-bound process execution updates. |

---

## 🧪 Conformance & Testing

Ensure that all tools adhere strictly to the JSON Schema specification using the built-in conformance runner:

```bash
./run_conformance_tests.sh
```

The script will launch Godot in headless mode, trigger `conformance_mode` to load mockup entities, and execute the official `@modelcontextprotocol/conformance` test suite.

---

## 🔒 Security & Rules of Play

1. **Local Bind:** By default, the socket binds to `127.0.0.1`. Do not expose this server to the open WAN network unless authentication/firewall proxies are layered over the communication port.
2. **Physics/Raw Thread Safety:** Any operations altering scene nodes, modifying instance hierarchies, or loading new packages must call `.call_deferred()` or run on `await get_tree().process_frame` to respect frame stability constraints.
