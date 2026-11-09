@tool
extends EditorPlugin
## Editor tool for building routes. Turn on "Place holds" in the 3D toolbar, then:
##   - click a hold: select it
##   - click / drag on the wall: the selected hold moves to the mouse cursor and faces out of the wall
##   - Shift + click on the wall: a copy of the selected hold is placed there (and selected)
## The hold keeps its scale and its rotation around its own axis.

var _button: Button
var _hold: Hold
var _dragging := false
var _start_transform: Transform3D


func _enter_tree() -> void:
	_button = Button.new()
	_button.text = "Place holds"
	_button.tooltip_text = "Click on the wall to put the selected hold there.\nShift + click: place a copy."
	_button.toggle_mode = true
	_button.flat = true
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _button)


func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _button)
	_button.queue_free()


func _handles(object: Object) -> bool:
	return object is Hold


func _edit(object: Object) -> void:
	_hold = object as Hold


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _button.button_pressed or _hold == null:
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			return _on_press(camera, event.position, event.shift_pressed)
		if _dragging:
			_dragging = false
			_commit_move()
			return AFTER_GUI_INPUT_STOP
	elif event is InputEventMouseMotion and _dragging:
		var hit := _raycast(camera, event.position, true)
		if not hit.is_empty():
			_place(_hold, hit)
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _on_press(camera: Camera3D, mouse: Vector2, copy: bool) -> int:
	# Clicking a hold selects it.
	var any := _raycast(camera, mouse, false)
	if not any.is_empty() and any.collider is Hold:
		var selection := EditorInterface.get_selection()
		selection.clear()
		selection.add_node(any.collider)
		return AFTER_GUI_INPUT_STOP
	var hit := _raycast(camera, mouse, true)
	if hit.is_empty():
		return AFTER_GUI_INPUT_PASS
	if copy:
		_place_copy(hit)
	else:
		_dragging = true
		_start_transform = _hold.transform
		_place(_hold, hit)
	return AFTER_GUI_INPUT_STOP


## Ray from the mouse into the scene. skip_holds: only walls count.
func _raycast(camera: Camera3D, mouse: Vector2, skip_holds: bool) -> Dictionary:
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.hit_back_faces = false
	if skip_holds:
		var excluded: Array[RID] = []
		for node in _hold.get_tree().get_nodes_in_group("holds"):
			excluded.append(node.get_rid())
		query.exclude = excluded
	return _hold.get_world_3d().direct_space_state.intersect_ray(query)


func _place(hold: Hold, hit: Dictionary) -> void:
	var normal: Vector3 = hit.normal.normalized()
	var up := hold.global_basis.y
	up -= normal * up.dot(normal)
	if up.length() < 0.01:
		up = Vector3.UP - normal * normal.y
	if up.length() < 0.01:
		up = Vector3.FORWARD
	up = up.normalized()
	var x := up.cross(normal).normalized()
	var s := hold.global_basis.get_scale()
	var offset := 0.0
	var aligner := hold.get_parent() as HoldAligner
	if aligner:
		offset = aligner.surface_offset
	hold.global_transform = Transform3D(Basis(x * s.x, up * s.y, normal * s.z), hit.position + normal * offset)
	if aligner:
		# Tell the aligner this is where the hold belongs, so it does not snap it elsewhere.
		aligner._last[hold.get_instance_id()] = hold.transform


func _commit_move() -> void:
	var end := _hold.transform
	var undo := get_undo_redo()
	undo.create_action("Place hold")
	undo.add_do_property(_hold, "transform", end)
	undo.add_undo_property(_hold, "transform", _start_transform)
	undo.commit_action(false)


func _place_copy(hit: Dictionary) -> void:
	var parent := _hold.get_parent()
	var copy := _hold.duplicate() as Hold
	var root := EditorInterface.get_edited_scene_root()
	var undo := get_undo_redo()
	undo.create_action("Place hold copy")
	undo.add_do_method(parent, "add_child", copy, true)
	undo.add_do_property(copy, "owner", root)
	undo.add_do_reference(copy)
	undo.add_undo_method(parent, "remove_child", copy)
	undo.commit_action()
	_place(copy, hit)
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(copy)
