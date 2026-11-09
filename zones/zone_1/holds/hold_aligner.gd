@tool
class_name HoldAligner
extends Node3D
## Editor helper: attach this script to a node (e.g. Map/Route).
## All direct children (holds) are automatically aligned to the wall in the editor
## as soon as you move them or drag new ones in:
##   - the position slides onto the wall you see behind the hold, i.e. under the mouse (optional)
##   - the front (+Z, blue axis) points away from the wall
##   - the rotation around its own axis stays (rotating with E still works)
## Only runs in the editor, nothing happens in the game.

@export var enabled := true
## Pull the hold onto the surface. Off = only rotate, the position stays where you drag it.
@export var snap_to_surface := true
## How far (m) to search for a wall when there is no editor camera.
@export_range(0.2, 5.0, 0.1) var search_radius := 2.0
## Distance to the surface (m), e.g. 0.01 if holds sink slightly into the wall.
@export_range(-0.05, 0.1, 0.005) var surface_offset := 0.0
## Only surfaces of this node count (e.g. the climbing wall, not the outer boundary). Empty = all.
@export var wall: Node3D

var _last := {}
var _dirs: Array[Vector3] = []


func _ready() -> void:
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x != 0 or y != 0 or z != 0:
					_dirs.append(Vector3(x, y, z).normalized())
	if not Engine.is_editor_hint():
		set_process(false)
		return
	# Leave existing holds alone when opening, only remember them
	for c in get_children():
		if c is Node3D:
			_last[c.get_instance_id()] = c.transform


func _process(_delta: float) -> void:
	if enabled and is_inside_tree():
		align_changed()


## Aligns all children whose transform changed since the last time.
func align_changed(force := false) -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var excl: Array[RID] = []
	for c in get_children():
		if c is CollisionObject3D:
			excl.append(c.get_rid())
	for c in get_children():
		if not (c is Node3D):
			continue
		var id: int = c.get_instance_id()
		# Local transform: moving the whole zone must not re-align its holds.
		if not force and _last.has(id) and _last[id].is_equal_approx(c.transform):
			continue
		var hit := _surface_on_screen(space, c, excl)
		if not hit.is_empty():
			c.global_transform = _aligned(c, hit.position, hit.normal)
		_last[id] = c.transform


## The wall seen behind the hold from the editor camera, so a dragged hold lands on the wall
## under the mouse. Outside the editor view (no camera) it falls back to the closest wall.
func _surface_on_screen(space: PhysicsDirectSpaceState3D, node: Node3D, excl: Array[RID]) -> Dictionary:
	var editor := Engine.get_singleton("EditorInterface") if Engine.is_editor_hint() else null
	var cam: Camera3D = editor.get_editor_viewport_3d(0).get_camera_3d() if editor else null
	if cam == null:
		return _closest_surface(space, node, excl)
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + (node.global_position - from).normalized() * 1000.0)
	q.exclude = excl
	q.hit_back_faces = false
	var r := space.intersect_ray(q)
	if r.is_empty() or not _is_wall(r.collider):
		return {}
	return r


func _is_wall(collider: Object) -> bool:
	return wall == null or wall.is_ancestor_of(collider)


func _closest_surface(space: PhysicsDirectSpaceState3D, node: Node3D, excl: Array[RID]) -> Dictionary:
	# start a bit in front of the current front side, so the ray does not begin inside the wall
	var from := node.global_position + node.global_basis.z.normalized() * 0.05
	var best := {}
	var best_d := INF
	for d in _dirs:
		var q := PhysicsRayQueryParameters3D.create(from, from + d * search_radius)
		q.exclude = excl
		q.hit_back_faces = false
		var r := space.intersect_ray(q)
		if r.is_empty() or not _is_wall(r.collider):
			continue
		var dist := from.distance_to(r.position)
		if dist < best_d:
			best_d = dist
			best = r
	return best


func _aligned(node: Node3D, point: Vector3, normal: Vector3) -> Transform3D:
	var n := normal.normalized()
	var up := node.global_basis.y
	up -= n * up.dot(n)
	if up.length() < 0.01:
		up = Vector3.UP - n * n.y
	if up.length() < 0.01:
		up = Vector3.FORWARD
	up = up.normalized()
	var x := up.cross(n).normalized()
	var s := node.global_basis.get_scale()
	var pos := point + n * surface_offset if snap_to_surface else node.global_position
	return Transform3D(Basis(x * s.x, up * s.y, n * s.z), pos)
