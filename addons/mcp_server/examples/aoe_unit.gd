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

func _ready() -> void:
	add_to_group("aoe_units")
	add_to_group("aoe_player_%d" % owner_id)
