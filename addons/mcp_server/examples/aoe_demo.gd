extends Node2D

# 2D AoE-like RTS Demo showcasing multi-agent and human player coexistence in a single game process.
# Players:
#   0: Human (Blue)
#   1: Agent 1 (Red)
#   2: Agent 2 (Green)

# --- Game State & Player Resources ---
var players = {
	0: { "name": "Human", "wood": 300, "gold": 300, "food": 300, "pop": 0, "cap": 10, "color": Color(0.23, 0.53, 1.0) }, # Blue
	1: { "name": "Agent 1", "wood": 300, "gold": 300, "food": 300, "pop": 0, "cap": 10, "color": Color(1.0, 0.05, 0.4) }, # Red
	2: { "name": "Agent 2", "wood": 300, "gold": 300, "food": 300, "pop": 0, "cap": 10, "color": Color(0.1, 0.8, 0.2) } # Green
}

var screen_width: float = 1152.0
var screen_height: float = 648.0
var play_area_width: float = 800.0

var next_entity_id: int = 1

# --- Node Containers ---
var resource_container: Node2D
var building_container: Node2D
var unit_container: Node2D

# --- Human Selection & Input ---
var selected_entities: Array[Node] = []
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_current: Vector2 = Vector2.ZERO

# --- Construction Placement Mode (Human) ---
var placement_mode: bool = false
var placement_type: String = "" # "barracks", "house"
var placement_cost: int = 0

# --- UI Controls ---
var players_grid: GridContainer
var selection_title: Label
var selection_details: Label
var action_panel: HBoxContainer
var conn_label: Label
var log_text: RichTextLabel

func _ready() -> void:
	# 1. Setup play area background
	var bg = ColorRect.new()
	bg.color = Color(0.18, 0.28, 0.15) # Grass Green Theme
	bg.size = Vector2(play_area_width, screen_height)
	add_child(bg)
	
	# 2. Setup sidebar background panel (glassmorphism/dark style)
	var sidebar_bg = ColorRect.new()
	sidebar_bg.color = Color(0.06, 0.07, 0.1)
	sidebar_bg.position = Vector2(play_area_width, 0)
	sidebar_bg.size = Vector2(screen_width - play_area_width, screen_height)
	add_child(sidebar_bg)
	
	# Border line separating play area and sidebar
	var border = ColorRect.new()
	border.color = Color(0.2, 0.25, 0.3)
	border.position = Vector2(play_area_width, 0)
	border.size = Vector2(2, screen_height)
	add_child(border)
	
	# 3. Create Entity Containers
	resource_container = Node2D.new()
	resource_container.name = "Resources"
	add_child(resource_container)
	
	building_container = Node2D.new()
	building_container.name = "Buildings"
	add_child(building_container)
	
	unit_container = Node2D.new()
	unit_container.name = "Units"
	add_child(unit_container)
	
	# 4. Populate Resources
	_spawn_initial_resources()
	
	# 5. Spawn Player Starting Entities (Town Center + 3 Villagers)
	# Player 0 (Human, top-left)
	_spawn_building_internal(0, "town_center", Vector2(150, 150))
	_spawn_unit_internal(0, "villager", Vector2(150, 220))
	_spawn_unit_internal(0, "villager", Vector2(210, 150))
	_spawn_unit_internal(0, "villager", Vector2(220, 220))
	
	# Player 1 (Agent 1, bottom-left)
	_spawn_building_internal(1, "town_center", Vector2(150, 500))
	_spawn_unit_internal(1, "villager", Vector2(150, 430))
	_spawn_unit_internal(1, "villager", Vector2(220, 500))
	_spawn_unit_internal(1, "villager", Vector2(220, 430))
	
	# Player 2 (Agent 2, center-right)
	_spawn_building_internal(2, "town_center", Vector2(650, 324))
	_spawn_unit_internal(2, "villager", Vector2(580, 324))
	_spawn_unit_internal(2, "villager", Vector2(650, 250))
	_spawn_unit_internal(2, "villager", Vector2(580, 250))
	
	# 6. Initialize UI
	_setup_ui()
	
	# 7. Connect to MCP Server tool logger
	MCPServer.tool_called.connect(_on_mcp_tool_called)
	
	# 8. Register MCP RTS tools
	_register_rts_mcp_tools()
	
	_log_message("System: RTS Game initialized. Port 9090 is active.")

func _exit_tree() -> void:
	# Clean up registered tools when leaving the scene
	MCPServer.unregister_tool_name("aoe_get_game_state")
	MCPServer.unregister_tool_name("aoe_command_units")
	MCPServer.unregister_tool_name("aoe_spawn_unit")
	MCPServer.unregister_tool_name("aoe_place_building")
	_log_message("System: RTS Game tools unregistered.")

func _spawn_initial_resources() -> void:
	# Gold Mines (600 gold)
	_spawn_resource_internal("gold_mine", Vector2(400, 324)) # Center gold
	_spawn_resource_internal("gold_mine", Vector2(100, 324)) # West gold
	_spawn_resource_internal("gold_mine", Vector2(680, 140)) # Northeast gold
	_spawn_resource_internal("gold_mine", Vector2(680, 500)) # Southeast gold
	
	# Berry Bushes (400 food)
	_spawn_resource_internal("berry_bush", Vector2(260, 160)) # Near Human
	_spawn_resource_internal("berry_bush", Vector2(260, 490)) # Near Agent 1
	_spawn_resource_internal("berry_bush", Vector2(550, 324)) # Near Agent 2
	_spawn_resource_internal("berry_bush", Vector2(400, 100)) # North berry
	_spawn_resource_internal("berry_bush", Vector2(400, 548)) # South berry
	
	# Trees (300 wood)
	var tree_coords = [
		Vector2(60, 60), Vector2(80, 50), Vector2(50, 80), # Human forest
		Vector2(60, 580), Vector2(80, 590), Vector2(50, 560), # Agent 1 forest
		Vector2(730, 280), Vector2(740, 300), Vector2(720, 320), # Agent 2 forest
		Vector2(400, 180), Vector2(430, 190), # North forest
		Vector2(400, 460), Vector2(370, 450)  # South forest
	]
	for coord in tree_coords:
		_spawn_resource_internal("tree", coord)

func _process(_delta: float) -> void:
	queue_redraw() # Refresh rendering of selection rings, paths, and health bars
	_update_ui_displays()

func _physics_process(delta: float) -> void:
	# 1. Update Population Caps & Counts
	_recalculate_population()
	
	# 2. Simulate Buildings (Spawn queue progress)
	_simulate_buildings(delta)
	
	# 3. Simulate Units (Movement, Gathering, Attacking, Building)
	_simulate_units(delta)

# --- Population and Caps ---
func _recalculate_population() -> void:
	# Reset populations
	for p_id in players:
		players[p_id]["pop"] = 0
		players[p_id]["cap"] = 10 # Starting Town Center cap
		
	# Calculate caps from completed Town Centers (+10) and Houses (+5)
	for building in building_container.get_children():
		if building.is_under_construction:
			continue
		var owner_id = building.owner_id
		if not players.has(owner_id):
			continue
		if building.building_type == "town_center":
			players[owner_id]["cap"] = min(50, players[owner_id]["cap"] + 10)
		elif building.building_type == "house":
			players[owner_id]["cap"] = min(50, players[owner_id]["cap"] + 5)
			
	# Count units
	for unit in unit_container.get_children():
		var owner_id = unit.owner_id
		if players.has(owner_id):
			players[owner_id]["pop"] += 1

# --- Building Simulation ---
func _simulate_buildings(delta: float) -> void:
	for building in building_container.get_children():
		if building.is_under_construction:
			continue
		if building.spawn_queue.is_empty():
			building.spawn_progress = 0.0
			continue
			
		building.spawn_progress += delta
		var time_needed = 4.0 if building.spawn_queue[0] == "villager" else 6.0
		
		if building.spawn_progress >= time_needed:
			var unit_type = building.spawn_queue.pop_front()
			building.spawn_progress = 0.0
			
			# Spawn unit near building
			var spawn_pos = building.position + Vector2(randf_range(-30, 30), randf_range(40, 60))
			_spawn_unit_internal(building.owner_id, unit_type, spawn_pos)

# --- Unit Simulation (Steering + AI tasks) ---
func _simulate_units(delta: float) -> void:
	var units = unit_container.get_children()
	
	# Gather references for targets
	var resources = resource_container.get_children()
	var buildings = building_container.get_children()
	
	for unit in units:
		var target_vel = Vector2.ZERO
		var speed = 130.0 if unit.unit_type == "villager" else 165.0
		
		# Decool attack timers
		if unit.has_meta("attack_cooldown"):
			var cd = unit.get_meta("attack_cooldown") - delta
			unit.set_meta("attack_cooldown", max(0.0, cd))
		else:
			unit.set_meta("attack_cooldown", 0.0)
			
		# Handle State Machine
		match unit.state:
			"idle":
				pass
				
			"moving":
				var dist = unit.position.distance_to(unit.target_position)
				if dist > 8.0:
					target_vel = (unit.target_position - unit.position).normalized() * speed
				else:
					unit.state = "idle"
					
			"gathering":
				# Find resource node
				var res_node = _find_entity_by_id(resources, unit.target_entity_id)
				if res_node:
					var dist = unit.position.distance_to(res_node.position)
					if dist > 25.0:
						# Move to resource
						target_vel = (res_node.position - unit.position).normalized() * speed
					else:
						# Close enough, gather!
						unit.cargo_type = _get_resource_cargo_type(res_node.resource_type)
						unit.cargo_amount = min(unit.max_cargo, unit.cargo_amount + 2.5 * delta)
						
						# Deduct resource node amount
						res_node.amount -= 2.5 * delta
						if res_node.amount <= 0:
							res_node.queue_free()
							unit.state = "returning"
							
						if unit.cargo_amount >= unit.max_cargo:
							unit.state = "returning"
				else:
					# Resource node was deleted/depleted. Auto-find nearby resource of same type
					var nearest = _find_nearest_resource(unit.position, unit.cargo_type)
					if nearest:
						unit.target_entity_id = nearest.resource_id
					else:
						# No other nodes, return cargo if any
						if unit.cargo_amount > 0:
							unit.state = "returning"
						else:
							unit.state = "idle"
							
			"returning":
				# Find closest friendly Town Center
				var tc = _find_closest_town_center(unit.position, unit.owner_id)
				if tc:
					var dist = unit.position.distance_to(tc.position)
					if dist > 35.0:
						target_vel = (tc.position - unit.position).normalized() * speed
					else:
						# Deposit!
						var type_str = unit.cargo_type
						if type_str != "none":
							players[unit.owner_id][type_str] = players[unit.owner_id][type_str] + int(unit.cargo_amount)
							unit.cargo_amount = 0.0
							
						# Head back to resource if it's still alive
						var res_node = _find_entity_by_id(resources, unit.target_entity_id)
						if res_node:
							unit.state = "gathering"
						else:
							var nearest = _find_nearest_resource(unit.position, type_str)
							if nearest:
								unit.target_entity_id = nearest.resource_id
								unit.state = "gathering"
							else:
								unit.state = "idle"
				else:
					# No Town Center! Go idle
					unit.state = "idle"
					
			"building":
				var b_node = _find_entity_by_id(buildings, unit.target_entity_id)
				if b_node and b_node.is_under_construction:
					var dist = unit.position.distance_to(b_node.position)
					if dist > 35.0:
						target_vel = (b_node.position - unit.position).normalized() * speed
					else:
						# Construct building
						b_node.health = min(b_node.max_health, b_node.health + 20.0 * delta)
						if b_node.health >= b_node.max_health:
							b_node.is_under_construction = false
							unit.state = "idle"
				else:
					unit.state = "idle"
					
			"attacking":
				# Target can be a unit or a building
				var target_node = _find_entity_by_id(units, unit.target_entity_id)
				var is_building = false
				if not target_node:
					target_node = _find_entity_by_id(buildings, unit.target_entity_id)
					is_building = true
					
				if target_node and target_node.owner_id != unit.owner_id:
					var range_needed = 45.0 if is_building else 25.0
					var dist = unit.position.distance_to(target_node.position)
					if dist > range_needed:
						target_vel = (target_node.position - unit.position).normalized() * speed
					else:
						# Attack!
						var cd = unit.get_meta("attack_cooldown")
						if cd <= 0.0:
							var dmg = 6.0 if unit.unit_type == "villager" else 15.0
							target_node.health -= dmg
							unit.set_meta("attack_cooldown", 1.0) # 1s cooldown
							
							# Visual attack effect flash trigger
							unit.set_meta("attack_flash_t", 0.15)
							unit.set_meta("attack_flash_pos", target_node.position)
							
							if target_node.health <= 0:
								# Destroy!
								_log_message("Combat: Player %d's %s destroyed Player %d's %s!" % [
									unit.owner_id, unit.unit_type.capitalize(),
									target_node.owner_id, (target_node.building_type if is_building else target_node.unit_type).capitalize()
								])
								target_node.queue_free()
								
								# Clean up selection if human selection dies
								if target_node in selected_entities:
									selected_entities.erase(target_node)
									
								unit.state = "idle"
				else:
					unit.state = "idle"
		
		# 4. Multi-agent steering separation force (prevents perfect stacking)
		var separation = Vector2.ZERO
		for other in units:
			if other != unit:
				var dist = unit.position.distance_to(other.position)
				if dist < 16.0 and dist > 0.1:
					separation += (unit.position - other.position).normalized() * (16.0 - dist) * 8.0
					
		# Apply final movement
		var final_vel = target_vel + separation
		unit.position += final_vel * delta
		unit.position.x = clamp(unit.position.x, 15.0, play_area_width - 15.0)
		unit.position.y = clamp(unit.position.y, 15.0, screen_height - 15.0)

# --- Drawing Utilities (Glow selection rings, dash paths, resources) ---
func _draw() -> void:
	# A. Draw play area grid (subtle grassland lines)
	var grid_color = Color(0.22, 0.33, 0.18)
	for x in range(0, int(play_area_width), 50):
		draw_line(Vector2(x, 0), Vector2(x, screen_height), grid_color, 1.0)
	for y in range(0, int(screen_height), 50):
		draw_line(Vector2(0, y), Vector2(play_area_width, y), grid_color, 1.0)
		
	# B. Draw selection box (while dragging)
	if is_dragging:
		var rect = Rect2(drag_start, drag_current - drag_start)
		draw_rect(rect, Color(0.2, 0.6, 1.0, 0.15), true)
		draw_rect(rect, Color(0.2, 0.6, 1.0, 0.6), false, 1.5)
		
	# C. Draw building placement ghost
	if placement_mode:
		var mouse_pos = get_local_mouse_position()
		mouse_pos.x = clamp(mouse_pos.x, 24.0, play_area_width - 24.0)
		mouse_pos.y = clamp(mouse_pos.y, 24.0, screen_height - 24.0)
		
		var size = Vector2(32, 32) if placement_type == "house" else Vector2(48, 48)
		var offset = -size / 2.0
		
		var can_afford = players[0]["wood"] >= placement_cost
		var color = Color(0.2, 1.0, 0.2, 0.4) if can_afford else Color(1.0, 0.2, 0.2, 0.4)
		draw_rect(Rect2(mouse_pos + offset, size), color, true)
		draw_rect(Rect2(mouse_pos + offset, size), color.lightened(0.3), false, 2.0)

	# D. Draw Action Lines (vectors connecting units to their targets)
	for unit in unit_container.get_children():
		var target_p = Vector2.ZERO
		var line_color = Color(0.8, 0.8, 0.8, 0.3)
		if unit.state == "moving":
			target_p = unit.target_position
			line_color = Color(0.2, 0.6, 1.0, 0.35)
		elif unit.state == "gathering" or unit.state == "returning":
			var res = _find_entity_by_id(resource_container.get_children(), unit.target_entity_id)
			if res: target_p = res.position
			line_color = Color(0.8, 0.7, 0.1, 0.35)
		elif unit.state == "building":
			var bld = _find_entity_by_id(building_container.get_children(), unit.target_entity_id)
			if bld: target_p = bld.position
			line_color = Color(0.6, 0.4, 0.2, 0.35)
		elif unit.state == "attacking":
			var enemy = _find_entity_by_id(unit_container.get_children(), unit.target_entity_id)
			if not enemy: enemy = _find_entity_by_id(building_container.get_children(), unit.target_entity_id)
			if enemy: target_p = enemy.position
			line_color = Color(1.0, 0.1, 0.1, 0.5)
			
		if target_p != Vector2.ZERO:
			draw_line(unit.position, target_p, line_color, 1.0)

# --- Helper drawing methods ---
func _draw_polygon_node(center: Vector2, radius: float, sides: int, color: Color) -> void:
	var points = PackedVector2Array()
	for i in range(sides):
		var angle = i * TAU / sides
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)
	draw_polyline(points, color.lightened(0.25), 1.5)

func _draw_small_bar(pos: Vector2, width: float, pct: float, color: Color) -> void:
	# Background (red)
	draw_rect(Rect2(pos, Vector2(width, 3)), Color(0.7, 0.1, 0.1), true)
	# Filled (green or custom color)
	draw_rect(Rect2(pos, Vector2(width * pct, 3)), color, true)

# --- Spawning Mechanics ---
func _spawn_resource_internal(type: String, pos: Vector2) -> AoEResource:
	var res = AoEResource.new()
	res.resource_type = type
	res.position = pos
	
	if type == "gold_mine":
		res.amount = 600.0
		res.max_amount = 600.0
	elif type == "berry_bush":
		res.amount = 400.0
		res.max_amount = 400.0
	else:
		res.amount = 300.0
		res.max_amount = 300.0
		
	res.resource_id = next_entity_id
	next_entity_id += 1
	res.name = "Resource_%s_%d" % [type.capitalize(), res.resource_id]
	resource_container.add_child(res)
	return res

func _spawn_building_internal(owner_id: int, type: String, pos: Vector2, is_construction: bool = false) -> AoEBuilding:
	var bld = AoEBuilding.new()
	bld.owner_id = owner_id
	bld.building_type = type
	bld.position = pos
	bld.is_under_construction = is_construction
	
	if type == "town_center":
		bld.max_health = 1000.0
	elif type == "barracks":
		bld.max_health = 500.0
	else: # house
		bld.max_health = 200.0
		
	bld.health = bld.max_health * 0.1 if is_construction else bld.max_health
	
	bld.building_id = next_entity_id
	next_entity_id += 1
	bld.name = "Building_%s_P%d_%d" % [type.capitalize(), owner_id, bld.building_id]
	building_container.add_child(bld)
	
	# Instantly recalculate limits
	_recalculate_population()
	return bld

func _spawn_unit_internal(owner_id: int, type: String, pos: Vector2) -> AoEUnit:
	# Verify population cap first
	_recalculate_population()
	if players[owner_id]["pop"] >= players[owner_id]["cap"]:
		_log_message("Economy: Player %d hit population cap (%d/%d). Spawn canceled." % [owner_id, players[owner_id]["pop"], players[owner_id]["cap"]])
		return null
		
	var unit = AoEUnit.new()
	unit.owner_id = owner_id
	unit.unit_type = type
	unit.position = pos
	
	if type == "villager":
		unit.health = 50.0
		unit.max_health = 50.0
	else: # soldier
		unit.health = 100.0
		unit.max_health = 100.0
		
	unit.unit_id = next_entity_id
	next_entity_id += 1
	unit.name = "Unit_%s_P%d_%d" % [type.capitalize(), owner_id, unit.unit_id]
	unit_container.add_child(unit)
	
	# Recalculate limits
	_recalculate_population()
	return unit

# --- Entity Finder Helpers ---
func _find_entity_by_id(list: Array, id: int) -> Node:
	for item in list:
		if "unit_id" in item and item.unit_id == id:
			return item
		if "building_id" in item and item.building_id == id:
			return item
		if "resource_id" in item and item.resource_id == id:
			return item
	return null

func _find_nearest_resource(pos: Vector2, cargo_type: String) -> AoEResource:
	var target_res_type = "tree"
	if cargo_type == "gold":
		target_res_type = "gold_mine"
	elif cargo_type == "food":
		target_res_type = "berry_bush"
		
	var closest: AoEResource = null
	var min_d = 999999.0
	for res in resource_container.get_children():
		if res.resource_type == target_res_type and res.amount > 0:
			var d = pos.distance_to(res.position)
			if d < min_d:
				min_d = d
				closest = res
	return closest

func _find_closest_town_center(pos: Vector2, owner_id: int) -> AoEBuilding:
	var closest: AoEBuilding = null
	var min_d = 999999.0
	for bld in building_container.get_children():
		if bld.owner_id == owner_id and bld.building_type == "town_center" and not bld.is_under_construction:
			var d = pos.distance_to(bld.position)
			if d < min_d:
				min_d = d
				closest = bld
	return closest

func _get_resource_cargo_type(res_type: String) -> String:
	if res_type == "tree": return "wood"
	if res_type == "gold_mine": return "gold"
	if res_type == "berry_bush": return "food"
	return "none"

# --- Human Mouse Input Processing ---
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# A. Handle Placement Mode clicks
		if placement_mode:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				var m_pos = get_local_mouse_position()
				if m_pos.x < play_area_width:
					# Verify cost
					if players[0]["wood"] >= placement_cost:
						players[0]["wood"] -= placement_cost
						_log_message("Human: Placed %s building site at (%d, %d)." % [placement_type.capitalize(), int(m_pos.x), int(m_pos.y)])
						
						# Spawn building deferred (Execution Rule)
						var new_bld = _spawn_building_internal(0, placement_type, m_pos, true)
						
						# Command selected villagers to build it
						for unit in selected_entities:
							if unit is AoEUnit and unit.unit_type == "villager" and unit.owner_id == 0:
								unit.state = "building"
								unit.target_entity_id = new_bld.building_id
								unit.target_position = new_bld.position
								
						placement_mode = false
						queue_redraw()
					else:
						_log_message("System: Not enough wood to construct %s!" % placement_type.capitalize())
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				# Cancel placement
				placement_mode = false
				_log_message("System: Construction placement canceled.")
				queue_redraw()
				return
				
		# B. Left-click Selection Input
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start dragging
				is_dragging = true
				drag_start = get_local_mouse_position()
				drag_current = drag_start
			else:
				# Stop dragging & resolve selection
				is_dragging = false
				drag_current = get_local_mouse_position()
				
				# Clear old selection
				selected_entities.clear()
				
				if drag_start.distance_to(drag_current) < 5.0:
					# Click selection
					var click_pos = drag_start
					if click_pos.x < play_area_width:
						# 1. Search units
						var selected_unit: AoEUnit = null
						var min_dist = 15.0
						for unit in unit_container.get_children():
							var dist = unit.position.distance_to(click_pos)
							if dist < min_dist:
								min_dist = dist
								selected_unit = unit
								
						if selected_unit:
							selected_entities.append(selected_unit)
						else:
							# 2. Search buildings
							var selected_bld: AoEBuilding = null
							for bld in building_container.get_children():
								var size = 32.0 if bld.building_type == "town_center" else 24.0
								if bld.position.distance_to(click_pos) < size:
									selected_bld = bld
									break
							if selected_bld:
								selected_entities.append(selected_bld)
							else:
								# 3. Search resources
								var selected_res: AoEResource = null
								for res in resource_container.get_children():
									var size = 16.0 if res.resource_type == "gold_mine" else 10.0
									if res.position.distance_to(click_pos) < size:
										selected_res = res
										break
								if selected_res:
									selected_entities.append(selected_res)
				else:
					# Drag box selection (only selects human-owned units)
					var box = Rect2(
						Vector2(min(drag_start.x, drag_current.x), min(drag_start.y, drag_current.y)),
						Vector2(abs(drag_start.x - drag_current.x), abs(drag_start.y - drag_current.y))
					)
					
					for unit in unit_container.get_children():
						if unit.owner_id == 0 and box.has_point(unit.position):
							selected_entities.append(unit)
							
				queue_redraw()
				
		# C. Right-click Actions (Commands to selected units)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var click_pos = get_local_mouse_position()
			if click_pos.x < play_area_width and not selected_entities.is_empty():
				# Check if right-clicked on resources, buildings, or enemy units
				var clicked_res: AoEResource = null
				for res in resource_container.get_children():
					var size = 18.0 if res.resource_type == "gold_mine" else 12.0
					if res.position.distance_to(click_pos) < size:
						clicked_res = res
						break
						
				var clicked_bld: AoEBuilding = null
				for bld in building_container.get_children():
					var size = 32.0 if bld.building_type == "town_center" else 24.0
					if bld.position.distance_to(click_pos) < size:
						clicked_bld = bld
						break
						
				var clicked_unit: AoEUnit = null
				for unit in unit_container.get_children():
					if unit.position.distance_to(click_pos) < 15.0:
						clicked_unit = unit
						break
						
				# Issue commands to all selected human villagers/soldiers
				for item in selected_entities:
					if item is AoEUnit and item.owner_id == 0:
						if clicked_res:
							# Gather command
							if item.unit_type == "villager":
								item.state = "gathering"
								item.target_entity_id = clicked_res.resource_id
								item.target_position = clicked_res.position
								_log_message("Player: Command Villager %d to gather resource %d." % [item.unit_id, clicked_res.resource_id])
						elif clicked_bld:
							# Build or attack command
							if clicked_bld.owner_id != 0: # Enemy building
								item.state = "attacking"
								item.target_entity_id = clicked_bld.building_id
								item.target_position = clicked_bld.position
								_log_message("Player: Command %s %d to attack enemy building %d." % [item.unit_type.capitalize(), item.unit_id, clicked_bld.building_id])
							elif clicked_bld.is_under_construction: # Repair/Build friendly
								if item.unit_type == "villager":
									item.state = "building"
									item.target_entity_id = clicked_bld.building_id
									item.target_position = clicked_bld.position
									_log_message("Player: Command Villager %d to construct building %d." % [item.unit_id, clicked_bld.building_id])
						elif clicked_unit:
							# Attack command
							if clicked_unit.owner_id != 0: # Enemy unit
								item.state = "attacking"
								item.target_entity_id = clicked_unit.unit_id
								item.target_position = clicked_unit.position
								_log_message("Player: Command %s %d to attack enemy unit %d." % [item.unit_type.capitalize(), item.unit_id, clicked_unit.unit_id])
						else:
							# Movement command
							item.state = "moving"
							item.target_position = click_pos
							item.target_entity_id = -1
							_log_message("Player: Command %s %d to move to (%d, %d)." % [item.unit_type.capitalize(), item.unit_id, int(click_pos.x), int(click_pos.y)])
				queue_redraw()

	elif event is InputEventMouseMotion:
		if is_dragging:
			drag_current = get_local_mouse_position()
			queue_redraw()

# --- Deferred State Mutations (Execution Rule) ---
func _deferred_command_units(player_id: int, unit_ids: Array, action: String, target_pos: Vector2, target_id: int) -> void:
	var units = unit_container.get_children()
	var resources = resource_container.get_children()
	var buildings = building_container.get_children()
	
	for unit in units:
		if unit.owner_id == player_id and unit.unit_id in unit_ids:
			match action:
				"move":
					unit.state = "moving"
					unit.target_position = target_pos
					unit.target_entity_id = -1
					
				"gather":
					if unit.unit_type == "villager":
						var res = _find_entity_by_id(resources, target_id)
						if res:
							unit.state = "gathering"
							unit.target_entity_id = target_id
							unit.target_position = res.position
							
				"attack":
					var enemy = _find_entity_by_id(units, target_id)
					if not enemy:
						enemy = _find_entity_by_id(buildings, target_id)
					if enemy and enemy.owner_id != player_id:
						unit.state = "attacking"
						unit.target_entity_id = target_id
						unit.target_position = enemy.position

func _deferred_spawn_unit(player_id: int, building_id: int, unit_type: String) -> void:
	var bld = _find_entity_by_id(building_container.get_children(), building_id)
	if bld and bld.owner_id == player_id and not bld.is_under_construction:
		# Deduct resources & add to queue
		var food_cost = 50
		var gold_cost = 30 if unit_type == "soldier" else 0
		
		# Check limit
		_recalculate_population()
		var queued_count = 0
		for b in building_container.get_children():
			if b.owner_id == player_id:
				queued_count += b.spawn_queue.size()
				
		if players[player_id]["pop"] + queued_count >= players[player_id]["cap"]:
			_log_message("Economy: Player %d hit population cap. Training failed." % player_id)
			return
			
		if players[player_id]["food"] >= food_cost and players[player_id]["gold"] >= gold_cost:
			players[player_id]["food"] -= food_cost
			players[player_id]["gold"] -= gold_cost
			bld.spawn_queue.append(unit_type)
			_log_message("Building: Player %d's TC/Barracks queued %s." % [player_id, unit_type.capitalize()])
		else:
			_log_message("System: Player %d insufficient resources to spawn %s." % [player_id, unit_type])

func _deferred_place_building(player_id: int, villager_id: int, building_type: String, pos: Vector2) -> void:
	var builder = _find_entity_by_id(unit_container.get_children(), villager_id)
	if builder and builder.owner_id == player_id and builder.unit_type == "villager":
		var cost = 50 if building_type == "house" else 150
		if players[player_id]["wood"] >= cost:
			players[player_id]["wood"] -= cost
			var site = _spawn_building_internal(player_id, building_type, pos, true)
			
			builder.state = "building"
			builder.target_entity_id = site.building_id
			builder.target_position = site.position
			_log_message("Building: Player %d placed %s site at (%d, %d)." % [player_id, building_type.capitalize(), int(pos.x), int(pos.y)])
		else:
			_log_message("System: Player %d insufficient wood for %s." % [player_id, building_type])

# --- UI Sidebar Layout Setup ---
func _setup_ui() -> void:
	var layout = VBoxContainer.new()
	layout.position = Vector2(play_area_width + 15, 15)
	layout.size = Vector2(screen_width - play_area_width - 30, screen_height - 30)
	add_child(layout)
	
	# Title
	var title = Label.new()
	title.text = "2D MULTI-PLAYER RTS DEMO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	layout.add_child(title)
	layout.add_child(HSeparator.new())
	
	# Resource Table Title
	var table_hdr = Label.new()
	table_hdr.text = "Player Telemetry"
	table_hdr.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	layout.add_child(table_hdr)
	
	# Resources Grid
	players_grid = GridContainer.new()
	players_grid.columns = 5
	players_grid.add_theme_constant_override("h_separation", 10)
	players_grid.add_theme_constant_override("v_separation", 6)
	
	# Grid header labels
	var headers = ["Player", "Food", "Wood", "Gold", "Pop"]
	for h in headers:
		var lbl = Label.new()
		lbl.text = h
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
		players_grid.add_child(lbl)
		
	layout.add_child(players_grid)
	layout.add_child(HSeparator.new())
	
	# Map Legend Section
	var legend_hdr = Label.new()
	legend_hdr.text = "Thematic Map Legend"
	legend_hdr.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	layout.add_child(legend_hdr)
	
	var legend_grid = GridContainer.new()
	legend_grid.columns = 2
	legend_grid.add_theme_constant_override("h_separation", 15)
	legend_grid.add_theme_constant_override("v_separation", 4)
	
	var legend_items = [
		["🌲 Tree (Green Canopy)", "Wood resource"],
		["🪙 Gold Mine (Outcrop)", "Gold resource"],
		["🍒 Berry Bush (Berries)", "Food resource"],
		["🏛️ Town Center (Keep)", "Trains Villagers"],
		["🛡️ Barracks (Crossed Swords)", "Trains Soldiers"],
		["🏠 House (Pitched Roof)", "Adds +5 Pop Cap"],
		["🧑‍🌾 Villager (Straw Hat)", "Gathers / Builds"],
		["⚔️ Soldier (Steel Helmet)", "Attacks / Guards"]
	]
	
	for pair in legend_items:
		var name_lbl = Label.new()
		name_lbl.text = pair[0]
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		legend_grid.add_child(name_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = pair[1]
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		legend_grid.add_child(desc_lbl)
		
	layout.add_child(legend_grid)
	layout.add_child(HSeparator.new())
	
	# Selection Panel
	selection_title = Label.new()
	selection_title.text = "No Selection"
	selection_title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	layout.add_child(selection_title)
	
	selection_details = Label.new()
	selection_details.text = "Select units with Left Click/Drag.\nRight Click to command."
	selection_details.add_theme_font_size_override("font_size", 11)
	selection_details.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	layout.add_child(selection_details)
	
	action_panel = HBoxContainer.new()
	action_panel.add_theme_constant_override("separation", 10)
	layout.add_child(action_panel)
	
	layout.add_child(HSeparator.new())
	
	# Connected clients
	conn_label = Label.new()
	conn_label.text = "MCP Clients: 0 connected"
	conn_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.1))
	layout.add_child(conn_label)
	
	# Logs Label
	var logs_hdr = Label.new()
	logs_hdr.text = "Server Event Logs:"
	layout.add_child(logs_hdr)
	
	log_text = RichTextLabel.new()
	log_text.custom_minimum_size = Vector2(0, 110)
	log_text.scroll_active = true
	log_text.scroll_following = true
	log_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	log_text.add_theme_color_override("default_color", Color(0.7, 0.9, 0.7))
	log_text.add_theme_font_size_override("normal_font_size", 10)
	layout.add_child(log_text)

func _update_ui_displays() -> void:
	# 1. Update Grid Content
	# Clear old values (skip headers, which is columns = 5 elements)
	while players_grid.get_child_count() > 5:
		var c = players_grid.get_child(5)
		players_grid.remove_child(c)
		c.queue_free()
		
	# Populate values
	for id in [0, 1, 2]:
		var p_info = players[id]
		var col = p_info["color"]
		
		var name_lbl = Label.new()
		name_lbl.text = p_info["name"]
		name_lbl.add_theme_color_override("font_color", col)
		name_lbl.add_theme_font_size_override("font_size", 11)
		players_grid.add_child(name_lbl)
		
		var food_lbl = Label.new()
		food_lbl.text = str(p_info["food"])
		food_lbl.add_theme_font_size_override("font_size", 11)
		players_grid.add_child(food_lbl)
		
		var wood_lbl = Label.new()
		wood_lbl.text = str(p_info["wood"])
		wood_lbl.add_theme_font_size_override("font_size", 11)
		players_grid.add_child(wood_lbl)
		
		var gold_lbl = Label.new()
		gold_lbl.text = str(p_info["gold"])
		gold_lbl.add_theme_font_size_override("font_size", 11)
		players_grid.add_child(gold_lbl)
		
		var pop_lbl = Label.new()
		pop_lbl.text = "%d/%d" % [p_info["pop"], p_info["cap"]]
		pop_lbl.add_theme_font_size_override("font_size", 11)
		players_grid.add_child(pop_lbl)
		
	# 2. Update Connection Status
	var count = MCPServer.connected_peers.size()
	conn_label.text = "MCP Clients: %d connected" % count
	if count > 0:
		conn_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))
	else:
		conn_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.1))
		
	# 3. Update Selection Info & Action Panel
	_update_selection_panel()

func _update_selection_panel() -> void:
	# Clear old buttons
	for b in action_panel.get_children():
		action_panel.remove_child(b)
		b.queue_free()
		
	if selected_entities.is_empty():
		selection_title.text = "No Selection"
		selection_details.text = "Select units with Left Click/Drag.\nRight Click to command."
		return
		
	var first = selected_entities[0]
	if not is_instance_valid(first):
		selected_entities.clear()
		return
		
	if first is AoEUnit:
		var v_count = 0
		var s_count = 0
		for e in selected_entities:
			if e is AoEUnit:
				if e.unit_type == "villager": v_count += 1
				else: s_count += 1
				
		if selected_entities.size() == 1:
			selection_title.text = "%s (ID: %d)" % [first.unit_type.capitalize(), first.unit_id]
			var owner_name = players[first.owner_id]["name"]
			var cargo_str = ""
			if first.unit_type == "villager" and first.cargo_amount > 0:
				cargo_str = " | Cargo: %d %s" % [int(first.cargo_amount), first.cargo_type.capitalize()]
			selection_details.text = "Owner: %s\nHealth: %d/%d\nState: %s%s" % [owner_name, int(first.health), int(first.max_health), first.state.capitalize(), cargo_str]
			
			# If human villager: show construct buttons
			if first.owner_id == 0 and first.unit_type == "villager":
				var bh = Button.new()
				bh.text = "House (50w)"
				bh.pressed.connect(func(): _start_placement("house", 50))
				action_panel.add_child(bh)
				
				var bb = Button.new()
				bb.text = "Barracks (150w)"
				bb.pressed.connect(func(): _start_placement("barracks", 150))
				action_panel.add_child(bb)
		else:
			selection_title.text = "Selected Units (%d)" % selected_entities.size()
			selection_details.text = "Villagers: %d\nSoldiers: %d" % [v_count, s_count]
			
	elif first is AoEBuilding:
		selection_title.text = "%s (ID: %d)" % [first.building_type.capitalize().replace("_", " "), first.building_id]
		var owner_name = players[first.owner_id]["name"]
		var build_state = "Healthy" if not first.is_under_construction else "Under Construction"
		var progress_str = ""
		if not first.spawn_queue.is_empty():
			progress_str = "\nTraining: %s (Queue: %d)" % [first.spawn_queue[0].capitalize(), first.spawn_queue.size()]
		selection_details.text = "Owner: %s\nHealth: %d/%d\nStatus: %s%s" % [owner_name, int(first.health), int(first.max_health), build_state, progress_str]
		
		# If human building: show training buttons
		if first.owner_id == 0 and not first.is_under_construction:
			if first.building_type == "town_center":
				var train_v = Button.new()
				train_v.text = "Train Villager (50f)"
				train_v.pressed.connect(func(): _deferred_spawn_unit(0, first.building_id, "villager"))
				action_panel.add_child(train_v)
			elif first.building_type == "barracks":
				var train_s = Button.new()
				train_s.text = "Train Soldier (50f, 30g)"
				train_s.pressed.connect(func(): _deferred_spawn_unit(0, first.building_id, "soldier"))
				action_panel.add_child(train_s)
				
	elif first is AoEResource:
		selection_title.text = "%s (ID: %d)" % [first.resource_type.capitalize().replace("_", " "), first.resource_id]
		selection_details.text = "Amount Remaining: %d/%d" % [int(first.amount), int(first.max_amount)]

func _start_placement(type: String, cost: int) -> void:
	placement_mode = true
	placement_type = type
	placement_cost = cost
	_log_message("System: Placement mode active for %s. Left-click grid to place building." % type.capitalize())

func _log_message(msg: String) -> void:
	var time = Time.get_time_string_from_system()
	log_text.append_text("[%s] %s\n" % [time, msg])

func _on_mcp_tool_called(tool_name: String, arguments: Dictionary, response: Dictionary) -> void:
	if tool_name.begins_with("aoe_"):
		var arg_str = JSON.stringify(arguments)
		var status = "Success" if not response.get("isError", false) else "Error"
		_log_message("AI Call: '%s' with %s -> %s" % [tool_name, arg_str, status])

# --- MCP Tool Registrations ---
func _register_rts_mcp_tools() -> void:
	# 1. Get Game State
	MCPServer.register_function(
		"aoe_get_game_state",
		"Retrieves the complete state of the 2D RTS map, including resources, players, units, and buildings.",
		{
			"type": "object",
			"properties": {
				"player_id": { "type": "integer", "description": "The ID of the player requesting the state (1 or 2)" }
			},
			"required": ["player_id"]
		},
		_on_get_game_state
	)
	
	# 2. Command Units
	MCPServer.register_function(
		"aoe_command_units",
		"Commands a list of owned units to perform an action: move to X/Y coordinates, gather from a resource ID, or attack a target ID.",
		{
			"type": "object",
			"properties": {
				"player_id": { "type": "integer", "description": "Owner ID (1 or 2)" },
				"unit_ids": { "type": "array", "items": { "type": "integer" }, "description": "Array of unit IDs to command" },
				"action": { "type": "string", "enum": ["move", "gather", "attack"], "description": "Action type" },
				"target_position": { "type": "array", "items": { "type": "number" }, "description": "Coordinates [x, y] for movement" },
				"target_id": { "type": "integer", "description": "Target resource ID, building ID, or enemy unit ID" }
			},
			"required": ["player_id", "unit_ids", "action"]
		},
		_on_command_units
	)
	
	# 3. Train Unit
	MCPServer.register_function(
		"aoe_spawn_unit",
		"Queues the training of a unit (villager or soldier) inside a Town Center or Barracks.",
		{
			"type": "object",
			"properties": {
				"player_id": { "type": "integer", "description": "Owner ID (1 or 2)" },
				"building_id": { "type": "integer", "description": "The ID of the building to train the unit in" },
				"unit_type": { "type": "string", "enum": ["villager", "soldier"], "description": "Unit type to spawn" }
			},
			"required": ["player_id", "building_id", "unit_type"]
		},
		_on_spawn_unit
	)
	
	# 4. Place Building
	MCPServer.register_function(
		"aoe_place_building",
		"Spawns a building site (house/barracks) and commands a villager to build/construct it.",
		{
			"type": "object",
			"properties": {
				"player_id": { "type": "integer", "description": "Owner ID (1 or 2)" },
				"villager_id": { "type": "integer", "description": "The ID of the builder villager" },
				"building_type": { "type": "string", "enum": ["barracks", "house"], "description": "Building type" },
				"x": { "type": "number", "description": "X coordinate inside play area (0 to 800)" },
				"y": { "type": "number", "description": "Y coordinate inside play area (0 to 648)" }
			},
			"required": ["player_id", "villager_id", "building_type", "x", "y"]
		},
		_on_place_building
	)

# --- Tool Callback Handlers ---
func _on_get_game_state(args: Dictionary) -> Dictionary:
	var p_id = int(args.get("player_id", 1))
	if not players.has(p_id):
		return { "isError": true, "content": [{"type": "text", "text": "Invalid player_id: %d" % p_id}] }
		
	var players_data = []
	for id in players:
		players_data.append({
			"player_id": id,
			"name": players[id]["name"],
			"wood": players[id]["wood"],
			"gold": players[id]["gold"],
			"food": players[id]["food"],
			"pop": players[id]["pop"],
			"cap": players[id]["cap"]
		})
		
	var resources_data = []
	for res in resource_container.get_children():
		resources_data.append({
			"resource_id": res.resource_id,
			"type": res.resource_type,
			"amount": res.amount,
			"position": [res.position.x, res.position.y]
		})
		
	var buildings_data = []
	for bld in building_container.get_children():
		buildings_data.append({
			"building_id": bld.building_id,
			"owner_id": bld.owner_id,
			"type": bld.building_type,
			"health": bld.health,
			"max_health": bld.max_health,
			"under_construction": bld.is_under_construction,
			"position": [bld.position.x, bld.position.y],
			"spawn_queue": Array(bld.spawn_queue)
		})
		
	var units_data = []
	for unit in unit_container.get_children():
		units_data.append({
			"unit_id": unit.unit_id,
			"owner_id": unit.owner_id,
			"type": unit.unit_type,
			"health": unit.health,
			"max_health": unit.max_health,
			"state": unit.state,
			"cargo_amount": unit.cargo_amount,
			"cargo_type": unit.cargo_type,
			"position": [unit.position.x, unit.position.y]
		})
		
	var state = {
		"requesting_player_id": p_id,
		"players": players_data,
		"resources": resources_data,
		"buildings": buildings_data,
		"units": units_data
	}
	
	return {
		"isError": false,
		"content": [{"type": "text", "text": JSON.stringify(state, "  ")}]
	}

func _on_command_units(args: Dictionary) -> Dictionary:
	var player_id = int(args.get("player_id", 0))
	if player_id == 0:
		return { "isError": true, "content": [{"type": "text", "text": "Human player (0) cannot be controlled via AI MCP tool directly."}] }
		
	var unit_ids = args.get("unit_ids", [])
	var action = str(args.get("action", ""))
	
	var target_id = int(args.get("target_id", -1))
	var target_pos_arr = args.get("target_position", [400.0, 300.0])
	var target_pos = Vector2(target_pos_arr[0], target_pos_arr[1])
	
	# Execute deferred to comply with the thread safety rule
	call_deferred("_deferred_command_units", player_id, unit_ids, action, target_pos, target_id)
	
	return {
		"isError": false,
		"content": [{"type": "text", "text": "Command queued: Player %d's units %s set to %s." % [player_id, str(unit_ids), action]}]
	}

func _on_spawn_unit(args: Dictionary) -> Dictionary:
	var player_id = int(args.get("player_id", 0))
	if player_id == 0:
		return { "isError": true, "content": [{"type": "text", "text": "Human player (0) queueing is handled locally."}] }
		
	var building_id = int(args.get("building_id", -1))
	var unit_type = str(args.get("unit_type", ""))
	
	# Execute deferred to comply with the thread safety rule
	call_deferred("_deferred_spawn_unit", player_id, building_id, unit_type)
	
	return {
		"isError": false,
		"content": [{"type": "text", "text": "Spawn command queued: Player %d training %s in building %d." % [player_id, unit_type, building_id]}]
	}

func _on_place_building(args: Dictionary) -> Dictionary:
	var player_id = int(args.get("player_id", 0))
	if player_id == 0:
		return { "isError": true, "content": [{"type": "text", "text": "Human player (0) building placement is handled locally."}] }
		
	var villager_id = int(args.get("villager_id", -1))
	var building_type = str(args.get("building_type", ""))
	var tx = clampf(float(args.get("x", 400.0)), 24.0, play_area_width - 24.0)
	var ty = clampf(float(args.get("y", 300.0)), 24.0, screen_height - 24.0)
	var pos = Vector2(tx, ty)
	
	# Execute deferred to comply with the thread safety rule
	call_deferred("_deferred_place_building", player_id, villager_id, building_type, pos)
	
	return {
		"isError": false,
		"content": [{"type": "text", "text": "Construction command queued: Player %d placing %s at (%d, %d)." % [player_id, building_type, int(tx), int(ty)]}]
	}
