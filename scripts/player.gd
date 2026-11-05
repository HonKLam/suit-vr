class_name Player
extends XROrigin3D

func set_fling_boost(val: float) -> void:
	$MovementClimb.fling_multiplier = val

## Frozen: no movement and no new grabs. Hands that already hold on keep holding.
func set_frozen(frozen: bool) -> void:
	$PlayerBody.enabled = not frozen
	$XRController3D_left/FunctionPickup.enabled = not frozen
	$XRController3D_right/FunctionPickup.enabled = not frozen
