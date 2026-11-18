class_name MarkerFlag
extends XRToolsPickable
## Small flag to mark finds. Let go above the ground and it sticks upright in the earth.

## How far below the flag the ground may be (m)
const MAX_DROP_HEIGHT: float = 1.5
## How deep the tip goes into the ground (m)
const STICK_DEPTH: float = 0.08
## Physics layers that count as ground
const GROUND_MASK: int = 1


func let_go(by: Node3D, p_linear_velocity: Vector3, p_angular_velocity: Vector3) -> void:
	super(by, p_linear_velocity, p_angular_velocity)
	if is_picked_up() or not by is XRToolsFunctionPickup:
		return
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * MAX_DROP_HEIGHT, GROUND_MASK, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return
	freeze = true
	global_transform = Transform3D(Basis(Vector3.UP, global_rotation.y), hit.position + Vector3.DOWN * STICK_DEPTH)
