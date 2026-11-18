class_name ToolBelt
extends Node3D
## Belt that travels with the player and holds the tools of zone 2:
## shovel (right), metal detector (left), flags (front).
## - Shovel and detector fly back to the belt shortly after they are let go.
## - Flags: take one from the pouch and a new one appears.

@export var shovel: XRToolsPickable
@export var metal_detector: XRToolsPickable
@export var flag_scene: PackedScene

## How fast the belt turns with the head (per second)
const TURN_SPEED: float = 4.0
## Below this the head looks too far up/down to tell where forward is
const MIN_FORWARD_LENGTH: float = 0.3
## Time until a let go tool flies back (s)
const RETURN_DELAY: float = 0.4
## Time until a new flag appears in the pouch (s)
const NEW_FLAG_DELAY: float = 0.3

var _yaw: float = 0.0

@onready var _shovel_slot: XRToolsSnapZone = $ShovelSlot
@onready var _detector_slot: XRToolsSnapZone = $DetectorSlot
@onready var _flag_slot: XRToolsSnapZone = $FlagSlot


func _ready() -> void:
	process_physics_priority = -100 # move before the xr-tools grab drivers carry the tools along
	for slot: XRToolsSnapZone in [_shovel_slot, _detector_slot, _flag_slot]:
		slot.add_to_group("tool_belt") # matches the XRToolsGrabPointSnap of the tools
	_stow(shovel, _shovel_slot, "belt_shovel")
	_stow(metal_detector, _detector_slot, "belt_detector")
	_flag_slot.snap_require = "belt_flag"
	_flag_slot.has_dropped.connect(_on_flag_taken)
	_put_new_flag.call_deferred() # the level is still adding its children right now


func _physics_process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var head := camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	if forward.length() > MIN_FORWARD_LENGTH:
		_yaw = lerp_angle(_yaw, atan2(-forward.x, -forward.z), 1.0 - exp(-TURN_SPEED * delta))
	var floor_height: float = camera.get_parent().global_position.y if camera.get_parent() is Node3D else 0.0
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), Vector3(head.origin.x, floor_height, head.origin.z))


## Puts the tool in its slot and makes it come back there after being let go.
func _stow(tool: XRToolsPickable, slot: XRToolsSnapZone, group: String) -> void:
	if tool == null:
		return
	tool.add_to_group(group)
	slot.snap_require = group
	var return_to_belt := XRToolsReturnToSnapZone.new()
	return_to_belt.name = "ReturnToBelt"
	return_to_belt.return_delay = RETURN_DELAY
	tool.add_child(return_to_belt)
	return_to_belt.set_snap_zone(slot)
	slot.pick_up_object(tool)


func _on_flag_taken() -> void:
	get_tree().create_timer(NEW_FLAG_DELAY).timeout.connect(_put_new_flag)


func _put_new_flag() -> void:
	if flag_scene == null or _flag_slot.has_snapped_object():
		return
	var flag: XRToolsPickable = flag_scene.instantiate()
	flag.add_to_group("belt_flag")
	get_parent().add_child(flag)
	flag.global_transform = _flag_slot.global_transform
	_flag_slot.pick_up_object(flag)
