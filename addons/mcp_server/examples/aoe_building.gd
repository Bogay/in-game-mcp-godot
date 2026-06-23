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

func _ready() -> void:
	add_to_group("aoe_buildings")
	add_to_group("aoe_player_%d" % owner_id)
