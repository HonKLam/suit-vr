@tool
class_name GrassScatter
extends Node3D
## Verteilt Gras-Büschel (MultiMesh) auf einer elliptischen Fläche um diesen Node.
## - Lässt einen Weg frei (Abstand zu den Kindern von path_node).
## - Auf der Grabfläche (sandbox) verschwinden Büschel, sobald darunter gegraben wird.
## Läuft im Editor als Vorschau mit, Positionen sind über seed reproduzierbar.

## Gras-Modelle (z.B. Grass_Common_Short.fbx). Pro Modell ein MultiMesh.
@export var grass_scenes: Array[PackedScene] = []:
	set(v):
		grass_scenes = v
		_queue_rebuild()
## Größe der Gras-Ellipse (Halbachsen x/z in m).
@export var radius := Vector2(9, 9):
	set(v):
		radius = v
		_queue_rebuild()
## Büschel pro m².
@export_range(0.1, 20.0, 0.1) var density := 2.5:
	set(v):
		density = v
		_queue_rebuild()
## Zum Rand der Ellipse hin dünner werden (0 = gleichmäßig).
@export_range(0.0, 1.0, 0.05) var edge_falloff := 0.6:
	set(v):
		edge_falloff = v
		_queue_rebuild()
@export var scale_range := Vector2(0.22, 0.34):
	set(v):
		scale_range = v
		_queue_rebuild()
@export var seed := 1:
	set(v):
		seed = v
		_queue_rebuild()
## Node, dessen Kinder den Weg bilden (z.B. Wegsteine). Dort wächst kein Gras.
@export var path_node: NodePath:
	set(v):
		path_node = v
		_queue_rebuild()
@export_range(0.0, 2.0, 0.05) var path_clearance := 0.55:
	set(v):
		path_clearance = v
		_queue_rebuild()
## Grabfläche: dort wächst kein Gras (oder, mit grow_on_sandbox, es verschwindet beim Graben).
@export var sandbox_path: NodePath:
	set(v):
		sandbox_path = v
		_queue_rebuild()
## Gras auch auf der Grabfläche wachsen lassen.
@export var grow_on_sandbox := false:
	set(v):
		grow_on_sandbox = v
		_queue_rebuild()

@export_group("Wind")
@export var wind_enabled := true:
	set(v):
		wind_enabled = v
		_queue_rebuild()
@export var wind_direction := Vector2(1.0, 0.3):
	set(v):
		wind_direction = v
		_queue_rebuild()
@export_range(0.0, 5.0, 0.05) var wind_speed := 1.0:
	set(v):
		wind_speed = v
		_queue_rebuild()
## Ausschlag der Halmspitzen (m) auf Höhe wind_sway_height.
@export_range(0.0, 0.3, 0.005) var wind_sway := 0.06:
	set(v):
		wind_sway = v
		_queue_rebuild()
@export_range(0.05, 2.0, 0.05) var wind_sway_height := 0.35:
	set(v):
		wind_sway_height = v
		_queue_rebuild()

var _rebuild_queued := false
var _dig_mm: Array[MultiMesh] = [] # Gras auf der Grabfläche, pro Modell
var _dig_pos: Array[PackedVector3Array] = [] # lokale Fußpunkte dazu
var _sandbox: Node3D


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		_sandbox = get_node_or_null(sandbox_path)
		if _sandbox and _sandbox.has_signal("dug"):
			_sandbox.dug.connect(_on_dug)


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	for c in get_children(true):
		if c is MultiMeshInstance3D and c.has_meta("_grass"):
			c.queue_free()
	_dig_mm.clear()
	_dig_pos.clear()
	var meshes: Array[Mesh] = []
	for ps in grass_scenes:
		if ps == null:
			continue
		var inst := ps.instantiate()
		var mi := inst as MeshInstance3D
		if mi == null:
			var found := inst.find_children("*", "MeshInstance3D", true, false)
			mi = found[0] if not found.is_empty() else null
		if mi and mi.mesh:
			meshes.append(_wind_mesh(mi.mesh) if wind_enabled else mi.mesh)
		inst.free()
	if meshes.is_empty():
		return
	var avoid: Array[Vector3] = []
	var pn := get_node_or_null(path_node)
	if pn:
		for c in pn.get_children():
			if c is Node3D:
				avoid.append(to_local(c.global_position))
	var sb := get_node_or_null(sandbox_path) as Node3D
	var sb_half := Vector2.ZERO
	if sb and "size" in sb:
		sb_half = sb.size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var area := PI * radius.x * radius.y
	var count := int(area * density)
	var lists := [] # pro Mesh: [normal: Array[Transform3D], dig: Array[Transform3D]]
	for m in meshes:
		lists.append([[], []])
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf())
		if edge_falloff > 0.0 and rng.randf() < r * r * edge_falloff:
			continue
		var p := Vector3(cos(a) * r * radius.x, 0, sin(a) * r * radius.y)
		var blocked := false
		for q in avoid:
			if Vector2(p.x - q.x, p.z - q.z).length() < path_clearance:
				blocked = true
				break
		if blocked:
			continue
		var on_dig := false
		if sb:
			var lp := sb.to_local(to_global(p))
			on_dig = absf(lp.x) < sb_half.x + 0.15 and absf(lp.z) < sb_half.y + 0.15
			if on_dig and not grow_on_sandbox:
				continue
		var sc := rng.randf_range(scale_range.x, scale_range.y)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), p)
		var k := rng.randi() % meshes.size()
		lists[k][1 if on_dig else 0].append(t)
	for k in meshes.size():
		for part in 2:
			var xs: Array = lists[k][part]
			if xs.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[k]
			mm.instance_count = xs.size()
			var pos := PackedVector3Array()
			for i in xs.size():
				mm.set_instance_transform(i, xs[i])
				pos.append(xs[i].origin)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.set_meta("_grass", true)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi, false, Node.INTERNAL_MODE_FRONT)
			if part == 1:
				_dig_mm.append(mm)
				_dig_pos.append(pos)


func _on_dug(world_pos: Vector3, _removed: float) -> void:
	var c := to_local(world_pos)
	var r := 0.6
	for k in _dig_mm.size():
		var mm := _dig_mm[k]
		var pos := _dig_pos[k]
		for i in pos.size():
			var p := pos[i]
			if Vector2(p.x - c.x, p.z - c.z).length() > r:
				continue
			# Boden unter dem Büschel weg? -> ausblenden
			if not _sandbox.is_solid(to_global(p) - Vector3(0, 0.03, 0)):
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), p))


func _wind_mesh(mesh: Mesh) -> Mesh:
	var m: Mesh = mesh.duplicate()
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		var cutout := mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		m.surface_set_material(s, NatureWind.material(mat, cutout, 0.5, wind_sway, wind_sway_height, 0.0,
			wind_direction, wind_speed))
	return m
