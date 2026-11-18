class_name DigFinds
extends Node3D
## Buried finds in the sandbox (one at every MetalObject inside it).
## - Placeholder boxes = trash. The BOMB_NUMBER-th find you uncover turns into the bomb.
## - Uncovered = most of its top is free of earth.
## - Select: point the laser of an empty hand at it and pull the trigger.
##   Trash disappears, the bomb flies up in front of you, opens and starts counting down.

signal find_uncovered(find: Node3D, is_bomb: bool)
signal trash_selected(trash_count: int)
signal bomb_selected(bomb: Bomb)

@export var sandbox: Sandbox
@export var bomb_scene: PackedScene
## Hidden while the tool menu is open (it uses the left laser)
@export var tool_menu: Node3D
## Which uncovered find is the bomb (1 = first)
@export var bomb_number: int = 3
@export var trash_size: Vector3 = Vector3(0.28, 0.16, 0.2)

## Uncovered when at least this share of the top samples is free of earth
const FREE_SHARE: float = 0.65
const SAMPLE_HEIGHT: float = 0.03
const CHECK_INTERVAL: float = 0.25
const LASER_LENGTH: float = 3.0
const LASER_THICKNESS: float = 0.002
const HIT_MARGIN: float = 0.03
const TRIGGER_PRESSED: float = 0.7
## Where the selected bomb floats: in front of / below the head (m)
const BOMB_DISTANCE: float = 0.55
const BOMB_DROP: float = 0.55
const BOMB_FLIGHT_TIME: float = 1.2

var uncovered_count: int = 0
var trash_count: int = 0
var _finds: Array[Dictionary] = [] # {node, bounds (local AABB), uncovered, is_bomb, selectable}
var _check_timer: float = 0.0
var _camera: XRCamera3D
var _hands: Array[Dictionary] = [] # {controller, pickup, laser, trigger_was_pressed}
var _hint: Label3D
var _trash_material: StandardMaterial3D


func _ready() -> void:
	_trash_material = StandardMaterial3D.new()
	_trash_material.albedo_color = Color(0.42, 0.4, 0.36)
	_trash_material.roughness = 0.9
	_hint = Label3D.new()
	_hint.text = "Trigger: auswählen"
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.pixel_size = 0.001
	_hint.font_size = 48
	_hint.outline_size = 8
	_hint.no_depth_test = true
	_hint.top_level = true
	_hint.visible = false
	add_child(_hint)
	_bury.call_deferred()


func _bury() -> void:
	if sandbox == null:
		return
	for spot in sandbox.find_children("*", "", true, false):
		if spot is MetalObject:
			var box := MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = trash_size
			box_mesh.material = _trash_material
			box.mesh = box_mesh
			box.rotation.y = randf() * TAU
			spot.add_child(box)
			_finds.append({node = box, bounds = box_mesh.get_aabb(), uncovered = false, is_bomb = false, selectable = false})


func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHECK_INTERVAL
		_check_uncovered()
	if not _find_player():
		return
	_hint.visible = false
	for hand in _hands:
		_update_hand(hand)


func _check_uncovered() -> void:
	for find in _finds:
		if find.uncovered or not is_instance_valid(find.node):
			continue
		if _top_free_share(find) >= FREE_SHARE:
			find.uncovered = true
			find.selectable = true
			uncovered_count += 1
			if uncovered_count == bomb_number:
				_turn_into_bomb(find)
			find_uncovered.emit(find.node, find.is_bomb)


## Share of a 3x3 grid on top of the find that has no earth.
func _top_free_share(find: Dictionary) -> float:
	var node: Node3D = find.node
	var bounds: AABB = find.bounds
	var free_samples := 0
	for ix in 3:
		for iz in 3:
			var local := Vector3(
				bounds.position.x + bounds.size.x * (0.15 + 0.35 * ix),
				bounds.end.y + SAMPLE_HEIGHT,
				bounds.position.z + bounds.size.z * (0.15 + 0.35 * iz))
			if not sandbox.is_solid(node.global_transform * local):
				free_samples += 1
	return free_samples / 9.0


## Swaps the box for the bomb, tops at the same height.
func _turn_into_bomb(find: Dictionary) -> void:
	if bomb_scene == null:
		return
	var box: Node3D = find.node
	var box_top: float = find.bounds.end.y
	var bomb: Bomb = bomb_scene.instantiate()
	box.get_parent().add_child(bomb)
	var bounds := _local_bounds(bomb)
	bomb.transform = Transform3D(box.transform.basis, box.position + Vector3.UP * (box_top - bounds.end.y))
	box.queue_free()
	find.node = bomb
	find.bounds = bounds
	find.is_bomb = true


func _update_hand(hand: Dictionary) -> void:
	var controller: XRController3D = hand.controller
	var laser: MeshInstance3D = hand.laser
	var hand_free: bool = hand.pickup.picked_up_object == null
	var menu_open := tool_menu != null and tool_menu.visible
	var has_selectable := _finds.any(func(find): return find.selectable)
	laser.visible = hand_free and has_selectable and not menu_open
	var trigger_pressed := controller.get_float("trigger") > TRIGGER_PRESSED
	var just_pressed: bool = trigger_pressed and not hand.trigger_was_pressed
	hand.trigger_was_pressed = trigger_pressed
	if not laser.visible:
		return

	var start := controller.global_position
	var direction := -controller.global_basis.z
	var length := LASER_LENGTH
	var hovered: Dictionary = {}
	for find in _finds:
		if not find.selectable:
			continue
		var hit := _ray_hits_box(start, direction, find.node, find.bounds.grow(HIT_MARGIN))
		if hit >= 0.0 and hit < length:
			length = hit
			hovered = find
	laser.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, direction)) * Basis.from_scale(Vector3(1.0, length, 1.0)), start + direction * length * 0.5)
	if hovered.is_empty():
		return
	var node: Node3D = hovered.node
	_hint.global_position = node.global_transform * hovered.bounds.get_center() + Vector3.UP * (hovered.bounds.size.y * 0.5 + 0.12)
	_hint.visible = true
	if just_pressed:
		_select(hovered)


func _select(find: Dictionary) -> void:
	find.selectable = false
	if find.is_bomb:
		_bring_bomb(find.node)
	else:
		trash_count += 1
		_throw_away(find.node)
		trash_selected.emit(trash_count)


## Trash: "Müll" pops up, the box rises and shrinks away.
func _throw_away(trash: Node3D) -> void:
	var label := Label3D.new()
	label.text = "Müll"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.002
	label.font_size = 64
	label.outline_size = 10
	label.no_depth_test = true
	label.top_level = true
	add_child(label)
	label.global_position = trash.global_position + Vector3.UP * 0.25
	var tween := create_tween().set_parallel()
	tween.tween_property(trash, "global_position", trash.global_position + Vector3.UP * 0.4, 0.6)
	tween.tween_property(trash, "scale", Vector3.ONE * 0.01, 0.6).set_ease(Tween.EASE_IN)
	tween.tween_property(label, "global_position", label.global_position + Vector3.UP * 0.3, 1.2)
	tween.tween_property(label, "modulate:a", 0.0, 1.2).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(trash.queue_free)
	tween.tween_callback(label.queue_free)


## Bomb: flies up in front of the player (front toward them), then opens and counts down.
func _bring_bomb(bomb: Bomb) -> void:
	var start := bomb.global_transform
	bomb.top_level = true
	bomb.global_transform = start
	var head := _camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var spot := head.origin + forward * BOMB_DISTANCE + Vector3.DOWN * BOMB_DROP
	var target := Transform3D(Basis.looking_at(forward), spot) # bomb front (+Z) faces the player
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(bomb, "global_transform", target, BOMB_FLIGHT_TIME)
	tween.tween_callback(bomb.open_flap)
	tween.tween_callback(bomb.start_countdown)
	bomb_selected.emit(bomb)


## Distance along the ray to the box (in node space), -1 if missed.
func _ray_hits_box(start: Vector3, direction: Vector3, node: Node3D, bounds: AABB) -> float:
	var to_local := node.global_transform.affine_inverse()
	var local_start := to_local * start
	var local_direction := to_local.basis * direction
	var hit: Variant = bounds.intersects_ray(local_start, local_direction)
	if hit == null:
		return -1.0
	return start.distance_to(node.global_transform * (hit as Vector3))


## Bounds of all meshes below node, in node space.
func _local_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var relative := Transform3D.IDENTITY
		var current: Node3D = mesh
		while current != node:
			relative = current.transform * relative
			current = current.get_parent()
		var box := relative * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


func _find_player() -> bool:
	if not _hands.is_empty() and is_instance_valid(_hands[0].controller):
		return true
	_hands.clear()
	_camera = get_viewport().get_camera_3d() as XRCamera3D
	if _camera == null:
		return false
	var origin := _camera.get_parent()
	for controller_name in ["XRController3D_left", "XRController3D_right"]:
		var controller: XRController3D = origin.get_node_or_null(controller_name)
		if controller == null:
			_hands.clear()
			return false
		_hands.append({controller = controller, pickup = controller.get_node("FunctionPickup"), laser = _make_laser(), trigger_was_pressed = false})
	return true


func _make_laser() -> MeshInstance3D:
	var laser := MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = LASER_THICKNESS
	beam.bottom_radius = LASER_THICKNESS
	beam.height = 1.0 # stretched to the laser length
	beam.radial_segments = 6
	beam.rings = 1
	var beam_material := StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.albedo_color = Color(1.0, 0.85, 0.3)
	beam.material = beam_material
	laser.mesh = beam
	laser.top_level = true
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser.visible = false
	add_child(laser)
	return laser
