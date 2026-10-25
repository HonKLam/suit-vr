@tool
class_name GameSceneBase
extends XRToolsSceneBase

@onready var map: Map = $Map
@onready var player: Player = $XROrigin3D
@onready var movement_climb: XRToolsMovementClimb = $XROrigin3D/MovementClimb

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	map.fling_boost_active.connect(player.set_fling_boost.bind(1.5))
	map.fling_boost_inactive.connect(player.set_fling_boost.bind(1.0))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
