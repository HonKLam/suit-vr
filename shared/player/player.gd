class_name Player
extends XROrigin3D

const MENU_DISTANCE := 0.6
const MENU_SIZE := Vector2(0.4, 0.4)

## Off: the screen on the wrist is hidden, it only shows up as the opened menu.
@export var show_wrist_screen: bool = true

@onready var _screen: XRToolsViewport2DIn3D = $XRController3D_left/WristMenu
@onready var _pointer: XRToolsFunctionPointer = $XRController3D_right/FunctionPointer
@onready var _wrist_transform: Transform3D = _screen.transform
@onready var _wrist_size: Vector2 = _screen.screen_size

func _ready() -> void:
	_screen.visible = show_wrist_screen

func set_fling_boost(val: float) -> void:
	$MovementClimb.fling_multiplier = val

## Open: the wrist screen floats in front of the head and the right hand gets a laser to click it.
func set_menu_open(open: bool) -> void:
	_pointer.enabled = open
	_pointer.visible = open
	_screen.top_level = open
	_screen.visible = open or show_wrist_screen
	if open:
		var head: Transform3D = $XRCamera3D.global_transform
		_screen.screen_size = MENU_SIZE
		_screen.global_transform = head.translated_local(Vector3.FORWARD * MENU_DISTANCE)
	else:
		_screen.screen_size = _wrist_size
		_screen.transform = _wrist_transform

## Frozen: no movement and no new grabs. Hands that already hold on keep holding.
func set_frozen(frozen: bool) -> void:
	$PlayerBody.enabled = not frozen
	$XRController3D_left/FunctionPickup.enabled = not frozen
	$XRController3D_right/FunctionPickup.enabled = not frozen
