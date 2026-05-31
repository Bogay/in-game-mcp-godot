extends Node2D

# In-Game RPG Demo showcasing the Model Context Protocol (MCP) Addon capabilities.
# Creates a player, wandering enemies, collectible gold, and an interactive HUD.
# Exposes player stats, healing, teleportation, spawning, and inventory mutations.

# --- Game State ---
var player_health: int = 80
var player_max_health: int = 100
var player_mana: int = 40
var player_inventory: Array[String] = ["Wooden Sword", "Healing Potion"]
var player_speed: float = 250.0

var screen_width: float = 1152.0
var screen_height: float = 648.0
var play_area_width: float = 800.0

# --- Nodes ---
var player_node: Node2D
var enemy_container: Node2D
var item_container: Node2D

# --- UI Controls ---
var hp_bar: ProgressBar
var hp_label: Label
var mana_label: Label
var pos_label: Label
var inv_label: Label
var conn_label: Label
var log_text: RichTextLabel

func _ready() -> void:
    # 1. Setup play field background
    var bg = ColorRect.new()
    bg.color = Color(0.12, 0.14, 0.18)
    bg.size = Vector2(play_area_width, screen_height)
    add_child(bg)
    
    # 2. Setup sidebar background panel
    var sidebar_bg = ColorRect.new()
    sidebar_bg.color = Color(0.08, 0.09, 0.12)
    sidebar_bg.position = Vector2(play_area_width, 0)
    sidebar_bg.size = Vector2(screen_width - play_area_width, screen_height)
    add_child(sidebar_bg)
    
    # 3. Setup container nodes
    enemy_container = Node2D.new()
    enemy_container.name = "Enemies"
    add_child(enemy_container)
    
    item_container = Node2D.new()
    item_container.name = "Items"
    add_child(item_container)
    
    # 4. Spawning Player
    player_node = Node2D.new()
    player_node.name = "Player"
    player_node.position = Vector2(400, 300)
    add_child(player_node)
    
    # Player visual rect (Blue)
    var player_visual = ColorRect.new()
    player_visual.color = Color(0.2, 0.5, 0.9)
    player_visual.size = Vector2(32, 32)
    player_visual.position = Vector2(-16, -16) # Centered
    player_node.add_child(player_visual)
    
    # 5. Populate initial items & enemies
    for i in range(5):
        _spawn_item_internal(Vector2(randf_range(50, play_area_width - 50), randf_range(50, screen_height - 50)))
        
    for i in range(3):
        _spawn_enemy_internal("Goblin_" + str(i + 1), Vector2(randf_range(100, play_area_width - 100), randf_range(100, screen_height - 100)))

    # 6. Setup GUI Sidebar Layout
    _setup_ui()
    
    # 7. Connect to MCPServer events
    MCPServer.tool_called.connect(_on_mcp_tool_called)
    
    # 8. Register Custom Demo Tools
    _register_demo_mcp_tools()
    
    _log_message("System: Game initialized and MCP Server active.")

func _process(delta: float) -> void:
    # A. Handle player movement input (WASD / Arrows)
    var move_dir = Vector2.ZERO
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move_dir.y -= 1
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move_dir.y += 1
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move_dir.x -= 1
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move_dir.x += 1
    
    if move_dir != Vector2.ZERO:
        player_node.position += move_dir.normalized() * player_speed * delta
        player_node.position.x = clamp(player_node.position.x, 16, play_area_width - 16)
        player_node.position.y = clamp(player_node.position.y, 16, screen_height - 16)

    # B. Wandering Enemies & Collision Check with Player
    for enemy in enemy_container.get_children():
        # Wander logic
        if randf() < 0.02:
            enemy.set_meta("target_dir", Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized())
            
        var dir = enemy.get_meta("target_dir", Vector2.ZERO)
        enemy.position += dir * 100.0 * delta
        enemy.position.x = clamp(enemy.position.x, 16, play_area_width - 16)
        enemy.position.y = clamp(enemy.position.y, 16, screen_height - 16)
        
        # Check collision with Player (approximate AABB overlap)
        if player_node.position.distance_to(enemy.position) < 30.0:
            # Damage player over time
            player_health = max(0, player_health - int(15.0 * delta))
            
    # C. Item Pickup Check
    for item in item_container.get_children():
        if player_node.position.distance_to(item.position) < 24.0:
            var item_name = item.get_meta("item_name", "Gold Coin")
            player_inventory.append(item_name)
            _log_message("Player: Picked up '%s'" % item_name)
            item.queue_free()

    # D. Update UI values
    _update_ui_displays()

# --- UI Setup Helper ---
func _setup_ui() -> void:
    var font_size = 14
    var layout = VBoxContainer.new()
    layout.position = Vector2(play_area_width + 15, 15)
    layout.size = Vector2(screen_width - play_area_width - 30, screen_height - 30)
    add_child(layout)
    
    # Title
    var title = Label.new()
    title.text = "GODOT MCP SERVER DEMO"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
    layout.add_child(title)
    
    layout.add_child(HSeparator.new())
    
    # Stats Title
    var stats_hdr = Label.new()
    stats_hdr.text = "Player Statistics"
    layout.add_child(stats_hdr)
    
    # HP Bar
    var hp_row = HBoxContainer.new()
    var hp_lbl = Label.new()
    hp_lbl.text = "HP:  "
    hp_lbl.custom_minimum_size = Vector2(40, 0)
    hp_row.add_child(hp_lbl)
    
    hp_bar = ProgressBar.new()
    hp_bar.max_value = player_max_health
    hp_bar.value = player_health
    hp_bar.custom_minimum_size = Vector2(180, 20)
    hp_bar.show_percentage = false
    hp_row.add_child(hp_bar)
    
    hp_label = Label.new()
    hp_label.text = "80/100"
    hp_row.add_child(hp_label)
    layout.add_child(hp_row)
    
    # Mana
    var mana_row = HBoxContainer.new()
    var mana_title = Label.new()
    mana_title.text = "MP: "
    mana_title.custom_minimum_size = Vector2(40, 0)
    mana_row.add_child(mana_title)
    
    mana_label = Label.new()
    mana_label.text = "40"
    mana_row.add_child(mana_label)
    layout.add_child(mana_row)
    
    # Position
    var pos_row = HBoxContainer.new()
    var pos_title = Label.new()
    pos_title.text = "Pos: "
    pos_title.custom_minimum_size = Vector2(40, 0)
    pos_row.add_child(pos_title)
    
    pos_label = Label.new()
    pos_label.text = "(400, 300)"
    pos_row.add_child(pos_label)
    layout.add_child(pos_row)
    
    # Inventory
    var inv_title = Label.new()
    inv_title.text = "Inventory:"
    layout.add_child(inv_title)
    
    inv_label = Label.new()
    inv_label.autowrap_mode = TextServer.AUTOWRAP_WORD
    inv_label.text = "Wooden Sword, Healing Potion"
    inv_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
    layout.add_child(inv_label)
    
    layout.add_child(HSeparator.new())
    
    # Server Connection Status
    conn_label = Label.new()
    conn_label.text = "MCP Clients: 0 connected"
    conn_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.1))
    layout.add_child(conn_label)
    
    layout.add_child(HSeparator.new())
    
    # Logs Panel
    var log_title = Label.new()
    log_title.text = "AI Command Logs:"
    layout.add_child(log_title)
    
    log_text = RichTextLabel.new()
    log_text.custom_minimum_size = Vector2(0, 240)
    log_text.scroll_active = true
    log_text.scroll_following = true
    log_text.autowrap_mode = TextServer.AUTOWRAP_WORD
    log_text.add_theme_color_override("default_color", Color(0.7, 0.9, 0.7))
    layout.add_child(log_text)

func _update_ui_displays() -> void:
    hp_bar.value = player_health
    hp_label.text = "%d/%d" % [player_health, player_max_health]
    mana_label.text = str(player_mana)
    pos_label.text = "(%d, %d)" % [int(player_node.position.x), int(player_node.position.y)]
    inv_label.text = ", ".join(player_inventory)
    
    # Connection count
    var count = MCPServer.connected_peers.size()
    conn_label.text = "MCP Clients: %d connected" % count
    if count > 0:
        conn_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))
    else:
        conn_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.1))

func _log_message(msg: String) -> void:
    var time = Time.get_time_string_from_system()
    log_text.append_text("[%s] %s\n" % [time, msg])

# --- Log events from MCP Client calls ---
func _on_mcp_tool_called(tool_name: String, arguments: Dictionary, response: Dictionary) -> void:
    var arg_str = JSON.stringify(arguments)
    var status = "Success" if not response.get("isError", false) else "Error"
    _log_message("AI: call '%s' with %s -> %s" % [tool_name, arg_str, status])

# --- Internal Spawning ---
func _spawn_item_internal(pos: Vector2, item_name: String = "Gold Coin") -> void:
    var item = Node2D.new()
    item.position = pos
    item.set_meta("item_name", item_name)
    item_container.add_child(item)
    
    var vis = ColorRect.new()
    vis.size = Vector2(16, 16)
    vis.position = Vector2(-8, -8)
    
    # Color coding items
    if item_name == "Health Potion":
        vis.color = Color(0.9, 0.2, 0.2)
    elif item_name == "Mana Elixir":
        vis.color = Color(0.2, 0.2, 0.9)
    else: # Gold Coin
        vis.color = Color(0.9, 0.8, 0.1)
        
    item.add_child(vis)

func _spawn_enemy_internal(enemy_name: String, pos: Vector2) -> void:
    var enemy = Node2D.new()
    enemy.name = enemy_name
    enemy.position = pos
    enemy.set_meta("target_dir", Vector2(randf_range(-1,1), randf_range(-1,1)).normalized())
    enemy_container.add_child(enemy)
    
    var vis = ColorRect.new()
    vis.size = Vector2(24, 24)
    vis.position = Vector2(-12, -12)
    vis.color = Color(0.9, 0.1, 0.1)
    enemy.add_child(vis)
    
    var lbl = Label.new()
    lbl.text = enemy_name
    lbl.position = Vector2(-30, -32)
    lbl.custom_minimum_size = Vector2(60, 20)
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.add_theme_font_size_override("font_size", 10)
    enemy.add_child(lbl)

# --- MCP Tool Registrations ---
func _register_demo_mcp_tools() -> void:
    # 1. Get Player Status
    MCPServer.register_function(
        "get_player_status",
        "Gets the current status of the RPG Player character (Health, Mana, Inventory, Position, and visible items/enemies).",
        {},
        func(_args: Dictionary) -> Dictionary:
            var items_list = []
            for item in item_container.get_children():
                items_list.append({
                    "name": item.get_meta("item_name", "Gold Coin"),
                    "position": [item.position.x, item.position.y]
                })
            var enemies_list = []
            for enemy in enemy_container.get_children():
                enemies_list.append({
                    "name": enemy.name,
                    "position": [enemy.position.x, enemy.position.y]
                })
            return {
                "isError": false,
                "content": [{
                    "type": "text",
                    "text": JSON.stringify({
                        "health": player_health,
                        "max_health": player_max_health,
                        "mana": player_mana,
                        "position": [player_node.position.x, player_node.position.y],
                        "inventory": player_inventory,
                        "map_items": items_list,
                        "map_enemies": enemies_list
                    }, "  ")
                }]
            }
    )
    
    # 2. Heal Player
    MCPServer.register_function(
        "heal_player",
        "Heals the player by a specified amount (restoring HP).",
        {
            "type": "object",
            "properties": {
                "amount": { "type": "integer", "description": "HP points to heal (caps at max health)" }
            },
            "required": ["amount"]
        },
        func(args: Dictionary) -> Dictionary:
            var amt = int(args.get("amount", 0))
            player_health = min(player_max_health, player_health + amt)
            _log_message("MCP: Restored %d Health to player." % amt)
            return {
                "isError": false,
                "content": [{"type": "text", "text": "Healed player by %d HP. Health is now %d." % [amt, player_health]}]
            }
    )
    
    # 3. Teleport Player
    MCPServer.register_function(
        "teleport_player",
        "Instantly teleports the player character to specified X/Y coordinates in the play area (range 0 to 800).",
        {
            "type": "object",
            "properties": {
                "x": { "type": "number", "description": "X position (0 to 800)" },
                "y": { "type": "number", "description": "Y position (0 to 648)" }
            },
            "required": ["x", "y"]
        },
        func(args: Dictionary) -> Dictionary:
            var tx = clampf(float(args.get("x", 400.0)), 16.0, play_area_width - 16.0)
            var ty = clampf(float(args.get("y", 300.0)), 16.0, screen_height - 16.0)
            
            # Defer position changes to next idle frame to comply with thread safety (Execution Rule)
            player_node.call_deferred("set_position", Vector2(tx, ty))
            _log_message("MCP: Teleported player to (%d, %d)." % [tx, ty])
            return {
                "isError": false,
                "content": [{"type": "text", "text": "Teleported player to (%d, %d)." % [tx, ty]}]
            }
    )
    
    # 4. Give Inventory Item
    MCPServer.register_function(
        "give_item",
        "Adds an item to the player's inventory list (e.g. 'Health Potion', 'Mana Elixir', 'Gold Coin', 'Dragon Shield').",
        {
            "type": "object",
            "properties": {
                "item_name": { "type": "string", "description": "Name of the item to add" }
            },
            "required": ["item_name"]
        },
        func(args: Dictionary) -> Dictionary:
            var item_name = args.get("item_name", "")
            if item_name == "":
                return { "isError": true, "content": [{"type": "text", "text": "Item name is required."}] }
            player_inventory.append(item_name)
            _log_message("MCP: Gave player item '%s'." % item_name)
            return {
                "isError": false,
                "content": [{"type": "text", "text": "Gave player '%s'." % item_name}]
            }
    )
    
    # 5. Spawn Enemy
    MCPServer.register_function(
        "spawn_enemy",
        "Spawns a new enemy character at a specified location.",
        {
            "type": "object",
            "properties": {
                "name": { "type": "string", "description": "Name for the enemy" },
                "x": { "type": "number", "description": "X coordinate to spawn (0 to 800)" },
                "y": { "type": "number", "description": "Y coordinate to spawn (0 to 648)" }
            },
            "required": ["name", "x", "y"]
        },
        func(args: Dictionary) -> Dictionary:
            var name = args.get("name", "Slime")
            var tx = clampf(float(args.get("x", 400.0)), 20.0, play_area_width - 20.0)
            var ty = clampf(float(args.get("y", 300.0)), 20.0, screen_height - 20.0)
            
            # Defer structural spawning changes to respect the Execution Rule
            call_deferred("_spawn_enemy_internal", name, Vector2(tx, ty))
            _log_message("MCP: Spawned enemy '%s' at (%d, %d)." % [name, tx, ty])
            return {
                "isError": false,
                "content": [{"type": "text", "text": "Spawned enemy '%s' at (%d, %d)." % [name, tx, ty]}]
            }
    )
