class_name Player
extends XROrigin3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_fling_boost(val: float) -> void:
	$MovementClimb.fling_multiplier = val
