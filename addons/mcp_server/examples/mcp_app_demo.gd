extends Node

@export var bootstrap_server: bool = true
@export var register_demo_tools: bool = true

func _ready() -> void:
    print("[MCP App Demo] Starting MCP Apps Demonstration environment...")
    
    if bootstrap_server:
        # Bind to 0.0.0.0 to allow connection from the host machine via the VM IP
        MCPServer.bind_address = "0.0.0.0"
        MCPServer.allowed_hosts = ["*"] # Expose and allow all host headers for demo access
        MCPServer.stop_server()
        MCPServer.start_server()
    
    # 1. Register the MCP UI resource
    MCPServer.register_dynamic_resource(
        "ui://demo/panel",
        "Godot Control Center",
        "text/html;profile=mcp-app",
        "Interactive control panel for game telemetry and manipulation.",
        _get_ui_html
    )
    
    # 2. Register tools with UI linking metadata
    var ui_meta = {
        "ui": {
            "resourceUri": "ui://demo/panel"
        }
    }
    
    if register_demo_tools:
        MCPServer.register_function(
            "app_demo_spawn",
            "Spawns a mock creature in the active scene.",
            {
                "type": "object",
                "properties": {
                    "enemy_type": { "type": "string", "enum": ["goblin", "orc", "dragon"], "default": "goblin" }
                }
            },
            _on_spawn,
            ui_meta
        )
        
        MCPServer.register_function(
            "app_demo_heal",
            "Restores health to the player character.",
            {},
            _on_heal,
            ui_meta
        )
        
        MCPServer.register_function(
            "app_demo_slowmo",
            "Toggles engine time scale (slow motion).",
            {
                "type": "object",
                "properties": {
                    "scale": { "type": "number", "default": 0.5 }
                }
            },
            _on_slowmo,
            ui_meta
        )
    
    print("[MCP App Demo] Demonstration ready! To test:")
    print("1. Start this scene in Godot.")
    print("2. Connect an MCP Client that supports MCP Apps.")
    print("3. Query tool 'app_demo_spawn' or read resource 'ui://demo/panel'.")

func _get_ui_html() -> String:
    var fps = Engine.get_frames_per_second()
    var mem = float(OS.get_static_memory_usage()) / 1024.0 / 1024.0 # MB
    var platform = OS.get_name()
    
    var html = """<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Godot Game Control Center</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        @keyframes pulse-slow {
            0%%, 100%% { opacity: 0.2; }
            50%% { opacity: 0.6; }
        }
        .glow { animation: pulse-slow 3s infinite; }
    </style>
</head>
<body class="bg-slate-950 text-slate-100 font-sans p-6 min-h-screen flex flex-col justify-between">
    <!-- Header -->
    <div class="border-b border-slate-800 pb-4 mb-6">
        <div class="flex justify-between items-center">
            <div>
                <h1 class="text-2xl font-bold bg-gradient-to-r from-blue-400 via-indigo-400 to-purple-400 bg-clip-text text-transparent">Godot Control Center</h1>
                <p class="text-xs text-slate-400 mt-1">MCP App Visual Telemetry & Controls</p>
            </div>
            <span class="flex h-3 w-3 relative">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                <span class="relative inline-flex rounded-full h-3 w-3 bg-emerald-500"></span>
            </span>
        </div>
    </div>

    <!-- Metrics Grid -->
    <div class="grid grid-cols-3 gap-4 mb-6">
        <div class="bg-slate-900 border border-slate-800 p-4 rounded-xl relative overflow-hidden">
            <div class="text-slate-400 text-xs font-semibold">Engine FPS</div>
            <div class="text-3xl font-mono font-bold mt-1 text-sky-400">%d</div>
            <div class="absolute bottom-0 right-0 w-12 h-12 bg-sky-500/10 rounded-full blur-lg glow"></div>
        </div>
        <div class="bg-slate-900 border border-slate-800 p-4 rounded-xl relative overflow-hidden">
            <div class="text-slate-400 text-xs font-semibold">Memory Usage</div>
            <div class="text-3xl font-mono font-bold mt-1 text-violet-400">%.2f MB</div>
            <div class="absolute bottom-0 right-0 w-12 h-12 bg-violet-500/10 rounded-full blur-lg glow"></div>
        </div>
        <div class="bg-slate-900 border border-slate-800 p-4 rounded-xl relative overflow-hidden">
            <div class="text-slate-400 text-xs font-semibold">OS Platform</div>
            <div class="text-xl font-bold mt-2 text-amber-400 truncate">%s</div>
            <div class="absolute bottom-0 right-0 w-12 h-12 bg-amber-500/10 rounded-full blur-lg glow"></div>
        </div>
    </div>

    <!-- Commands Panel -->
    <div class="bg-slate-900 border border-slate-800 p-5 rounded-xl mb-6">
        <h2 class="text-sm font-semibold text-slate-400 mb-4 uppercase tracking-wider">Execute Game Mutation Commands</h2>
        <div class="grid grid-cols-3 gap-3">
            <button onclick="callTool('app_demo_spawn', {enemy_type: 'orc'})" 
                    class="bg-gradient-to-br from-red-600 to-rose-700 hover:from-red-500 hover:to-rose-600 text-white font-medium py-2.5 px-4 rounded-lg shadow-lg hover:shadow-red-500/20 active:scale-95 transition-all text-sm">
                Spawn Orc
            </button>
            <button onclick="callTool('app_demo_heal', {})" 
                    class="bg-gradient-to-br from-emerald-600 to-teal-700 hover:from-emerald-500 hover:to-teal-600 text-white font-medium py-2.5 px-4 rounded-lg shadow-lg hover:shadow-emerald-500/20 active:scale-95 transition-all text-sm">
                Heal Player
            </button>
            <button onclick="callTool('app_demo_slowmo', {scale: 0.2})" 
                    class="bg-gradient-to-br from-indigo-600 to-violet-700 hover:from-indigo-500 hover:to-violet-600 text-white font-medium py-2.5 px-4 rounded-lg shadow-lg hover:shadow-indigo-500/20 active:scale-95 transition-all text-sm">
                Slow-Mo (20%%)
            </button>
        </div>
    </div>

    <!-- Operation Console -->
    <div class="bg-slate-950 border border-slate-800 p-4 rounded-lg flex-1 min-h-[100px] mb-6 flex flex-col font-mono text-xs">
        <div class="text-slate-500 border-b border-slate-900 pb-1 mb-2 flex justify-between">
            <span>CONSOLE LOG</span>
            <button onclick="clearConsole()" class="hover:text-slate-300">CLEAR</button>
        </div>
        <div id="console" class="flex-1 overflow-y-auto max-h-[120px] text-emerald-400 space-y-1">
            <div>[System] Diagnostics interface initialized.</div>
        </div>
    </div>

    <!-- Footer -->
    <div class="text-center text-[10px] text-slate-500">
        Connected to Godot MCP Server via WebSocket/SSE
    </div>

    <script>
        function log(message, type = 'info') {
            const con = document.getElementById('console');
            const el = document.createElement('div');
            const time = new Date().toLocaleTimeString();
            el.innerText = `[${time}] ${message}`;
            if (type === 'error') el.className = 'text-red-400';
            else if (type === 'success') el.className = 'text-green-400';
            con.appendChild(el);
            con.scrollTop = con.scrollHeight;
        }

        function clearConsole() {
            document.getElementById('console').innerHTML = '<div>[Console cleared]</div>';
        }

        // Send a postMessage JSON-RPC tool/call to the host client (e.g. Cursor, Claude)
        function callTool(name, args) {
            log(`Invoking tool '${name}' with ${JSON.stringify(args)}...`);
            
            const message = {
                jsonrpc: "2.0",
                method: "tools/call",
                params: {
                    name: name,
                    arguments: args
                }
            };
            
            // Post message back to the host window
            window.parent.postMessage(message, "*");
        }

        // Listen for tool responses or data streams returned from host
        window.addEventListener('message', (event) => {
            const data = event.data;
            if (data && data.jsonrpc === "2.0") {
                if (data.result) {
                    log(`Response: ${JSON.stringify(data.result)}`, 'success');
                } else if (data.error) {
                    log(`Error: ${data.error.message}`, 'error');
                }
            }
        });
    </script>
</body>
</html>
""" % [fps, mem, platform]
    return html

func _on_spawn(args: Dictionary) -> Dictionary:
    var type = args.get("enemy_type", "goblin")
    print("[MCP App Demo] Spawning enemy of type: ", type)
    return {
        "isError": false,
        "content": [{"type": "text", "text": "Successfully spawned a %s!" % type}]
    }

func _on_heal(_args: Dictionary) -> Dictionary:
    print("[MCP App Demo] Player healed back to full health.")
    return {
        "isError": false,
        "content": [{"type": "text", "text": "Player health restored."}]
    }

func _on_slowmo(args: Dictionary) -> Dictionary:
    var scale = float(args.get("scale", 0.5))
    print("[MCP App Demo] Toggled slow motion. Setting time scale to: ", scale)
    Engine.time_scale = scale
    return {
        "isError": false,
        "content": [{"type": "text", "text": "Game time scale set to %.1f." % scale}]
    }
