class_name HoldGroundBlock
extends Node
## Stops a held XRToolsPickable from being pushed into the ground.
## Add as a child of the pickable and place probes (Marker3D children of the pickable)
## at the spots that must stay above ground (e.g. the edge of the detector coil).
## If a probe is below the surface, the whole object is pushed up.
## Also works in dug holes (a ray from above checks the real surface).
## Works together with HeavyHold (runs after it and corrects its state).

## Probes (Marker3D under the pickable).
@export var probes: Array[Node3D] = []
## Minimum distance of the probes to the surface (m).
@export_range(0.0, 0.2, 0.005) var margin := 0.02
## How far above a probe to search for the surface (m).
@export_range(0.1, 3.0, 0.05) var search_height := 0.8
## Physics layers that count as ground (default: layer 1 = static world).
@export_flags_3d_physics var ground_mask := 1

const META := "held_transform"

var _pickable: Node3D
var _active := false


func _ready() -> void:
	_pickable = get_parent() as Node3D
	process_physics_priority = 110 # after the grab driver and HeavyHold
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
