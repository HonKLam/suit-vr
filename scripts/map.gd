class_name Map
extends Node3D

signal fling_boost_active

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for stone in get_tree().get_nodes_in_group("stones"):
		if is_ancestor_of(stone):
			stone.both_hands_grabbed.connect(_on_both_hands_grabbed)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func on_climb_start(climbable: Node3D, hand: String) -> void:
	if not is_ancestor_of(climbable):
		return
	if climbable is Stone:
		climbable.on_grabbed(hand)

func _on_both_hands_grabbed(by: Stone) -> void:
	if by.fling_boost_allowed:
		fling_boost_active.emit()
