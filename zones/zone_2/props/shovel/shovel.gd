@tool
class_name Shovel
extends XRToolsPickable

## Two-handed shovel (top handle + shaft). Digging only with both hands.
## 0. Aim: StabMarker shows where the blade will go in (straight along the blade).
## 1. Stab: push both hands along the shaft into a Sandbox -> blade lands on the marker,
##    sinks in (faster = deeper) and sticks.
## 2. Pull: hands up along the shaft -> growing vibration + PullRing, then pops out and digs.
##    Deeper = bigger hole, longer pull.

## strength: 0..1 (push speed of the hands)
signal stabbed(strength: float, at: Vector3)
## radius: hole size (m)
signal scooped(at: Vector3, radius: float)

## Push speed of the hands along the shaft (m/s): weakest / strongest stab
const MIN_SPEED: float = 0.6
const MAX_SPEED: float = 2.0

const MIN_RADIUS: float = 0.06
const MAX_RADIUS: float = 0.15

## Stab depth (m), weakest / strongest stab
const MIN_DEPTH: float = 0.05
const MAX_DEPTH: float = 0.38

## Max angle hand movement vs. blade (more = sideways swipe)
const MAX_STAB_ANGLE: float = 50.0
## Max angle blade vs. straight down
const MAX_TILT_ANGLE: float = 70.0

## Hand speed is measured over this time (s): smooths shaky hands
const MOTION_WINDOW: float = 0.1

## Pull distance to pop out (m) = BASE + PER_DEPTH * stuck depth
const PULL_DISTANCE_BASE: float = 0.12
const PULL_DISTANCE_PER_DEPTH: float = 0.6

## Vibration (both hands)
const STAB_VIBRATION_STRENGTH: float = 0.6
const STAB_VIBRATION_TIME: float = 0.08
## x = pull start, y = just before popping out
const PULL_VIBRATION_STRENGTH := Vector2(0.1, 0.8)
const PULL_VIBRATION_INTERVAL := Vector2(0.3, 0.06)
const PULL_VIBRATION_TIME: float = 0.05
const POP_VIBRATION_STRENGTH: float = 1.0
const POP_VIBRATION_TIME: float = 0.15
## Glide back into the hands after popping out (s)
const POP_RETURN_TIME: float = 0.1

## How far ahead of the tip the stab point is searched (m)
const STAB_TARGET_RANGE: float = 0.6

## 0..1, read by PullRing
var pull_progress: float = 0.0
## Earth surface straight ahead of the blade, read by StabMarker
var has_stab_target: bool = false
var stab_target: Vector3 = Vector3.ZERO

var _recent_hand_positions: Array[Vector3] = [] # center between both hands
var _stuck_in_sandbox: Sandbox
var _stuck_transform: Transform3D
var _stuck_depth: float = 0.0
var _hands_lowest_point: float = INF # along the shaft, since pull start
var _time_to_next_pull_vibration: float = 0.0


## xr-tools has no getter for the second hand -> reads the grab driver
func is_two_handed() -> bool:
	return _grab_driver != null and is_instance_valid(_grab_driver.secondary)


func is_stuck() -> bool:
	return _stuck_in_sandbox != null


func get_hands_center() -> Vector3:
	return (_grab_driver.primary.by.global_position + _grab_driver.secondary.by.global_position) * 0.5


## Comes out of the ground without digging (e.g. when it goes back into the tool menu).
func unstick() -> void:
	_stuck_in_sandbox = null
	pull_progress = 0.0


func pick_up(by: Node3D) -> void:
	super(by)
	if not by is XRToolsFunctionPickup:
		return
	_ignore_player_body(by)
	# full fist while holding, also without pressing grip/trigger
	var hand := XRToolsHand.find_instance(by)
	if hand and is_picked_up():
		hand.force_grip_trigger(1.0, 1.0)
	if is_stuck() and _grab_driver:
		_keep_in_ground()
		global_transform = _stuck_transform


func let_go(by: Node3D, p_linear_velocity: Vector3, p_angular_velocity: Vector3) -> void:
	super(by, p_linear_velocity, p_angular_velocity)
	if by is XRToolsFunctionPickup:
		var hand := XRToolsHand.find_instance(by)
		if hand:
			hand.force_grip_trigger(-1.0, -1.0) # back to the controller buttons
	if is_stuck() and not is_picked_up():
		# stay in the ground
		freeze = true
		global_transform = _stuck_transform


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if is_stuck():
		_update_pull(delta)
		return

	_update_stab_target()

	if not is_two_handed():
		_recent_hand_positions.clear()
		return

	# Both hands together give the push (the rear hand pushes, the front one guides),
	# so measure the center between them instead of the blade tip (which swings like a lever).
	var hands_center: Vector3 = get_hands_center()
	_recent_hand_positions.push_back(hands_center)

	while _recent_hand_positions.size() > maxi(2, roundi(MOTION_WINDOW / delta) + 1):
		_recent_hand_positions.pop_front()

	if _recent_hand_positions.size() < 2:
		return

	var hands_velocity: Vector3 = (hands_center - _recent_hand_positions[0]) / (delta * (_recent_hand_positions.size() - 1))
	var blade_direction: Vector3 = -global_basis.y
	var push_speed: float = hands_velocity.dot(blade_direction)

	if push_speed < MIN_SPEED:
		return

	if hands_velocity.angle_to(blade_direction) > deg_to_rad(MAX_STAB_ANGLE) or blade_direction.angle_to(Vector3.DOWN) > deg_to_rad(MAX_TILT_ANGLE):
		return

	# a bit in front of the tip: counts as soon as the blade touches the earth
	var sandbox: Sandbox = _sandbox_at(global_position + blade_direction * MIN_DEPTH * 0.5)
	if sandbox == null:
		return

	var stab_strength: float = clampf(inverse_lerp(MIN_SPEED, MAX_SPEED, push_speed), 0.0, 1.0)
	_stick_into_ground(sandbox, stab_strength)


func _stick_into_ground(sandbox: Sandbox, stab_strength: float) -> void:
	_stuck_in_sandbox = sandbox
	_stuck_depth = lerpf(MIN_DEPTH, MAX_DEPTH, stab_strength)
	_keep_in_ground()
	if has_stab_target:
		global_position = stab_target
	global_position += -global_basis.y * _stuck_depth
	_stuck_transform = global_transform

	_vibrate_both_hands(STAB_VIBRATION_STRENGTH * lerpf(0.3, 1.0, stab_strength), STAB_VIBRATION_TIME)
	stabbed.emit(stab_strength, global_position)


## Driver keeps following the hands but no longer moves the shovel -> hands can pull away
func _keep_in_ground() -> void:
	_grab_driver.remote_path = NodePath()
	_hands_lowest_point = INF
	pull_progress = 0.0


## Starts over when a hand lets go
func _update_pull(delta: float) -> void:
	if not is_two_handed():
		_hands_lowest_point = INF
		pull_progress = 0.0
		return

	var shaft_up: Vector3 = _stuck_transform.basis.y.normalized()
	var hands_height: float = get_hands_center().dot(shaft_up)
	_hands_lowest_point = minf(_hands_lowest_point, hands_height)

	var pull_distance_needed: float = PULL_DISTANCE_BASE + PULL_DISTANCE_PER_DEPTH * _stuck_depth
	pull_progress = clampf((hands_height - _hands_lowest_point) / pull_distance_needed, 0.0, 1.0)

	if pull_progress >= 1.0:
		_pop_out()
		return

	_time_to_next_pull_vibration -= delta
	if pull_progress > 0.05 and _time_to_next_pull_vibration <= 0.0:
		_time_to_next_pull_vibration = lerpf(PULL_VIBRATION_INTERVAL.x, PULL_VIBRATION_INTERVAL.y, pull_progress)
		_vibrate_both_hands(lerpf(PULL_VIBRATION_STRENGTH.x, PULL_VIBRATION_STRENGTH.y, pull_progress), PULL_VIBRATION_TIME)


func _pop_out() -> void:
	var depth_factor: float = inverse_lerp(MIN_DEPTH, MAX_DEPTH, _stuck_depth)
	var hole_radius: float = lerpf(MIN_RADIUS, MAX_RADIUS, depth_factor)
	# spheres from the tip up to the surface, so a deep stab gives a deep hole, not a cave
	var shaft_up: Vector3 = global_basis.y.normalized()
	var removed_volume: float = 0.0
	var distance_from_tip: float = hole_radius
	while true:
		removed_volume += _stuck_in_sandbox.dig_at(global_position + shaft_up * distance_from_tip, hole_radius)
		if distance_from_tip >= _stuck_depth:
			break
		distance_from_tip = minf(distance_from_tip + hole_radius, _stuck_depth)
	if removed_volume > 0.0:
		scooped.emit(global_position + shaft_up * _stuck_depth * 0.5, hole_radius)

	_stuck_in_sandbox = null
	pull_progress = 0.0
	_recent_hand_positions.clear()
	_vibrate_both_hands(POP_VIBRATION_STRENGTH, POP_VIBRATION_TIME)

	# hand the shovel back to the driver, glide instead of jump
	_grab_driver.lerp_start = global_transform
	_grab_driver.lerp_time = 0.0
	_grab_driver.lerp_duration = POP_RETURN_TIME
	_grab_driver.state = XRToolsGrabDriver.GrabState.LERP
	_grab_driver.global_transform = global_transform
	_grab_driver.remote_path = _grab_driver.get_path_to(self)


## Earth surface straight ahead of the blade (ray onto the Sandbox ground).
func _update_stab_target() -> void:
	has_stab_target = false
	if not is_two_handed():
		return
	var tip: Vector3 = global_position
	if _sandbox_at(tip) != null:
		# tip already in the earth
		has_stab_target = true
		stab_target = tip
		return
	var ray := PhysicsRayQueryParameters3D.create(tip, tip - global_basis.y * STAB_TARGET_RANGE)
	ray.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit and hit.collider.get_parent() is Sandbox:
		has_stab_target = true
		stab_target = hit.position


## Never collide with the player: a stuck shovel the player stands over would push them away.
func _ignore_player_body(hand: Node3D) -> void:
	var player_body := XRToolsPlayerBody.find_instance(hand)
	if player_body and not get_collision_exceptions().has(player_body):
		add_collision_exception_with(player_body)
		player_body.add_collision_exception_with(self)


func _vibrate_both_hands(strength: float, duration: float) -> void:
	Haptics.pulse(_grab_driver.primary.controller, strength, duration)
	Haptics.pulse(_grab_driver.secondary.controller, strength, duration)


func _sandbox_at(pos: Vector3) -> Sandbox:
	for sandbox: Sandbox in get_tree().get_nodes_in_group("diggable"):
		if sandbox.is_solid(pos):
			return sandbox
	return null
