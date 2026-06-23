extends Node2D
class_name AoEUnit

# Properties exposed to inspectors (inspect_node)
var unit_id: int
var owner_id: int # 0=Human, 1=Agent 1, 2=Agent 2
var unit_type: String # "villager", "soldier"
var health: float
var max_health: float
var state: String = "idle" # "idle", "moving", "gathering", "returning", "attacking", "building"

var target_position: Vector2
var target_entity_id: int = -1 # ID of target resource, building, or enemy

# Resource gathering cargo
var cargo_type: String = "none" # "wood", "gold", "food", "none"
var cargo_amount: float = 0.0
var max_cargo: float = 10.0

var p_color: Color = Color(0.8, 0.8, 0.8)

func _ready() -> void:
	add_to_group("aoe_units")
	add_to_group("aoe_player_%d" % owner_id)
	
	var main = get_tree().root.get_node_or_null("AoEDemoGame")
	if main and main.players.has(owner_id):
		p_color = main.players[owner_id]["color"]

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var radius = 7.5 if unit_type == "villager" else 9.5
	
	# Draw Unit Selection ring
	var main = get_tree().root.get_node_or_null("AoEDemoGame")
	var is_selected = main and self in main.selected_entities
	if is_selected:
		draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.85), 1.5)
		
	# Draw Unit Body
	draw_circle(Vector2.ZERO, radius, p_color)
	
	# Class customizations
	if unit_type == "villager":
		# Black outline
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 12, Color(0.1, 0.1, 0.1), 1.2)
		# Straw Hat (yellow dome & brim)
		draw_circle(Vector2(0, -3), 5.5, Color(0.85, 0.75, 0.4))
		draw_line(Vector2(-6, -2), Vector2(6, -2), Color(0.7, 0.6, 0.3), 1.5)
		
		# Tool based on task state
		var tool_color = Color(0.75, 0.75, 0.8)
		if state == "gathering":
			if cargo_type == "wood": # Axe
				draw_line(Vector2(4, 2), Vector2(10, -4), Color(0.4, 0.25, 0.1), 1.5)
				draw_rect(Rect2(Vector2(8, -6), Vector2(3, 3)), tool_color, true)
			elif cargo_type == "gold": # Pickaxe
				draw_line(Vector2(4, 2), Vector2(10, -4), Color(0.4, 0.25, 0.1), 1.5)
				draw_arc(Vector2(10, -4), 4.0, -PI/2, PI/2, 8, tool_color, 1.5)
			elif cargo_type == "food": # Sickle
				draw_line(Vector2(4, 2), Vector2(8, -2), Color(0.4, 0.25, 0.1), 1.5)
				draw_arc(Vector2(8, -2), 3.0, 0, PI, 8, tool_color, 1.5)
		elif state == "building": # Hammer
			draw_line(Vector2(4, 2), Vector2(10, -4), Color(0.4, 0.25, 0.1), 1.5)
			draw_rect(Rect2(Vector2(8, -7), Vector2(4, 3)), Color(0.35, 0.35, 0.38), true)
			
	else: # Soldier
		# Iron Helmet
		draw_circle(Vector2(0, -3), 6.5, Color(0.7, 0.7, 0.75))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 12, Color(0.2, 0.2, 0.2), 1.2)
		# Helmet Plume matching owner color
		draw_circle(Vector2(0, -8), 2.5, p_color)
		
		# Shield on left side
		draw_circle(Vector2(-7, 2), 5.0, Color(0.7, 0.7, 0.75))
		draw_circle(Vector2(-7, 2), 3.0, p_color)
		
		# Sword pointing right
		var sword_pos = Vector2(6, 2)
		var sword_target = Vector2(14, -4)
		if state == "attacking":
			sword_target = Vector2(16, 4) # swing down
		draw_line(sword_pos, sword_target, Color(0.9, 0.9, 0.95), 2.0)
		# Crossguard
		var dir = (sword_target - sword_pos).normalized()
		var perp = Vector2(-dir.y, dir.x)
		draw_line(sword_pos + dir * 2.0 - perp * 3.0, sword_pos + dir * 2.0 + perp * 3.0, Color(0.7, 0.5, 0.1), 1.5)
		
	# Display cargo count for gathering villagers
	if unit_type == "villager" and cargo_amount > 0:
		var label = "%d" % int(cargo_amount)
		draw_string(ThemeDB.fallback_font, Vector2(-10, -radius - 5), label, HORIZONTAL_ALIGNMENT_CENTER, 20, 8, Color(0.95, 0.85, 0.3))
		
	# Combat flash lines
	if has_meta("attack_flash_t"):
		var flash_t = get_meta("attack_flash_t")
		if flash_t > 0:
			var flash_pos = get_meta("attack_flash_pos")
			var local_flash = to_local(flash_pos)
			draw_line(Vector2.ZERO, local_flash, Color(1.0, 0.8, 0.2, flash_t / 0.15), 2.0)
			set_meta("attack_flash_t", flash_t - get_process_delta_time())
			
	# Health bar (if damaged or selected)
	if health < max_health or is_selected:
		_draw_small_bar(Vector2(-10, radius + 6), 20.0, health / max_health, Color(0.2, 0.9, 0.2))

func _draw_small_bar(pos: Vector2, width: float, pct: float, color: Color) -> void:
	draw_rect(Rect2(pos, Vector2(width, 3)), Color(0.7, 0.1, 0.1), true)
	draw_rect(Rect2(pos, Vector2(width * pct, 3)), color, true)
