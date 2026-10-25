@tool
class_name GameSceneBase
extends XRToolsSceneBase

@onready var map: Map = $Map
@onready var player: Player = $XROrigin3D
@onready var movement_climb: XRToolsMovementClimb = $XROrigin3D/MovementClimb

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	player.wall_grabbed.connect(map.on_climb_start)
	map.fling_boost_active.connect(player.on_both_hands_stone_grabbed)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
