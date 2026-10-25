@tool
class_name Map
extends Node3D

signal fling_boost_active
signal fling_boost_inactive
signal player_fell
signal player_won

@onready var lava: Lava = get_node_or_null("Lava")
@onready var win_area: Win = get_node_or_null("WinArea")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for stone: Stone in get_tree().get_nodes_in_group("stones"):
		if is_ancestor_of(stone):
			stone.one_hand_grabbed.connect(_on_one_hand_grabbed)
			stone.both_hands_grabbed.connect(_on_both_hands_grabbed)
	lava.player_fell.connect(_on_player_fell)
	win_area.player_win.connect(_on_player_win)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not get_node_or_null("Lava"):
		warnings.append("Missing child \"Lava\" (scenes/map/lava.tscn).")
	if not get_node_or_null("WinArea"):
		warnings.append("Missing child \"WinArea\" (scenes/map/win.tscn).")
	return warnings

func _on_one_hand_grabbed(by: Stone) -> void:
	fling_boost_inactive.emit()

func _on_both_hands_grabbed(by: Stone) -> void:
	if by.fling_boost_allowed:
		fling_boost_active.emit()

func _on_player_fell() -> void:
	player_fell.emit()

func _on_player_win() -> void:
	player_won.emit()
