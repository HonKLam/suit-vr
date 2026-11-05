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
## Hand stays on the grip: while held, the visible hand/controller model
## (MeshInstance3D children of the controller) follows the object instead of the real controller.
## Otherwise hand and grip would drift apart because of the inertia.

## How fast the position follows the hand (per second). Lower = heavier.
@export_range(1.0, 40.0, 0.5) var position_follow := 9.0
## How fast the rotation follows the hand (per second). Lower = heavier.
@export_range(1.0, 40.0, 0.5) var rotation_follow := 6.0
## From this distance (m) on it jumps to the hand right away (e.g. after a teleport).
@export var snap_distance := 1.5
## The visible hand sticks to the grip (follows the heavy object).
@export var glue_hand := true

const META := "held_transform"

var _pickable: Node3D
var _state: Transform3D
var _active := false
var _hand_offset := Transform3D() # hand relative to the object
var _visuals: Array[Node3D] = []
var _visual_saved := {} # Node3D -> [transform, top_level]


func _ready() -> void:
	_pickable = get_parent() as Node3D
	process_physics_priority = 100 # after the xr-tools grab driver
	if _pickable and _pickable.has_signal("picked_up"):
		_pickable.picked_up.connect(_on_picked_up)
		_pickable.dropped.connect(_on_dropped)


func _on_picked_up(_p) -> void:
	_state = _pickable.global_transform
	_pickable.set_meta(META, _state)
	_active = true
	if glue_hand:
		_attach_hand_visuals()


func _on_dropped(_p) -> void:
	_active = false
	_pickable.remove_meta(META)
	_release_hand_visuals()


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
	# Where the hand sits relative to the object (without inertia, object == target)
	var ctrl := _controller()
	if ctrl:
		_hand_offset = target.affine_inverse() * ctrl.global_transform


func _process(_delta: float) -> void:
	if not _active or _visuals.is_empty():
		return
	# The hand always sits on the (slow) object, so it stays on the grip
	var t := _pickable.global_transform * _hand_offset
	for v in _visuals:
		if is_instance_valid(v):
			v.global_transform = t * _visual_saved[v][0]


func _controller() -> Node3D:
	if _pickable.has_method("get_picked_up_by_controller"):
		return _pickable.get_picked_up_by_controller()
	return null


func _attach_hand_visuals() -> void:
	_release_hand_visuals()
	var ctrl := _controller()
	if ctrl == null:
		return
	for c in ctrl.get_children():
		if c is MeshInstance3D:
			var v := c as Node3D
			_visual_saved[v] = [v.transform, v.top_level]
			v.top_level = true # move independently of the real controller
			_visuals.append(v)
	_hand_offset = _hand_target().affine_inverse() * ctrl.global_transform


func _release_hand_visuals() -> void:
	for v in _visuals:
		if is_instance_valid(v):
			v.top_level = _visual_saved[v][1]
			v.transform = _visual_saved[v][0]
	_visuals.clear()
	_visual_saved.clear()

# Where the hand wants to put the object right now (target of the xr-tools grab driver).
func _hand_target() -> Transform3D:
	var driver = _pickable.get("_grab_driver")
	if driver is Node3D and is_instance_valid(driver):
		return driver.global_transform
	return _pickable.global_transform
