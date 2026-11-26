class_name HotRing
extends Node3D
## Ring held with both grips, like a steering wheel. The wire runs along the ring's local Y axis
## (the TorusMesh axis).
## - Grab: both grips pressed with both hands on the ring (within grab_reach of the tube), anywhere
##   along it. A short tick in the controller when a hand is on the ring.
## - While held it follows the hands relative to where they grabbed (no jump):
##   moving/turning the hands moves/turns the ring, hands apart/together = bigger/smaller.
## - Let go: the ring stays where it is.

const GRIP_PRESSED: float = 0.7

@export var min_radius: float = 0.05
@export var max_radius: float = 0.4
## Thickness of the ring's tube.
@export var tube_radius: float = 0.012
## Size at the start
@export var start_radius: float = 0.08
## Hands must be this close to the ring's tube to grab it (m)
@export var grab_reach: float = 0.05

var left: XRController3D
var right: XRController3D
var radius: float = 0.15
## Both grips are pressed, the ring follows the hands.
var held: bool = false
# hands and ring at the moment of grabbing
var _grab_hands: Transform3D
var _grab_ring: Transform3D
var _grab_hand_distance: float
var _grab_radius: float
var _left_on_ring: bool = false
var _right_on_ring: bool = false

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _material: StandardMaterial3D = _mesh.material_override


func _process(_delta: float) -> void:
	var grips_pressed: bool = left.get_float("grip") > GRIP_PRESSED and right.get_float("grip") > GRIP_PRESSED
	if not held:
		_tick_when_on_ring()
	if not grips_pressed:
		held = false # let go: the ring stays where it is
		return
	var hand_distance: float = left.global_position.distance_to(right.global_position)
	if not held:
		if not (_on_ring(left) and _on_ring(right)):
			return
		held = true
		_grab_hands = _hands_frame()
		_grab_ring = global_transform
		_grab_hand_distance = hand_distance
		_grab_radius = radius
	global_transform = _hands_frame() * _grab_hands.affine_inverse() * _grab_ring
	radius = clampf(_grab_radius + (hand_distance - _grab_hand_distance) / 2.0, min_radius, max_radius)
	_update_mesh()


## Places the ring at the start, start size.
func place(start: Transform3D) -> void:
	held = false
	global_transform = start
	radius = start_radius
	_update_mesh()


## Hands as one frame: X from left to right hand, Y where the fists point, centre between them.
func _hands_frame() -> Transform3D:
	var a: Vector3 = left.global_position
	var b: Vector3 = right.global_position
	var x: Vector3 = (b - a).normalized()
	var pointing: Vector3 = -(left.global_basis.z + right.global_basis.z)
	var y: Vector3 = (pointing - x * pointing.dot(x)).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), (a + b) / 2.0)


## Hand is at the ring's tube (anywhere along the ring).
func _on_ring(hand: XRController3D) -> bool:
	var p: Vector3 = global_transform.affine_inverse() * hand.global_position
	return Vector2(Vector2(p.x, p.z).length() - radius, p.y).length() < tube_radius + grab_reach


## Short tick when a hand reaches the ring, so you feel where you can grab.
func _tick_when_on_ring() -> void:
	var left_now := _on_ring(left)
	var right_now := _on_ring(right)
	if left_now and not _left_on_ring:
		Haptics.pulse(left, 0.3, 0.03)
	if right_now and not _right_on_ring:
		Haptics.pulse(right, 0.3, 0.03)
	_left_on_ring = left_now
	_right_on_ring = right_now


func _update_mesh() -> void:
	var torus: TorusMesh = _mesh.mesh
	torus.inner_radius = radius - tube_radius
	torus.outer_radius = radius + tube_radius


func set_color(color: Color) -> void:
	_material.albedo_color = color


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
