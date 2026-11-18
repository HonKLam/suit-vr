class_name MarkerFlag
extends XRToolsPickable
## Small flag to mark finds (origin = tip of the stick).
## - While held: a ring on the ground shows where it will land.
## - Let go above the ground: it sticks upright in the earth. Let go in the air: it disappears.

## How far below the flag the ground may be (m)
const MAX_DROP_HEIGHT: float = 1.5
## How deep the tip goes into the ground (m)
const STICK_DEPTH: float = 0.05
## Physics layers that count as ground
const GROUND_MASK: int = 1
const LANDING_RING_RADIUS: float = 0.05

var _landing_ring: MeshInstance3D


func _ready() -> void:
	super()
	_landing_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = LANDING_RING_RADIUS * 0.8
	ring.outer_radius = LANDING_RING_RADIUS
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(1.0, 1.0, 1.0)
	ring.material = ring_material
	_landing_ring.mesh = ring
	_landing_ring.top_level = true
	_landing_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_landing_ring.visible = false
	add_child(_landing_ring)


func _process(_delta: float) -> void:
	var landing = _landing_spot() if is_picked_up() else null
	_landing_ring.visible = landing != null
	if landing != null:
		_landing_ring.global_position = landing + Vector3.UP * 0.01


func let_go(by: Node3D, p_linear_velocity: Vector3, p_angular_velocity: Vector3) -> void:
	super(by, p_linear_velocity, p_angular_velocity)
	if is_picked_up() or not by is XRToolsFunctionPickup:
		return
	_landing_ring.visible = false
	var landing = _landing_spot()
	if landing == null:
		queue_free()
		return
	freeze = true
	global_transform = Transform3D(Basis(Vector3.UP, global_rotation.y), landing + Vector3.DOWN * STICK_DEPTH)


## Ground straight below the flag, or null.
func _landing_spot() -> Variant:
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * MAX_DROP_HEIGHT, GROUND_MASK, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.position if hit else null
