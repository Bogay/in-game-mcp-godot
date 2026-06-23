extends Node2D
class_name AoEResource

# Properties exposed to inspectors
var resource_id: int
var resource_type: String # "tree", "gold_mine", "berry_bush"
var amount: float
var max_amount: float

func _ready() -> void:
	add_to_group("aoe_resources")

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Draw centered at Vector2.ZERO
	if resource_type == "gold_mine":
		# Draw rocky grey outcrop
		_draw_polygon_node(Vector2.ZERO, 16.0, 5, Color(0.42, 0.42, 0.45))
		# Draw gold nuggets inside
		draw_rect(Rect2(Vector2(-8, -4), Vector2(5, 4)), Color(1.0, 0.8, 0.0), true)
		draw_rect(Rect2(Vector2(2, 2), Vector2(6, 4)), Color(1.0, 0.8, 0.0), true)
		draw_circle(Vector2(-2, 6), 3.0, Color(1.0, 0.8, 0.0))
		# Draw shiny sparkles
		draw_circle(Vector2(-6, -6), 1.5, Color(1.0, 1.0, 1.0))
		draw_circle(Vector2(4, -4), 1.5, Color(1.0, 1.0, 1.0))
		
	elif resource_type == "berry_bush":
		# Draw dense dark green bush circles
		draw_circle(Vector2(-6, 2), 9.0, Color(0.08, 0.35, 0.15))
		draw_circle(Vector2(6, 2), 9.0, Color(0.08, 0.35, 0.15))
		draw_circle(Vector2(0, -4), 10.0, Color(0.1, 0.4, 0.2))
		# Draw bright red berry dots
		draw_circle(Vector2(-5, -2), 3.0, Color(0.9, 0.1, 0.1))
		draw_circle(Vector2(5, -2), 3.5, Color(0.9, 0.1, 0.1))
		draw_circle(Vector2(0, 4), 3.0, Color(0.9, 0.1, 0.1))
		draw_circle(Vector2(-1, -8), 2.5, Color(0.9, 0.1, 0.1))
		
	else: # Tree
		# Draw brown trunk
		draw_rect(Rect2(Vector2(-3, 2), Vector2(6, 12)), Color(0.4, 0.25, 0.1), true)
		# Draw layered green canopy
		draw_circle(Vector2(0, -4), 10.0, Color(0.1, 0.45, 0.15))
		draw_circle(Vector2(0, -10), 8.0, Color(0.15, 0.55, 0.2))
		draw_circle(Vector2(-6, -2), 7.0, Color(0.08, 0.4, 0.12))
		draw_circle(Vector2(6, -2), 7.0, Color(0.08, 0.4, 0.12))
		
	# Quantity label
	var radius = 14.0 if resource_type == "gold_mine" else 10.0
	draw_string(ThemeDB.fallback_font, Vector2(-15, radius + 14), str(int(amount)), HORIZONTAL_ALIGNMENT_CENTER, 30, 9, Color(0.85, 0.85, 0.85))

func _draw_polygon_node(center: Vector2, radius: float, sides: int, color: Color) -> void:
	var points = PackedVector2Array()
	for i in range(sides):
		var angle = i * TAU / sides
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)
	draw_polyline(points, color.lightened(0.25), 1.5)
