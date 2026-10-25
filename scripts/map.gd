class_name Map
extends Node3D

signal fling_boost_active
signal fling_boost_inactive

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for stone: Stone in get_tree().get_nodes_in_group("stones"):
		if is_ancestor_of(stone):
			stone.one_hand_grabbed.connect(_on_one_hand_grabbed)
			stone.both_hands_grabbed.connect(_on_both_hands_grabbed)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_one_hand_grabbed(by: Stone) -> void:
	fling_boost_inactive.emit()

func _on_both_hands_grabbed(by: Stone) -> void:
	if by.fling_boost_allowed:
		fling_boost_active.emit()
