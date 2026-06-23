extends Node2D
class_name AoEResource

# Properties exposed to inspectors
var resource_id: int
var resource_type: String # "tree", "gold_mine", "berry_bush"
var amount: float
var max_amount: float

func _ready() -> void:
	add_to_group("aoe_resources")
