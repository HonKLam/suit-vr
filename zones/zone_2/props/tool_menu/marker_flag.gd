class_name MarkerFlag
extends XRToolsPickable
## Small flag to mark finds (origin = tip of the stick).
## - While held: a ring on the ground shows where it will land.
## - Let go above the ground: it sticks upright in the earth. Let go in the air: it disappears.
## - No collision with the player (no pushing, no getting stuck).

## How far below the flag the ground may be (m)
const MAX_DROP_HEIGHT: float = 1.5
## How deep the tip goes into the ground (m)
const STICK_DEPTH: float = 0.05
## Physics layers that count as ground
const GROUND_MASK: int = 1
const LANDING_RING_RADIUS: float = 0.05
## Ray starts this far above the flag tip; ring floats this far above the ground (m)
const RAY_START_ABOVE: float = 0.1
const RING_LIFT: float = 0.01

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
	_ignore_player_body.call_deferred()


func _process(_delta: float) -> void:
	var landing_spot = _landing_spot() if is_picked_up() else null
	_landing_ring.visible = landing_spot != null
	if landing_spot != null:
		_landing_ring.global_position = landing_spot + Vector3.UP * RING_LIFT


func let_go(released_by: Node3D, p_linear_velocity: Vector3, p_angular_velocity: Vector3) -> void:
	super(released_by, p_linear_velocity, p_angular_velocity)
	if is_picked_up() or not released_by is XRToolsFunctionPickup:
		return
	_landing_ring.visible = false
	var landing_spot = _landing_spot()
	if landing_spot == null:
		queue_free()
		return
	freeze = true
	global_transform = Transform3D(Basis(Vector3.UP, global_rotation.y), landing_spot + Vector3.DOWN * STICK_DEPTH)


## Ground straight below the flag, or null.
func _landing_spot() -> Variant:
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * RAY_START_ABOVE, global_position + Vector3.DOWN * MAX_DROP_HEIGHT, GROUND_MASK, [get_rid()])
	var ray_hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	return ray_hit.position if ray_hit else null


func _ignore_player_body() -> void:
	var camera := get_viewport().get_camera_3d()
	var player_body := XRToolsPlayerBody.find_instance(camera) if camera else null
	if player_body:
		add_collision_exception_with(player_body)
		player_body.add_collision_exception_with(self)
