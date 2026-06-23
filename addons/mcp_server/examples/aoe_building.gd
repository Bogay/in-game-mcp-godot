extends Node2D
class_name AoEBuilding

# Properties exposed to inspectors
var building_id: int
var owner_id: int # 0=Human, 1=Agent 1, 2=Agent 2
var building_type: String # "town_center", "barracks", "house"
var health: float
var max_health: float
var is_under_construction: bool = false
var spawn_queue: Array[String] = []
var spawn_progress: float = 0.0

var p_color: Color = Color(0.8, 0.8, 0.8)

func _ready() -> void:
	add_to_group("aoe_buildings")
	add_to_group("aoe_player_%d" % owner_id)
	
	var main = get_tree().root.get_node_or_null("AoEDemoGame")
	if main and main.players.has(owner_id):
		p_color = main.players[owner_id]["color"]

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if building_type == "town_center":
		# TC Keep structure
		# Towers
		draw_rect(Rect2(Vector2(-32, -32), Vector2(16, 64)), Color(0.5, 0.5, 0.53), true) # Left
		draw_rect(Rect2(Vector2(16, -32), Vector2(16, 64)), Color(0.5, 0.5, 0.53), true) # Right
		# Main Castle Hall
		draw_rect(Rect2(Vector2(-16, -16), Vector2(32, 48)), Color(0.4, 0.4, 0.43), true)
		# Towers crenellations/borders
		draw_rect(Rect2(Vector2(-32, -32), Vector2(16, 64)), p_color, false, 2.0)
		draw_rect(Rect2(Vector2(16, -32), Vector2(16, 64)), p_color, false, 2.0)
		draw_rect(Rect2(Vector2(-16, -16), Vector2(32, 48)), p_color, false, 2.0)
		
		# Conical roofs
		_draw_polygon_node(Vector2(-24, -38), 10.0, 3, p_color)
		_draw_polygon_node(Vector2(24, -38), 10.0, 3, p_color)
		
		# Door
		draw_rect(Rect2(Vector2(-8, 16), Vector2(16, 16)), Color(0.3, 0.2, 0.1), true)
		# Flag pole & Owner Flag
		draw_line(Vector2(0, -16), Vector2(0, -42), Color(0.8, 0.8, 0.8), 2.0)
		var flag_points = PackedVector2Array([
			Vector2(0, -42),
			Vector2(12, -36),
			Vector2(0, -30)
		])
		draw_colored_polygon(flag_points, p_color)
		
	elif building_type == "barracks":
		var size = Vector2(48, 48)
		var rect = Rect2(-size / 2.0, size)
		# Main Hall (wood siding)
		draw_rect(rect, Color(0.55, 0.45, 0.35), true)
		draw_rect(rect, p_color, false, 2.5)
		# Pitched roof
		var roof_points = PackedVector2Array([
			Vector2(-24, -24),
			Vector2(0, -42),
			Vector2(24, -24)
		])
		draw_colored_polygon(roof_points, Color(0.35, 0.25, 0.15))
		draw_polyline(roof_points, p_color, 2.5)
		
		# Crossed swords on front wall
		draw_line(Vector2(-10, -6), Vector2(10, 14), Color(0.9, 0.9, 0.95), 2.0)
		draw_line(Vector2(10, -6), Vector2(-10, 14), Color(0.9, 0.9, 0.95), 2.0)
		draw_circle(Vector2(-8, -4), 2.5, Color(0.75, 0.55, 0.1))
		draw_circle(Vector2(8, -4), 2.5, Color(0.75, 0.55, 0.1))
		
	else: # House
		var size = Vector2(32, 32)
		var rect = Rect2(-size / 2.0, size)
		# Log Cabin base
		draw_rect(rect, Color(0.45, 0.3, 0.2), true)
		draw_rect(rect, p_color, false, 2.0)
		# Pitched roof in Player color
		var roof_points = PackedVector2Array([
			Vector2(-16, -16),
			Vector2(0, -30),
			Vector2(16, -16)
		])
		draw_colored_polygon(roof_points, p_color)
		# Cozy door & glowing window
		draw_rect(Rect2(Vector2(-4, 4), Vector2(8, 12)), Color(0.25, 0.18, 0.1), true)
		draw_rect(Rect2(Vector2(-10, -4), Vector2(6, 6)), Color(0.95, 0.95, 0.4), true)
		draw_rect(Rect2(Vector2(-10, -4), Vector2(6, 6)), Color(0.1, 0.1, 0.1), false, 1.0)
		
	# Construction/Spawning progress bar
	var bar_width = 64.0 if building_type == "town_center" else (48.0 if building_type == "barracks" else 32.0)
	if is_under_construction:
		var pct = health / max_health
		_draw_small_bar(Vector2(-bar_width/2, -bar_width/2 - 12), bar_width, pct, Color(0.8, 0.5, 0.1))
	elif not spawn_queue.is_empty():
		var needed = 4.0 if spawn_queue[0] == "villager" else 6.0
		var pct = spawn_progress / needed
		_draw_small_bar(Vector2(-bar_width/2, -bar_width/2 - 12), bar_width, pct, Color(0.1, 0.7, 0.9))
		
	# Health bar (if damaged or selected)
	var main = get_tree().root.get_node_or_null("AoEDemoGame")
	var is_selected = main and self in main.selected_entities
	if health < max_health and not is_under_construction or is_selected:
		_draw_small_bar(Vector2(-bar_width/2, bar_width/2 + 8), bar_width, health / max_health, Color(0.2, 0.9, 0.2))

func _draw_polygon_node(center: Vector2, radius: float, sides: int, color: Color) -> void:
	var points = PackedVector2Array()
	for i in range(sides):
		var angle = i * TAU / sides
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)
	draw_polyline(points, color.lightened(0.25), 1.5)

func _draw_small_bar(pos: Vector2, width: float, pct: float, color: Color) -> void:
	draw_rect(Rect2(pos, Vector2(width, 3)), Color(0.7, 0.1, 0.1), true)
	draw_rect(Rect2(pos, Vector2(width * pct, 3)), color, true)
