class_name DigFinds
extends Node3D
## Buried finds in the sandbox (one at every MetalObject inside it).
## - Placeholder boxes = trash. The bomb_number-th find is the bomb:
##   once one less has been uncovered, the bomb lies (tilted, timer up) in the most covered
##   remaining spot, the other spots are cleared.
## - Uncovered = the upper part (UNCOVER_DEPTH of its height) is mostly free of earth.
## - Select: point the laser of an empty hand at it and pull the trigger.
##   Trash disappears, the bomb flies up in front of you (countdown is started later).

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
const UNCOVERED_FREE_SHARE: float = 0.65
## Share of the find's height that must be dug free from the top
const UNCOVER_DEPTH: float = 0.35
const CHECK_INTERVAL: float = 0.25
const LASER_LENGTH: float = 3.0
const LASER_THICKNESS: float = 0.002
const HIT_MARGIN: float = 0.03
## Select hint floats this far above a find (m)
const HINT_HEIGHT: float = 0.12
const TRIGGER_PRESSED: float = 0.7
## Bomb in the ground: tilt around its long axis and nose down (degrees, random in range)
const BOMB_ROLL_DEGREES := Vector2(15.0, 30.0)
const BOMB_PITCH_DEGREES := Vector2(8.0, 20.0)
## Where the selected bomb floats: in front of / below the head (m)
const BOMB_DISTANCE: float = 0.55
const BOMB_DROP: float = 0.55
const BOMB_FLIGHT_TIME: float = 1.2

var uncovered_count: int = 0
var trash_count: int = 0
var _finds: Array[Dictionary] = [] # {spot, model, bounds (AABB in spot space), uncovered, is_bomb, selectable}
var _time_to_next_check: float = 0.0
var _camera: XRCamera3D
var _hands: Array[Dictionary] = [] # {controller, pickup, laser, trigger_was_pressed}
var _select_hint: Label3D
var _trash_material: StandardMaterial3D


func _ready() -> void:
	_trash_material = StandardMaterial3D.new()
	_trash_material.albedo_color = Color(0.42, 0.4, 0.36)
	_trash_material.roughness = 0.9
	_select_hint = Label3D.new()
	_select_hint.text = "Trigger: auswählen"
	_select_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_select_hint.pixel_size = 0.001
	_select_hint.font_size = 48
	_select_hint.outline_size = 8
	_select_hint.no_depth_test = true
	_select_hint.top_level = true
	_select_hint.visible = false
	add_child(_select_hint)
	_bury.call_deferred()


func _bury() -> void:
	if sandbox == null:
		return
	for spot in sandbox.find_children("*", "", true, false):
		if spot is MetalObject:
			var trash_box := MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = trash_size
			box_mesh.material = _trash_material
			trash_box.mesh = box_mesh
			trash_box.rotation.y = randf() * TAU
			spot.add_child(trash_box)
			_finds.append({spot = spot, model = trash_box, bounds = trash_box.transform * box_mesh.get_aabb(), uncovered = false, is_bomb = false, selectable = false})
	if bomb_number <= 1:
		_place_bomb()


func _process(delta: float) -> void:
	_time_to_next_check -= delta
	if _time_to_next_check <= 0.0:
		_time_to_next_check = CHECK_INTERVAL
		_check_uncovered()
	if not _find_player():
		return
	_select_hint.visible = false
	for hand in _hands:
		_update_hand(hand)


func _check_uncovered() -> void:
	for find in _finds.duplicate():
		if find.uncovered or not _finds.has(find):
			continue
		if _top_free_share(find) >= UNCOVERED_FREE_SHARE:
			find.uncovered = true
			find.selectable = true
			uncovered_count += 1
			find_uncovered.emit(find.model, find.is_bomb)
			if uncovered_count == bomb_number - 1:
				_place_bomb()


## Share of a 3x3 grid (UNCOVER_DEPTH below the top of the find) that has no earth.
func _top_free_share(find: Dictionary) -> float:
	var spot: Node3D = find.spot
	var bounds: AABB = find.bounds
	var free_samples := 0
	for column in 3:
		for row in 3:
			var sample_point := Vector3(
				bounds.position.x + bounds.size.x * (0.15 + 0.35 * column),
				bounds.end.y - bounds.size.y * UNCOVER_DEPTH,
				bounds.position.z + bounds.size.z * (0.15 + 0.35 * row))
			if not sandbox.is_solid(spot.global_transform * sample_point):
				free_samples += 1
	return free_samples / 9.0


## The bomb goes into the most covered remaining spot, the other remaining spots are cleared.
func _place_bomb() -> void:
	var remaining: Array = _finds.filter(func(find): return not find.uncovered)
	if remaining.is_empty() or bomb_scene == null:
		return
	remaining.shuffle()
	remaining.sort_custom(func(find_a, find_b): return _top_free_share(find_a) < _top_free_share(find_b))
	for index in range(1, remaining.size()):
		var find_to_clear: Dictionary = remaining[index]
		find_to_clear.model.queue_free()
		find_to_clear.spot.remove_from_group(MetalObject.GROUP) # detector stays quiet there
		_finds.erase(find_to_clear)
	_turn_into_bomb(remaining[0])


## Swaps the box for the bomb: tilted like it fell in, timer up, highest point at the box top.
func _turn_into_bomb(find: Dictionary) -> void:
	var trash_box: Node3D = find.model
	var box_top: float = find.bounds.end.y
	var bomb: Bomb = bomb_scene.instantiate()
	find.spot.add_child(bomb)
	var roll := deg_to_rad(randf_range(BOMB_ROLL_DEGREES.x, BOMB_ROLL_DEGREES.y)) * (1 if randf() < 0.5 else -1)
	var pitch := deg_to_rad(randf_range(BOMB_PITCH_DEGREES.x, BOMB_PITCH_DEGREES.y)) * (1 if randf() < 0.5 else -1)
	var tilt := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.BACK, pitch) * Basis(Vector3.RIGHT, roll)
	var tilted_bounds := Transform3D(tilt, Vector3.ZERO) * _local_bounds(bomb)
	bomb.transform = Transform3D(tilt, Vector3.UP * (box_top - tilted_bounds.end.y))
	trash_box.queue_free()
	find.spot.strength = 1.0
	find.model = bomb
	find.bounds = bomb.transform * _local_bounds(bomb)
	find.is_bomb = true


func _update_hand(hand: Dictionary) -> void:
	var controller: XRController3D = hand.controller
	var laser: MeshInstance3D = hand.laser
	var hand_free: bool = hand.pickup.picked_up_object == null
	var menu_open := tool_menu != null and tool_menu.visible
	var has_selectable := _finds.any(func(find): return find.selectable)
	laser.visible = hand_free and has_selectable and not menu_open
	var trigger_pressed := controller.get_float("trigger") > TRIGGER_PRESSED
	var trigger_just_pressed: bool = trigger_pressed and not hand.trigger_was_pressed
	hand.trigger_was_pressed = trigger_pressed
	if not laser.visible:
		return

	var laser_start := controller.global_position
	var laser_direction := -controller.global_basis.z
	var laser_length := LASER_LENGTH
	var aimed_find: Dictionary = {}
	for find in _finds:
		if not find.selectable:
			continue
		var hit_distance := _ray_hits_box(laser_start, laser_direction, find.spot, find.bounds.grow(HIT_MARGIN))
		if hit_distance >= 0.0 and hit_distance < laser_length:
			laser_length = hit_distance
			aimed_find = find
	laser.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, laser_direction)) * Basis.from_scale(Vector3(1.0, laser_length, 1.0)), laser_start + laser_direction * laser_length * 0.5)
	if aimed_find.is_empty():
		return
	var spot: Node3D = aimed_find.spot
	_select_hint.global_position = spot.global_transform * aimed_find.bounds.get_center() + Vector3.UP * (aimed_find.bounds.size.y * 0.5 + HINT_HEIGHT)
	_select_hint.visible = true
	if trigger_just_pressed:
		_select(aimed_find)


func _select(find: Dictionary) -> void:
	find.selectable = false
	if find.is_bomb:
		_bring_bomb(find.model)
	else:
		trash_count += 1
		_throw_away(find.model)
		trash_selected.emit(trash_count)


## Trash: "Müll" pops up, the box rises and shrinks away.
func _throw_away(trash: Node3D) -> void:
	var trash_label := Label3D.new()
	trash_label.text = "Müll"
	trash_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	trash_label.pixel_size = 0.002
	trash_label.font_size = 64
	trash_label.outline_size = 10
	trash_label.no_depth_test = true
	trash_label.top_level = true
	add_child(trash_label)
	trash_label.global_position = trash.global_position + Vector3.UP * 0.25
	var vanish := create_tween().set_parallel()
	vanish.tween_property(trash, "global_position", trash.global_position + Vector3.UP * 0.4, 0.6)
	vanish.tween_property(trash, "scale", Vector3.ONE * 0.01, 0.6).set_ease(Tween.EASE_IN)
	vanish.tween_property(trash_label, "global_position", trash_label.global_position + Vector3.UP * 0.3, 1.2)
	vanish.tween_property(trash_label, "modulate:a", 0.0, 1.2).set_ease(Tween.EASE_IN)
	vanish.chain().tween_callback(trash.queue_free)
	vanish.tween_callback(trash_label.queue_free)


## Bomb: flies up in front of the player (front toward them). The countdown starts later (after the monologue).
func _bring_bomb(bomb: Bomb) -> void:
	var transform_in_ground := bomb.global_transform
	bomb.top_level = true
	bomb.global_transform = transform_in_ground
	var head := _camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var float_position := head.origin + forward * BOMB_DISTANCE + Vector3.DOWN * BOMB_DROP
	var float_transform := Transform3D(Basis.looking_at(forward), float_position) # bomb front (+Z) faces the player
	var flight := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	flight.tween_property(bomb, "global_transform", float_transform, BOMB_FLIGHT_TIME)
	bomb_selected.emit(bomb)


## Distance along the ray to the box (in node space), -1 if missed.
func _ray_hits_box(ray_start: Vector3, ray_direction: Vector3, node: Node3D, bounds: AABB) -> float:
	var world_to_node := node.global_transform.affine_inverse()
	var hit_point: Variant = bounds.intersects_ray(world_to_node * ray_start, world_to_node.basis * ray_direction)
	if hit_point == null:
		return -1.0
	return ray_start.distance_to(node.global_transform * (hit_point as Vector3))


## Bounds of all meshes below node, in node space.
func _local_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var is_first_mesh := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_to_node := Transform3D.IDENTITY
		var on_the_way: Node3D = mesh
		while on_the_way != node:
			mesh_to_node = on_the_way.transform * mesh_to_node
			on_the_way = on_the_way.get_parent()
		var mesh_bounds := mesh_to_node * mesh.get_aabb()
		bounds = mesh_bounds if is_first_mesh else bounds.merge(mesh_bounds)
		is_first_mesh = false
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
