@tool
class_name Shovel
extends XRToolsPickable

## Shovel that is held with two hands: top handle + shaft.
## One hand can carry it, digging only works while both hands hold it.
## Digging takes two steps:
## 1. Stab: the blade tip (the shovel origin) hits the earth of a Sandbox (group "diggable")
##    fast enough, along the blade and pointing down. Both hands vibrate, nothing is dug yet.
## 2. Lift: once the tip is LIFT_HEIGHT above its lowest point since the stab, a sphere is
##    removed where the stab hit. Faster and straighter stab = bigger hole.
## Letting go with a hand in between cancels the stab.

const MIN_SPEED: float = 0.7
const MAX_SPEED: float = 3.0

const MIN_RADIUS: float = 0.06
const MAX_RADIUS: float = 0.15

## Max angle between the movement and the blade. More = a sideways swipe, no stab.
const MAX_STAB_ANGLE: float = 50.0
## Max angle between the blade and straight down.
const MAX_TILT_ANGLE: float = 70.0

## Speed and direction are measured over this time (s) instead of one frame:
## smooths out shaky hands, and a stroke that slows down on impact still counts.
const MOTION_WINDOW: float = 0.1
const LIFT_HEIGHT: float = 0.1

## Vibration on a stab at the biggest hole, in both hands (0 = off).
const HAPTIC_STRENGTH: float = 0.6
const HAPTIC_TIME: float = 0.08

var _tips: Array[Vector3] = [] # tip positions of the last MOTION_WINDOW
var _stab_sandbox: Sandbox # set by a stab, cleared by the lift
var _stab_center: Vector3 = Vector3.ZERO
var _stab_radius: float = 0.0
var _stab_lowest: float = 0.0 # lowest tip height since the stab


## true while both hands hold the shovel.
## xr-tools has no public getter for the second hand, so this reads the grab driver directly.
func is_two_handed() -> bool:
	return _grab_driver != null and is_instance_valid(_grab_driver.secondary)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var tip: Vector3 = global_position
	_tips.push_back(tip)

	while _tips.size() > maxi(2, roundi(MOTION_WINDOW / delta) + 1):
		_tips.pop_front()

	if not is_two_handed():
		_stab_sandbox = null
		return

	if _stab_sandbox:
		_stab_lowest = minf(_stab_lowest, tip.y)
		if tip.y > _stab_lowest + LIFT_HEIGHT:
			_stab_sandbox.dig_at(_stab_center, _stab_radius)
			_stab_sandbox = null
		return

	if _tips.size() < 2:
		return

	var velocity: Vector3 = (tip - _tips[0]) / (delta * (_tips.size() - 1))
	var speed: float = velocity.length()
	
	if speed < MIN_SPEED:
		return

	var blade: Vector3 = -global_basis.y
	var stab: float = velocity.angle_to(blade)
	
	if stab > deg_to_rad(MAX_STAB_ANGLE) or blade.angle_to(Vector3.DOWN) > deg_to_rad(MAX_TILT_ANGLE):
		return

	var t: float = clampf(inverse_lerp(MIN_SPEED, MAX_SPEED, speed), 0.0, 1.0) * (1.0 - stab / deg_to_rad(MAX_STAB_ANGLE))
	var radius: float = lerpf(MIN_RADIUS, MAX_RADIUS, t)
	
	# Checked at the hole center (a bit in front of the tip), so it counts as soon as the blade touches the earth.
	var center: Vector3 = tip + blade * radius * 0.5
	var sandbox: Sandbox = _sandbox_at(center)
	if sandbox == null:
		return

	_stab_sandbox = sandbox
	_stab_center = center
	_stab_radius = radius
	_stab_lowest = tip.y

	var strength: float = HAPTIC_STRENGTH * lerpf(0.3, 1.0, t)
	Haptics.pulse(_grab_driver.primary.controller, strength, HAPTIC_TIME)
	Haptics.pulse(_grab_driver.secondary.controller, strength, HAPTIC_TIME)


func _sandbox_at(pos: Vector3) -> Sandbox:
	for s: Sandbox in get_tree().get_nodes_in_group("diggable"):
		if s.is_solid(pos):
			return s
	return null
