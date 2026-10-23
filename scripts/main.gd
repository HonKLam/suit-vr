extends Node3D

@onready var map: Map = $Map
@onready var player: Player = $Player
@onready var movement_climb: XRToolsMovementClimb = $Player/MovementClimb

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	player.wall_grabbed.connect(map.on_climb_start)
	map.fling_boost_active.connect(player.on_both_hands_stone_grabbed)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
