class_name HotRing
extends Node3D
## Ring held with both grips: its diameter is the distance between the hands, tilting the wrists
## tilts it. The wire runs along the ring's local Y axis (the TorusMesh axis).

const GRIP_PRESSED: float = 0.7

@export var min_radius: float = 0.05
@export var max_radius: float = 0.4
## Thickness of the ring's tube.
@export var tube_radius: float = 0.012

var left: XRController3D
var right: XRController3D
var radius: float = 0.15
## Both grips are pressed, the ring follows the hands.
var held: bool = false

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _material: StandardMaterial3D = _mesh.material_override


func _process(_delta: float) -> void:
	held = left.get_float("grip") > GRIP_PRESSED and right.get_float("grip") > GRIP_PRESSED
	visible = held
	if not held:
		return
	var a: Vector3 = left.global_position
	var b: Vector3 = right.global_position
	radius = clampf(a.distance_to(b) / 2.0, min_radius, max_radius)
	var x: Vector3 = (b - a).normalized()
	# ring axis: where the fists point, made perpendicular to the hand-to-hand line
	var pointing: Vector3 = -(left.global_basis.z + right.global_basis.z)
	var y: Vector3 = (pointing - x * pointing.dot(x)).normalized()
	global_transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) / 2.0)
	var torus: TorusMesh = _mesh.mesh
	torus.inner_radius = radius - tube_radius
	torus.outer_radius = radius + tube_radius


func set_color(color: Color) -> void:
	_material.albedo_color = color


## True if a wire point (global) is closer to the ring's tube than wire_radius.
func touches(points: PackedVector3Array, wire_radius: float) -> bool:
	var to_local: Transform3D = global_transform.affine_inverse()
	for point: Vector3 in points:
		var p: Vector3 = to_local * point
		if Vector2(Vector2(p.x, p.z).length() - radius, p.y).length() < tube_radius + wire_radius:
			return true
	return false


## Index of the wire segment that passes through the ring's hole, -1 if none does
## (ring slipped off the wire, or was pulled through it between two frames).
func threaded_segment(points: PackedVector3Array) -> int:
	var to_local: Transform3D = global_transform.affine_inverse()
	var prev: Vector3 = to_local * points[0]
	for i in range(1, points.size()):
		var p: Vector3 = to_local * points[i]
		if signf(prev.y) != signf(p.y):
			var hit: Vector3 = prev.lerp(p, prev.y / (prev.y - p.y))
			if Vector2(hit.x, hit.z).length() < radius:
				return i - 1
		prev = p
	return -1
