class_name HeavyHold
extends Node
## Makes a held XRToolsPickable feel heavy: instead of following the hand right away,
## it glides behind with damping (position and rotation can be tuned separately).
## Add as a child of the pickable. Only active while it is held.
##
## How it works: xr-tools moves the object to the hand every physics frame (grab driver).
## This script runs afterwards (process_physics_priority) and replaces that with a
## smoothed move from the last state to the hand position.
## Other components (e.g. HoldGroundBlock) can correct the state through the meta
## "held_transform" on the pickable.
##
## Hand stays on the grip: while held, the visible xr-tools hand is put on the grab point
## every frame (after the object moved). Otherwise hand and grip drift apart because of the inertia.

## How fast the position follows the hand (per second). Lower = heavier.
@export_range(1.0, 40.0, 0.5) var position_follow := 18.0
## How fast the rotation follows the hand (per second). Lower = heavier.
@export_range(1.0, 40.0, 0.5) var rotation_follow := 12.0
## From this distance (m) on it jumps to the hand right away (e.g. after a teleport).
@export var snap_distance := 1.5
## The visible hand sticks to the grip (follows the heavy object).
@export var glue_hand := true

const META := "held_transform"

var _pickable: Node3D
var _state: Transform3D
var _active := false
var _glued_hand: XRToolsHand


func _ready() -> void:
	_pickable = get_parent() as Node3D
	process_physics_priority = 100 # after the xr-tools grab driver
	process_priority = 100 # glue the hand after the controllers moved
	if _pickable and _pickable.has_signal("picked_up"):
		_pickable.picked_up.connect(_on_picked_up)
		_pickable.dropped.connect(_on_dropped)


func _on_picked_up(_p) -> void:
	_state = _pickable.global_transform
	_pickable.set_meta(META, _state)
	_active = true
	if glue_hand:
		_glued_hand = XRToolsHand.find_instance(_controller())


func _on_dropped(_p) -> void:
	_active = false
	_pickable.remove_meta(META)
	_glued_hand = null


func _physics_process(delta: float) -> void:
	if not _active:
		return
	var target := _hand_target()
	if _pickable.has_meta(META):
		_state = _pickable.get_meta(META)
	if _state.origin.distance_to(target.origin) > snap_distance:
		_state = target
	else:
		var tp := 1.0 - exp(-position_follow * delta)
		var tr := 1.0 - exp(-rotation_follow * delta)
		var q := _state.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), tr)
		_state = Transform3D(Basis(q).scaled(target.basis.get_scale()), _state.origin.lerp(target.origin, tp))
	_pickable.global_transform = _state
	_pickable.set_meta(META, _state)
	_put_hand_on_grip()


func _process(_delta: float) -> void:
	if _active:
		_put_hand_on_grip()


## Same placement as xr-tools uses for a snapped hand, but on the (slow) object.
func _put_hand_on_grip() -> void:
	if not is_instance_valid(_glued_hand):
		return
	var grab_point := _pickable.get_active_grab_point() as XRToolsGrabPointHand
	if grab_point:
		_glued_hand.global_transform = grab_point.get_palm_transform(true) * _glued_hand._transform


func _controller() -> Node3D:
	if _pickable.has_method("get_picked_up_by_controller"):
		return _pickable.get_picked_up_by_controller()
	return null


# Where the hand wants to put the object right now (target of the xr-tools grab driver).
func _hand_target() -> Transform3D:
	var driver = _pickable.get("_grab_driver")
	if driver is Node3D and is_instance_valid(driver):
		return driver.global_transform
	return _pickable.global_transform
