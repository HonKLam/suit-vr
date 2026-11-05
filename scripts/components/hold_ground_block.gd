class_name HoldGroundBlock
extends Node
## Verhindert, dass ein gehaltenes XRToolsPickable in den Boden gedrückt wird.
## Als Kind an das Pickable hängen und Prüfpunkte (Marker3D, Kinder des Pickables)
## an die Stellen setzen, die nicht in den Boden dürfen (z.B. Rand der Detektor-Spule).
## Liegt ein Prüfpunkt unter der Oberfläche, wird das ganze Objekt nach oben geschoben.
## Funktioniert auch in gegrabenen Löchern (prüft per Strahl von oben auf die echte Oberfläche).
## Mit HeavyHold kombinierbar (läuft danach und korrigiert dessen Stand).

## Prüfpunkte (Marker3D unter dem Pickable).
@export var probes: Array[Node3D] = []
## Mindestabstand der Prüfpunkte zur Oberfläche (m).
@export_range(0.0, 0.2, 0.005) var margin := 0.02
## Wie weit über einem Prüfpunkt nach der Oberfläche gesucht wird (m).
@export_range(0.1, 3.0, 0.05) var search_height := 0.8
## Physik-Ebenen, die als Boden zählen (Standard: Ebene 1 = statische Welt).
@export_flags_3d_physics var ground_mask := 1

const META := "held_transform"

var _pickable: Node3D
var _active := false


func _ready() -> void:
	_pickable = get_parent() as Node3D
	process_physics_priority = 110 # nach Grab-Driver und HeavyHold
	if _pickable and _pickable.has_signal("picked_up"):
		_pickable.picked_up.connect(func(_p): _active = true)
		_pickable.dropped.connect(func(_p): _active = false)


func _physics_process(_delta: float) -> void:
	if not _active or probes.is_empty():
		return
	var space := _pickable.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if _pickable is CollisionObject3D:
		exclude.append((_pickable as CollisionObject3D).get_rid())
	var push := 0.0
	for p in probes:
		if not is_instance_valid(p):
			continue
		var pos := p.global_position
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * search_height, pos, ground_mask, exclude)
		q.hit_back_faces = false
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		push = maxf(push, hit.position.y + margin - pos.y)
	if push <= 0.0:
		return
	var t := _pickable.global_transform
	t.origin.y += push
	_pickable.global_transform = t
	if _pickable.has_meta(META):
		_pickable.set_meta(META, t)
