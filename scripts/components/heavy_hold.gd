class_name HeavyHold
extends Node
## Lässt ein gehaltenes XRToolsPickable schwer wirken: Statt der Hand sofort zu folgen,
## gleitet es gedämpft hinterher (Position und Drehung getrennt einstellbar).
## Einfach als Kind an das Pickable hängen. Wirkt nur, solange es gehalten wird.
##
## Technik: xr-tools setzt das Objekt jeden Physik-Frame auf die Handposition (Grab-Driver).
## Dieses Skript läuft danach (process_physics_priority) und ersetzt das durch einen
## geglätteten Übergang vom letzten Stand zur Handposition.
## Andere Komponenten (z.B. HoldGroundBlock) können den Stand über die Meta
## "held_transform" am Pickable korrigieren.

## Wie schnell die Position der Hand folgt (pro Sekunde). Kleiner = schwerer/träger.
@export_range(1.0, 40.0, 0.5) var position_follow := 9.0
## Wie schnell die Drehung der Hand folgt (pro Sekunde). Kleiner = schwerer/träger.
@export_range(1.0, 40.0, 0.5) var rotation_follow := 6.0
## Ab diesem Abstand (m) springt es sofort zur Hand (z.B. nach einem Teleport).
@export var snap_distance := 1.5

const META := "held_transform"

var _pickable: Node3D
var _state: Transform3D
var _active := false


func _ready() -> void:
	_pickable = get_parent() as Node3D
	process_physics_priority = 100 # nach dem xr-tools Grab-Driver
	if _pickable and _pickable.has_signal("picked_up"):
		_pickable.picked_up.connect(_on_picked_up)
		_pickable.dropped.connect(_on_dropped)


func _on_picked_up(_p) -> void:
	_state = _pickable.global_transform
	_pickable.set_meta(META, _state)
	_active = true


func _on_dropped(_p) -> void:
	_active = false
	_pickable.remove_meta(META)


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


# Wo die Hand das Objekt gerade hinsetzen will (Ziel des xr-tools Grab-Drivers).
func _hand_target() -> Transform3D:
	var driver = _pickable.get("_grab_driver")
	if driver is Node3D and is_instance_valid(driver):
		return driver.global_transform
	return _pickable.global_transform
