class_name Player
extends XROrigin3D

signal wall_grabbed(climbable: Node3D, hand: String)

@onready var left_pickup = $XRController3D_left/FunctionPickup
@onready var right_pickup = $XRController3D_right/FunctionPickup

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	left_pickup.has_picked_up.connect(func(what): _on_grabbed(what, "left"))
	right_pickup.has_picked_up.connect(func(what): _on_grabbed(what, "right"))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_grabbed(what: Node3D, hand: String):
	if what is XRToolsClimbable:
		wall_grabbed.emit(what, hand)	

func on_both_hands_stone_grabbed() -> void:
	$MovementClimb.fling_multiplier = 1.5
