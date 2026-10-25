@tool
class_name HoldAligner
extends Node3D
## Editor-Helfer: Hänge dieses Skript an einen Node (z.B. Map/Strecke).
## Alle direkten Kinder (Holds) werden im Editor automatisch an der nächsten Wand ausgerichtet,
## sobald du sie verschiebst oder neu hineinziehst:
##   - Position rutscht auf die Wandoberfläche (optional)
##   - Vorderseite (+Z, blaue Achse) zeigt von der Wand weg
##   - die Drehung um die eigene Achse bleibt erhalten (mit E drehen geht weiter)
## Läuft nur im Editor, im Spiel passiert nichts.

@export var enabled := true
## Hold auf die Oberfläche ziehen. Aus = nur drehen, Position bleibt wo du sie hinziehst.
@export var snap_to_surface := true
## Wie weit (m) nach einer Wand gesucht wird.
@export_range(0.2, 5.0, 0.1) var search_radius := 2.0
## Abstand zur Oberfläche (m), z.B. 0.01 falls Holds leicht in der Wand verschwinden.
@export_range(-0.05, 0.1, 0.005) var surface_offset := 0.0

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
	# Bestehende Holds beim Öffnen nicht anfassen, nur merken
	for c in get_children():
		if c is Node3D:
			_last[c.get_instance_id()] = c.global_transform


func _process(_delta: float) -> void:
	if enabled and is_inside_tree():
		align_changed()


## Richtet alle Kinder aus, deren Transform sich seit dem letzten Mal geändert hat.
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
		if not force and _last.has(id) and _last[id].is_equal_approx(c.global_transform):
			continue
		var hit := _closest_surface(space, c, excl)
		if not hit.is_empty():
			c.global_transform = _aligned(c, hit.position, hit.normal)
		_last[id] = c.global_transform


func _closest_surface(space: PhysicsDirectSpaceState3D, node: Node3D, excl: Array[RID]) -> Dictionary:
	# etwas vor der aktuellen Vorderseite starten, damit der Strahl nicht in der Wand beginnt
	var from := node.global_position + node.global_basis.z.normalized() * 0.05
	var best := {}
	var best_d := INF
	for d in _dirs:
		var q := PhysicsRayQueryParameters3D.create(from, from + d * search_radius)
		q.exclude = excl
		q.hit_back_faces = false
		var r := space.intersect_ray(q)
		if r.is_empty():
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
