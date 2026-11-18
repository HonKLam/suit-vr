class_name ToolMenu
extends Node3D
## Tool menu on the right wrist.
## - Open: turn the empty right hand palm up.
## - Choose: hold the left hand at a tool and pull the left trigger.
## - The tool appears in front of you, ready to grab.
## - Let go of shovel or detector: it goes back into the menu. Flags stick in the ground.

@export var shovel: XRToolsPickable
@export var metal_detector: XRToolsPickable
@export var flag_scene: PackedScene

## Size of a tool model in the menu (m)
const ICON_SIZE: float = 0.09
const ICON_SPACING: float = 0.11
## Height of the menu above the wrist (m)
const MENU_HEIGHT: float = 0.12
## How close the left hand must be to a tool (m)
const HOVER_DISTANCE: float = 0.07
const HOVER_SCALE: float = 1.35
const SPIN_SPEED: float = 1.0
## Palm facing up: opens above OPEN, closes below CLOSE (dot product with up)
const PALM_UP_OPEN: float = 0.5
const PALM_UP_CLOSE: float = 0.3
const TRIGGER_PRESSED: float = 0.7
## Where a chosen tool appears: grab point this far in front of / below the head (m)
const SPAWN_DISTANCE: float = 0.4
const SPAWN_DROP: float = 0.35
## Shovel appears blade forward, tilted down by this angle
const SHOVEL_TILT: float = 30.0

var _camera: XRCamera3D
var _right: XRController3D
var _left: XRController3D
var _right_pickup: XRToolsFunctionPickup
var _left_pickup: XRToolsFunctionPickup
var _icons: Array[Node3D] = []
var _choices: Array[Callable] = []
var _hovered: int = -1
var _trigger_was_pressed: bool = false
var _tool_layers: Dictionary = {} # tool -> [collision_layer, collision_mask]


func _ready() -> void:
	top_level = true
	visible = false
	if shovel:
		_add_choice(shovel.get_node("MeshModel"), "Schaufel", _bring.bind(shovel))
		_put_away.call_deferred(shovel)
		shovel.dropped.connect(_put_away)
	if metal_detector:
		_add_choice(metal_detector.get_node("Mesh"), "Detektor", _bring.bind(metal_detector))
		_put_away.call_deferred(metal_detector)
		metal_detector.dropped.connect(_put_away)
	if flag_scene:
		var flag_model: Node3D = flag_scene.instantiate()
		_add_choice(flag_model, "Fähnchen", _bring_flag)
		flag_model.free()


func _process(delta: float) -> void:
	if not _find_player():
		return
	var palm_up: float = (-_right.global_basis.x).dot(Vector3.UP) # palm of the right hand is -X
	var hand_free := _right_pickup.picked_up_object == null
	if visible:
		visible = hand_free and palm_up > PALM_UP_CLOSE
	else:
		visible = hand_free and palm_up > PALM_UP_OPEN
	if not visible:
		_hovered = -1
		return

	# row of tools above the wrist, facing the head
	var head := _camera.global_transform
	var side := head.basis.x
	side.y = 0.0
	side = side.normalized()
	var center := _right.global_position + Vector3.UP * MENU_HEIGHT
	global_transform = Transform3D(Basis.looking_at(center - head.origin), center)

	_hovered = -1
	var closest := HOVER_DISTANCE
	for i in _icons.size():
		var icon := _icons[i]
		icon.global_position = center + side * (i - (_icons.size() - 1) * 0.5) * ICON_SPACING
		icon.rotate_y(SPIN_SPEED * delta)
		var distance := icon.global_position.distance_to(_left_pickup.global_position)
		if distance < closest:
			closest = distance
			_hovered = i
	for i in _icons.size():
		var grow := HOVER_SCALE if i == _hovered else 1.0
		_icons[i].scale = Vector3.ONE * grow

	var trigger_pressed := _left.get_float("trigger") > TRIGGER_PRESSED
	if trigger_pressed and not _trigger_was_pressed and _hovered >= 0:
		_choices[_hovered].call()
	_trigger_was_pressed = trigger_pressed


func _find_player() -> bool:
	if is_instance_valid(_right):
		return true
	_camera = get_viewport().get_camera_3d() as XRCamera3D
	if _camera == null:
		return false
	var origin := _camera.get_parent()
	_right = origin.get_node_or_null("XRController3D_right")
	_left = origin.get_node_or_null("XRController3D_left")
	if _right == null or _left == null:
		return false
	_right_pickup = _right.get_node("FunctionPickup")
	_left_pickup = _left.get_node("FunctionPickup")
	return true


## Small copy of the tool model (only its meshes), scaled to ICON_SIZE.
func _add_choice(model: Node3D, title: String, choose: Callable) -> void:
	var copy := Node3D.new()
	var bounds := AABB()
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	for i in meshes.size():
		var original: MeshInstance3D = meshes[i]
		var mesh_copy := MeshInstance3D.new()
		mesh_copy.mesh = original.mesh
		mesh_copy.material_override = original.material_override
		for surface in original.get_surface_override_material_count():
			mesh_copy.set_surface_override_material(surface, original.get_surface_override_material(surface))
		mesh_copy.transform = Transform3D.IDENTITY if original == model else _relative_transform(model, original)
		copy.add_child(mesh_copy)
		var box := mesh_copy.transform * original.get_aabb()
		bounds = box if i == 0 else bounds.merge(box)
	var fit := ICON_SIZE / maxf(bounds.get_longest_axis_size(), 0.001)
	copy.scale = Vector3.ONE * fit
	copy.position = -bounds.get_center() * fit
	var icon := Node3D.new()
	icon.add_child(copy)
	var label := Label3D.new()
	label.text = title
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.0005
	label.font_size = 32
	label.outline_size = 8
	label.no_depth_test = true
	label.position = Vector3.DOWN * (ICON_SIZE * 0.5 + 0.015)
	icon.add_child(label)
	add_child(icon)
	_icons.append(icon)
	_choices.append(choose)


## Transform of node relative to root (works outside the scene tree).
func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != root and current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result


## Shows the tool floating in front of the player, grab point toward the player.
func _bring(tool: XRToolsPickable) -> void:
	if tool.is_picked_up():
		return
	for other: XRToolsPickable in [shovel, metal_detector]:
		if other and other != tool and other.visible and not other.is_picked_up():
			_put_away(other) # only one tool floats around at a time
	var head := _camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var spot := head.origin + forward * SPAWN_DISTANCE + Vector3.DOWN * SPAWN_DROP
	var orientation: Basis
	var grab_point: Vector3
	if tool == shovel:
		var tilt := deg_to_rad(SHOVEL_TILT)
		var toward_handle := -forward * cos(tilt) + Vector3.UP * sin(tilt)
		var loading_side_down := -Vector3.UP * cos(tilt) - forward * sin(tilt) # -Z (loading side) up
		orientation = Basis(toward_handle.cross(loading_side_down), toward_handle, loading_side_down)
		grab_point = Vector3(0, 1.21, 0) # D-grip
	else:
		orientation = Basis.looking_at(-forward) # coil (+Z) forward
		grab_point = Vector3(0, 0.559, 0.498) # handle
	tool.global_transform = Transform3D(orientation, spot - orientation * grab_point)
	_show(tool)


func _bring_flag() -> void:
	var flag: XRToolsPickable = flag_scene.instantiate()
	get_parent().add_child(flag)
	var head := _camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	flag.global_position = head.origin + forward.normalized() * SPAWN_DISTANCE + Vector3.DOWN * (SPAWN_DROP + 0.3)
	flag.freeze = true # floats until grabbed


func _show(tool: XRToolsPickable) -> void:
	if _tool_layers.has(tool):
		tool.collision_layer = _tool_layers[tool][0]
		tool.collision_mask = _tool_layers[tool][1]
	tool.visible = true
	tool.enabled = true
	tool.freeze = true # floats until grabbed


## Back into the menu: hidden, not grabbable, no collisions.
func _put_away(tool: XRToolsPickable) -> void:
	if tool.is_picked_up():
		return
	if tool.has_method("unstick"):
		tool.unstick()
	if not _tool_layers.has(tool):
		_tool_layers[tool] = [tool.collision_layer, tool.collision_mask]
	tool.freeze = true
	tool.visible = false
	tool.enabled = false
	tool.collision_layer = 0
	tool.collision_mask = 0
