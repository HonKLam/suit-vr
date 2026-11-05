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
##
## Hand bleibt am Griff: Solange gehalten wird, folgt das sichtbare Hand-/Controller-Modell
## (Kinder des Controllers, z.B. MeshInstance3D) dem Objekt statt dem echten Controller.
## Sonst würden Hand und Griff durch die Trägheit auseinanderlaufen.

## Wie schnell die Position der Hand folgt (pro Sekunde). Kleiner = schwerer/träger.
@export_range(1.0, 40.0, 0.5) var position_follow := 9.0
## Wie schnell die Drehung der Hand folgt (pro Sekunde). Kleiner = schwerer/träger.
@export_range(1.0, 40.0, 0.5) var rotation_follow := 6.0
## Ab diesem Abstand (m) springt es sofort zur Hand (z.B. nach einem Teleport).
@export var snap_distance := 1.5
## Sichtbare Hand bleibt am Griff kleben (folgt dem schweren Objekt).
@export var glue_hand := true
## Namen der Kinder des Controllers, die als Hand mitgehen (leer = alle MeshInstance3D-Kinder).
@export var hand_visual_names: PackedStringArray = PackedStringArray()

const META := "held_transform"

var _pickable: Node3D
var _state: Transform3D
var _active := false
var _hand_offset := Transform3D() # Hand relativ zum Objekt
var _visuals: Array[Node3D] = []
var _visual_saved := {} # Node3D -> [transform, top_level]


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
	# Wo die Hand relativ zum Objekt sitzt (ohne Trägheit wäre Objekt == target)
	var ctrl := _controller()
	if ctrl:
		_hand_offset = target.affine_inverse() * ctrl.global_transform


func _process(_delta: float) -> void:
	if not _active or _visuals.is_empty():
		return
	# Hand sitzt immer am (trägen) Objekt -> bleibt am Griff
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
		if not (c is Node3D):
			continue
		var by_name := not hand_visual_names.is_empty() and c.name in hand_visual_names
		var by_type := hand_visual_names.is_empty() and c is MeshInstance3D
		if by_name or by_type:
			var v := c as Node3D
			_visual_saved[v] = [v.transform, v.top_level]
			v.top_level = true # unabhängig vom echten Controller bewegen
			_visuals.append(v)
	_hand_offset = _hand_target().affine_inverse() * ctrl.global_transform


func _release_hand_visuals() -> void:
	for v in _visuals:
		if is_instance_valid(v):
			v.top_level = _visual_saved[v][1]
			v.transform = _visual_saved[v][0]
	_visuals.clear()
	_visual_saved.clear()

# Wo die Hand das Objekt gerade hinsetzen will (Ziel des xr-tools Grab-Drivers).
func _hand_target() -> Transform3D:
	var driver = _pickable.get("_grab_driver")
	if driver is Node3D and is_instance_valid(driver):
		return driver.global_transform
	return _pickable.global_transform
