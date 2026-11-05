@tool
class_name Sandbox
extends Node3D
## Grabfläche im Stil von "A Game About Digging a Hole":
## Die Erde ist ein 3D-Volumen. Jeder Schaufelzug trägt eine Kugel ab – man kann
## senkrecht, schräg und seitlich graben, Tunnel inklusive. Oben Rasen, darunter Erdschichten.
## Oberfläche liegt bei y = 0 (lokal), die Erde reicht bis y = -depth.
## Intern: Dichte-Gitter (positiv = Erde) + Surface Nets, in Chunks und in
## Hintergrund-Threads neu vermascht (kein Ruckeln beim Graben).

## Wird nach jedem Graben gesendet. removed = abgetragene Erdmenge (m³, grob).
signal dug(world_pos: Vector3, removed: float)

## Größe der Fläche in Metern (x, z).
@export var size := Vector2(3, 3):
	set(v):
		size = v
		if is_inside_tree():
			_rebuild_all()
## Wie tief die Erde reicht (m). Darunter kommt man nicht weiter.
@export_range(0.3, 5.0, 0.1) var depth := 1.5:
	set(v):
		depth = v
		if is_inside_tree():
			_rebuild_all()
@export_group("Graben")
## Radius einer abgetragenen Kugel pro Schaufelzug (m).
@export_range(0.05, 1.0, 0.01) var dig_radius := 0.2
@export_group("Aussehen")
## Kantenlänge eines Voxels (m). Kleiner = rundere Dellen, aber langsamer.
@export_range(0.03, 0.2, 0.01) var voxel_size := 0.06:
	set(v):
		voxel_size = v
		if is_inside_tree():
			_rebuild_all()
@export var grass_color := Color(0.45, 0.68, 0.18)
## Wie dick die Rasenschicht oben ist (m).
@export_range(0.0, 0.2, 0.005) var grass_thickness := 0.03
## Erdschichten von oben nach unten (Comic-Stil, harte Übergänge).
@export var layer_colors: PackedColorArray = PackedColorArray([
	Color(0.64, 0.38, 0.25), Color(0.55, 0.31, 0.2), Color(0.45, 0.25, 0.16), Color(0.35, 0.19, 0.12)])
## Dicke einer Erdschicht (m).
@export_range(0.05, 1.0, 0.01) var layer_thickness := 0.35
@export var material_override: Material
@export_group("Debug")
## Taste G gräbt dort, wo die Kamera hinschaut (zum Testen ohne Schaufel).
@export var debug_key_dig := true

const CHUNK := 12 # Zellen pro Chunk-Kante
const SHADER := preload("res://assets/dig/dig_ground.gdshader")
const _CORNERS := [Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(0,1,0), Vector3i(1,1,0),
	Vector3i(0,0,1), Vector3i(1,0,1), Vector3i(0,1,1), Vector3i(1,1,1)]
const _EDGES := [[0,1],[2,3],[4,5],[6,7],[0,2],[1,3],[4,6],[5,7],[0,4],[1,5],[2,6],[3,7]]

var _n := Vector3i.ZERO # Anzahl Gitterpunkte
var _origin := Vector3.ZERO # lokale Position von Gitterpunkt (0,0,0)
var _d := PackedFloat32Array() # Dichte pro Gitterpunkt
var _s := PackedByteArray() # 1 = Erde (Dichte > 0)
var _chunks := {} # Vector3i -> MeshInstance3D
var _shapes := {} # Vector3i -> CollisionShape3D
var _body: StaticBody3D
var _default_mat: ShaderMaterial

# Hintergrund-Vermaschung
var _dirty := {} # Vector3i -> true
var _task := -1
var _task_keys: Array[Vector3i] = []
var _task_results: Array = []
var _snap_d := PackedFloat32Array()
var _snap_s := PackedByteArray()


func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "GroundBody"
	add_child(_body, false, Node.INTERNAL_MODE_FRONT)
	_rebuild_all()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1


## Trägt eine Kugel Erde um world_pos ab. radius < 0 = dig_radius.
## Gibt die abgetragene Menge (m³, grob) zurück, 0 wenn dort keine Erde war.
func dig_at(world_pos: Vector3, radius := -1.0) -> float:
	if radius < 0.0:
		radius = dig_radius
	var c := to_local(world_pos)
	var lo := _to_grid(c - Vector3.ONE * (radius + voxel_size)).clamp(Vector3i.ZERO, _n - Vector3i.ONE)
	var hi := (_to_grid(c + Vector3.ONE * (radius + voxel_size)) + Vector3i.ONE).clamp(Vector3i.ZERO, _n - Vector3i.ONE)
	var removed := 0
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				if _is_border(x, y, z):
					continue
				var i := _idx(x, y, z)
				var p := _origin + Vector3(x, y, z) * voxel_size
				var s := (p.distance_to(c) - radius) / voxel_size
				if s < _d[i]:
					if _s[i] == 1 and s <= 0.0:
						removed += 1
						_s[i] = 0
					_d[i] = s
	if removed == 0:
		return 0.0
	var c0 := (lo - Vector3i.ONE).clamp(Vector3i.ZERO, _n) / CHUNK
	var c1 := (hi + Vector3i.ONE).clamp(Vector3i.ZERO, _n) / CHUNK
	for cz in range(c0.z, c1.z + 1):
		for cy in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				_dirty[Vector3i(cx, cy, cz)] = true
	var vol := removed * pow(voxel_size, 3)
	dug.emit(world_pos, vol)
	return vol


## true, wenn an world_pos Erde ist.
func is_solid(world_pos: Vector3) -> bool:
	var g := _to_grid(to_local(world_pos) + Vector3.ONE * voxel_size * 0.5)
	if g.x < 0 or g.y < 0 or g.z < 0 or g.x >= _n.x or g.y >= _n.y or g.z >= _n.z:
		return false
	return _s[_idx(g.x, g.y, g.z)] == 1


## Alles wieder auffüllen.
func reset() -> void:
	_rebuild_all()


func _process(_delta: float) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_group_task_completed(_task):
			return
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1
		for k in _task_keys.size():
			_apply_chunk(_task_keys[k], _task_results[k])
	if _dirty.is_empty():
		return
	_task_keys.assign(_dirty.keys())
	_dirty.clear()
	_task_results.resize(_task_keys.size())
	_snap_d = _d.duplicate()
	_snap_s = _s.duplicate()
	_task = WorkerThreadPool.add_group_task(_build_task, _task_keys.size(), -1, true, "sandbox mesh")


func _build_task(k: int) -> void:
	_task_results[k] = _mesh_arrays(_task_keys[k], _snap_d, _snap_s)


func _idx(x: int, y: int, z: int) -> int:
	return (z * _n.y + y) * _n.x + x


func _to_grid(p: Vector3) -> Vector3i:
	return Vector3i(((p - _origin) / voxel_size).floor())


# Rand bleibt immer Erde (Wände/Boden), nur die Oberseite ist offen.
func _is_border(x: int, y: int, z: int) -> bool:
	return x == 0 or z == 0 or y == 0 or x == _n.x - 1 or z == _n.z - 1


func _rebuild_all() -> void:
	if _body == null:
		return
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1
	_dirty.clear()
	for k in _chunks:
		_chunks[k].queue_free()
		_shapes[k].queue_free()
	_chunks.clear()
	_shapes.clear()
	var cells := Vector3i(ceili(size.x / voxel_size) + 1, ceili(depth / voxel_size) + 2, ceili(size.y / voxel_size) + 1)
	_n = cells + Vector3i.ONE
	_origin = Vector3(-cells.x * voxel_size * 0.5, -depth - voxel_size, -cells.z * voxel_size * 0.5)
	_d = PackedFloat32Array()
	_d.resize(_n.x * _n.y * _n.z)
	_s = PackedByteArray()
	_s.resize(_d.size())
	for z in _n.z:
		for y in _n.y:
			var h := (-(_origin.y + y * voxel_size)) / voxel_size # >0 unter der Oberfläche
			for x in _n.x:
				var i := _idx(x, y, z)
				_d[i] = clampf(h, -2.0, 2.0)
				_s[i] = 1 if h > 0.0 else 0
	var nc := (cells + Vector3i.ONE * (CHUNK - 1)) / CHUNK
	for cz in nc.z:
		for cy in nc.y:
			for cx in nc.x:
				var ck := Vector3i(cx, cy, cz)
				_apply_chunk(ck, _mesh_arrays(ck, _d, _s))


func _apply_chunk(ck: Vector3i, arr: Array) -> void:
	var mi: MeshInstance3D = _chunks.get(ck)
	var cs: CollisionShape3D = _shapes.get(ck)
	if arr.is_empty():
		if mi:
			mi.mesh = null
			cs.shape = null
		return
	if mi == null:
		mi = MeshInstance3D.new()
		add_child(mi, false, Node.INTERNAL_MODE_FRONT)
		_chunks[ck] = mi
		cs = CollisionShape3D.new()
		_body.add_child(cs)
		_shapes[ck] = cs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, material_override if material_override else _material())
	mi.mesh = mesh
	cs.shape = mesh.create_trimesh_shape()


# Surface Nets für einen Chunk. Läuft auch in Threads: liest nur d/s, schreibt nichts.
# Gibt leeres Array zurück, wenn der Chunk keine Oberfläche hat.
func _mesh_arrays(ck: Vector3i, d: PackedFloat32Array, s: PackedByteArray) -> Array:
	var start := ck * CHUNK
	var end := (start + Vector3i.ONE * CHUNK).min(_n - Vector3i.ONE) # exklusiv (Zellen)
	if start.x >= end.x or start.y >= end.y or start.z >= end.z:
		return []
	var vmap := {}
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var sy := _n.x
	var sz := _n.x * _n.y
	# Zellen inkl. einer Zelle davor (für Quads an der Chunk-Grenze)
	var s0 := (start - Vector3i.ONE).max(Vector3i.ZERO)
	for z in range(s0.z, end.z):
		for y in range(s0.y, end.y):
			var row := z * sz + y * sy
			for x in range(s0.x, end.x):
				var i := row + x
				var cnt := s[i] + s[i + 1] + s[i + sy] + s[i + sy + 1] \
					+ s[i + sz] + s[i + sz + 1] + s[i + sz + sy] + s[i + sz + sy + 1]
				if cnt == 0 or cnt == 8:
					continue
				var v := _cell_vertex(d, i, x, y, z)
				var nrm := _cell_normal(d, i)
				vmap[Vector3i(x, y, z)] = verts.size()
				verts.append(v)
				normals.append(nrm)
	# Kanten von Punkt (x,y,z) in +x/+y/+z mit Vorzeichenwechsel -> Quad aus 4 Zellen
	for z in range(start.z, end.z):
		for y in range(start.y, end.y):
			var row := z * sz + y * sy
			for x in range(start.x, end.x):
				var i := row + x
				var a := s[i] == 1
				if x + 1 < _n.x and a != (s[i + 1] == 1) and y > 0 and z > 0:
					_quad(vmap, idx, Vector3i(x, y - 1, z - 1), Vector3i(x, y, z - 1), Vector3i(x, y, z), Vector3i(x, y - 1, z), a)
				if y + 1 < _n.y and a != (s[i + sy] == 1) and x > 0 and z > 0:
					_quad(vmap, idx, Vector3i(x - 1, y, z - 1), Vector3i(x - 1, y, z), Vector3i(x, y, z), Vector3i(x, y, z - 1), a)
				if z + 1 < _n.z and a != (s[i + sz] == 1) and x > 0 and y > 0:
					_quad(vmap, idx, Vector3i(x - 1, y - 1, z), Vector3i(x, y - 1, z), Vector3i(x, y, z), Vector3i(x - 1, y, z), a)
	if idx.is_empty():
		return []
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


func _quad(vmap: Dictionary, idx: PackedInt32Array, c0: Vector3i, c1: Vector3i, c2: Vector3i, c3: Vector3i, flip: bool) -> void:
	if not (vmap.has(c0) and vmap.has(c1) and vmap.has(c2) and vmap.has(c3)):
		return
	var i0: int = vmap[c0]
	var i1: int = vmap[c1]
	var i2: int = vmap[c2]
	var i3: int = vmap[c3]
	if flip:
		idx.append_array([i0, i2, i1, i0, i3, i2])
	else:
		idx.append_array([i0, i1, i2, i0, i2, i3])


func _cell_vertex(d: PackedFloat32Array, i: int, x: int, y: int, z: int) -> Vector3:
	var sy := _n.x
	var sz := _n.x * _n.y
	var vals := [d[i], d[i + 1], d[i + sy], d[i + sy + 1], d[i + sz], d[i + sz + 1], d[i + sz + sy], d[i + sz + sy + 1]]
	var sum := Vector3.ZERO
	var cnt := 0
	for e in _EDGES:
		var a: float = vals[e[0]]
		var b: float = vals[e[1]]
		if (a > 0.0) != (b > 0.0):
			sum += Vector3(_CORNERS[e[0]]).lerp(Vector3(_CORNERS[e[1]]), a / (a - b))
			cnt += 1
	return _origin + (Vector3(x, y, z) + sum / cnt) * voxel_size


func _cell_normal(d: PackedFloat32Array, i: int) -> Vector3:
	var sy := _n.x
	var sz := _n.x * _n.y
	var c000 := d[i]; var c100 := d[i + 1]; var c010 := d[i + sy]; var c110 := d[i + sy + 1]
	var c001 := d[i + sz]; var c101 := d[i + sz + 1]; var c011 := d[i + sz + sy]; var c111 := d[i + sz + sy + 1]
	var g := Vector3(
		(c000 + c010 + c001 + c011) - (c100 + c110 + c101 + c111),
		(c000 + c100 + c001 + c101) - (c010 + c110 + c011 + c111),
		(c000 + c100 + c010 + c110) - (c001 + c101 + c011 + c111))
	return g.normalized() if g.length_squared() > 0.0 else Vector3.UP


func _material() -> ShaderMaterial:
	if _default_mat == null:
		_default_mat = ShaderMaterial.new()
		_default_mat.shader = SHADER
	_default_mat.set_shader_parameter("grass_color", grass_color)
	_default_mat.set_shader_parameter("grass_thickness", grass_thickness)
	for k in 4:
		_default_mat.set_shader_parameter("layer_%d" % k, layer_colors[mini(k, layer_colors.size() - 1)] if not layer_colors.is_empty() else Color.WHITE)
	_default_mat.set_shader_parameter("layer_thickness", layer_thickness)
	return _default_mat


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not debug_key_dig:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 20.0)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.collider == _body:
			dig_at(hit.position)
