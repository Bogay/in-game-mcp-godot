# Godot In-Game Model Context Protocol (MCP) Server

A native, high-performance, and event-driven **Model Context Protocol (MCP)** server built inside the Godot 4 engine. This addon exposes the live game state, scene topology, telemetry, and execution hooks to external LLM clients (such as Claude Desktop, Cursor, or custom agents) over a WebSocket connection.

---

## ✨ Features

- **Native WebSocket Transport:** Upgrades incoming TCP streams using native `WebSocketPeer` over a configured port (defaults to `9090`).
- **Dynamic Tool Registry (`notifications/tools/list_changed`):** Fully supports dynamic toolsets. Instantly notifies external clients of tool additions or removals to trigger real-time capability rediscovery.
- **Engine Threading Safety:** Ensures all state mutations and scene modifications occur safely on the main thread via deferred execution or idle frame yielding.
- **Cross-Language Bridging:** Accept C# delegate mappings passed through `Callable.From<T>` and duck-typed node layouts checking for PascalCase (`GetToolName`/`Execute`) and snake_case (`get_tool_name`/`execute`) lifecycle hooks.
- **Context Window Protection:** Built-in tools enforce pagination, depth-clipping, and filtering to prevent blowing past the LLM's prompt context limit.

---

## 📁 File Structure

The workspace includes the automated test script and the plugin code located under `res://addons/mcp_server/`:

```text
res://
├── run_conformance_tests.sh   # Bash script to run official conformance tests headlessly
└── addons/mcp_server/
    ├── plugin.cfg             # Editor plugin descriptor
    ├── mcp_plugin.gd          # Editor plugin registration script
    ├── mcp_server.gd          # Core Autoload managing server loops and connections
    ├── dynamic_mcp_tool.gd    # Wrapper class for dynamic/inline lambdas
    │
    ├── core/
    │   ├── mcp_tool.gd        # Base class interface for static script tools
    │   └── mcp_command_group.gd # Base class for custom tool groups / namespace prefixes
    │
    ├── tools/                 # Pre-packaged observability tools
    │   ├── tool_get_tree.gd   # Depth-clipping scene tree topology scanner
    │   ├── tool_inspect_node.gd # Property inspector with variant-to-JSON serialization
    │   └── tool_get_metrics.gd # Engine metrics and performance reporter
    │
    └── examples/              # Integration references
        ├── sample_registration.gd # GDScript static, dynamic lambda, and command group registration
        ├── CSharpToolExample.cs # C# decoupled tool example using Godot.Collections
        ├── demo_game.tscn     # Playable 2D RPG Demo Game scene
        └── demo_game.gd       # Demo gameplay logic and tool registrations
```

---

## 🎮 Playable 2D RPG Demo Game

The repository contains a fully configured 2D RPG demo project. To run it:
1. Open this repository directory directly in the **Godot Engine Project Manager**.
2. Press **Play** (or load `res://addons/mcp_server/examples/demo_game.tscn`).
3. Use **WASD or Arrow keys** to move the blue Player character. Avoid the red wandering Enemies! Collect yellow Gold Coins.
4. Check the sidebar panel for:
   - Live Player health, mana, and coordinates.
   - Connected MCP clients count (e.g. Cursor, Claude, or local Node bridges).
   - **Live AI Command Logs**: Displays real-time actions and tools invoked by the external LLM client!

### Exposed Demo Tools
When the demo starts, it registers the following custom tools to the MCP server:
* `get_player_status`: Returns current health, mana, coordinates, and inventory list.
* `heal_player(amount: int)`: Restores player health (capped at max health).
* `teleport_player(x: float, y: float)`: Instantly teleports the player anywhere in the play grid.
* `give_item(item_name: string)`: Adds a custom item to the player's inventory list.
* `spawn_enemy(name: string, x: float, y: float)`: Spawns a new enemy character at coordinates.

---

## 🚀 Installation & Setup

1. Copy the `addons/mcp_server` folder into your Godot project's `addons/` directory.
2. Open your project in the Godot Editor.
3. Navigate to **Project Settings** -> **Plugins** and set **In-Game MCP Server** status to **Enabled**.
4. The addon automatically registers `MCPServer` as a global Autoload singleton.

### Server Configuration
By default, the server starts automatically in `WebSocket` mode. You can configure it programmatically or via Godot's Inspector under the Autoload settings:

```gdscript
# Select the transport protocol: "WebSocket" or "SSE"
MCPServer.transport = "SSE" # Default is "WebSocket"

# Port and bind settings (e.g., in a main menu or boot script)
MCPServer.port = 9090
MCPServer.bind_address = "127.0.0.1" # Listen on localhost for security
```

---

## 🤖 Integration with Antigravity (`agy`) / MCP Clients

The addon connects directly to `agy` and other MCP clients over the standard HTTP/SSE transport layer:

1. Configure the `MCPServer` Autoload to use the `SSE` transport (this can be done in the Inspector or via code):
   ```gdscript
   MCPServer.transport = "SSE"
   ```
2. In your global Antigravity client configuration `mcp_config.json` (typically at `~/.gemini/config/mcp_config.json`), define the Godot server URL:
   ```json
   {
     "mcpServers": {
       "godot-mcp-sse": {
         "serverUrl": "http://127.0.0.1:9090/sse"
       }
     }
   }
   ```
3. Run your Godot project. The agent (`agy`) will connect directly to the running game with zero external helper scripts!

---

## 🛠️ Registering Tools

### 1. Static Script Tools
Extend the `MCPTool` class and implement the lifecycle methods. Place the node inside your scene tree, and register it:

```gdscript
# my_tool.gd
extends MCPTool

func get_tool_name() -> String:
    return "player_get_health"

func get_description() -> String:
    return "Returns the health points of the main player character."

func get_input_schema() -> Dictionary:
    return { "type": "object", "properties": {}, "required": [] }

func execute(_args: Dictionary) -> Dictionary:
    var player = get_tree().get_first_node_in_group("player")
    if not player:
        return { "isError": true, "content": [{"type": "text", "text": "Player not found in scene."}] }
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
Register simple 1-to-1 method bindings on-the-fly without creating custom files:

```gdscript
MCPServer.register_function(
    "heal_player",
    "Heals the player character by a specific amount.",
    {
        "type": "object",
        "properties": {
            "amount": { "type": "integer", "description": "HP points to restore", "default": 10 }
        },
        "required": []
    },
    func(args: Dictionary) -> Dictionary:
        var amount = int(args.get("amount", 10))
        # Perform modification safely deferred (Execution Rule)
        call_deferred("_deferred_heal", amount)
        return {
            "isError": false,
            "content": [{"type": "text", "text": "Heal command queued for %d HP." % amount}]
        }
)
```

### 3. Command Groups with Prefixes
Group multiple tools under a common prefix namespace (e.g. `admin/kick_player`, `admin/spawn_boss`):

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
Thanks to duck-typing, C# scripts do not need to inherit from `MCPTool`. You must exclusively use `Godot.Collections.Dictionary` and `Godot.Collections.Array` to maintain interop Variant safety:

```csharp
using Godot;
using Godot.Collections;

public partial class MyCSGameTool : Node
{
    public string GetToolName() => "get_game_version";
    public string GetDescription() => "Gets current build string.";
    public Dictionary GetInputSchema() => new Dictionary { { "type", "object" }, { "properties", new Dictionary() } };

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

---

## 📡 Protocol Specification Support

The server supports standard JSON-RPC 2.0 frames:

| Method / Notification | Type | Purpose |
| :--- | :--- | :--- |
| `initialize` | Request | Setup handshake, exchange capabilities and protocol versions. |
| `notifications/initialized` | Notification | Inform server that connection is established. |
| `tools/list` | Request | Discovers all available tools and parameters schemas. |
| `tools/call` | Request | Executes a tool using arguments and yields back contents. |
| `notifications/tools/list_changed` | Notification | Broadcasted from server when a tool is added/removed. |

---

## 🧪 Conformance & Testing

This project integrates the official Model Context Protocol (MCP) conformance testing suite (`@modelcontextprotocol/conformance`) to ensure strict adherence to the specification.

### Running Conformance Tests
To run compliance tests locally:
1. Ensure your system has the `flatpak` package manager configured with Godot installed (or modify the runner script to target your local executable).
2. Execute the test runner script:
   ```bash
   ./run_conformance_tests.sh
   ```

The script will launch Godot in headless mode, wait for port `9090` to open, run the `@modelcontextprotocol/conformance` suite, and shut down the server process upon completion.

### Tool Schema Normalization
To prevent schema validation failures, the server automatically normalizes tool input schemas:
- Any tool registering with an empty dictionary `{}` or missing the `"type"` field is automatically wrapped with a compliant JSON Schema object: `{ "type": "object", "properties": {}, "required": [] }`.

---

## 🔒 Security & Rules of Play

1. **Local Bind:** By default, the socket binds to `127.0.0.1`. Do not expose this server to the open WAN network unless authentication/firewall proxies are layered over the WebSocket port.
2. **Physics/Raw Thread Safety:** WebSocket parsing runs within Godot's main thread `_process` idle loop. However, any operations altering scene nodes, modifying instance hierarchies, or loading new packages must call `.call_deferred()` or run on `await get_tree().process_frame` to respect frame stability constraints.
