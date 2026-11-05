class_name CrumbleParticles
extends RefCounted
## One-shot particle effects of a breaking hold: small crumbs, big chunks and a dust puff.
## Sizes are relative to the hold's size. Each effect frees itself when it is done.

const CHUNK_COUNT := 14
## Chunk size relative to the hold's size.
const CHUNK_SIZE := 0.22
const PUFF_COLOR := Color(1.0, 1.0, 1.0, 0.85)


static func crumb_mesh(size: float) -> SphereMesh:
	return _rock_mesh(size * CHUNK_SIZE * 0.18, 4)


static func spawn_crumb(host: Node, at: Vector3, mesh: SphereMesh, size: float, color: Color) -> void:
	var p := _rock_particles(mesh, 0.75, color)
	p.name = "GriffCrumb"
	p.amount = 2
	p.lifetime = 0.8
	p.spread = 70.0
	p.initial_velocity_min = size * 1.0
	p.initial_velocity_max = size * 3.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	_emit(host, p, at)


static func spawn_chunks(host: Node, center: Vector3, extents: Vector3, size: float, color: Color) -> void:
	var p := _rock_particles(_rock_mesh(size * CHUNK_SIZE * 0.5, 5), 0.7, color)
	p.name = "GriffChunks"
	p.amount = CHUNK_COUNT
	p.lifetime = 1.1
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents * 0.35
	p.spread = 180.0
	p.initial_velocity_min = size * 4.0
	p.initial_velocity_max = size * 9.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	_emit(host, p, center)


static func spawn_puff(host: Node, center: Vector3, size: float) -> void:
	var p := CPUParticles3D.new()
	p.name = "GriffPuff"
	var mesh := SphereMesh.new()
	mesh.radius = size * 0.13
	mesh.height = size * 0.26
	mesh.radial_segments = 10
	mesh.rings = 5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	p.mesh = mesh
	p.amount = 7
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.25
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = size * 1.0
	p.initial_velocity_max = size * 2.5
	p.gravity = Vector3(0, size * 1.5, 0)
	p.damping_min = size * 3.0
	p.damping_max = size * 5.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(0.4, 1.0))
	grow.add_point(Vector2(1.0, 1.3))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, PUFF_COLOR)
	fade.set_color(1, Color(PUFF_COLOR, 0.0))
	p.color_ramp = fade
	_emit(host, p, center)


# Few segments make an angular rock.
static func _rock_mesh(radius: float, segments: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.roughness = 1.0
	mesh.material = mat
	return mesh


# Falling rocks that keep their size, then shrink away from shrink_start on. Each gets a random color.
static func _rock_particles(mesh: SphereMesh, shrink_start: float, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.gravity = Vector3(0, -9.8, 0)
	p.particle_flag_rotate_y = true
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(shrink_start, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var ramp := Gradient.new()
	ramp.set_color(0, color.darkened(0.25))
	ramp.set_color(1, color.lightened(0.2))
	p.color_initial_ramp = ramp
	return p


static func _emit(host: Node, p: CPUParticles3D, at: Vector3) -> void:
	host.add_child(p)
	p.global_position = at
	p.emitting = true
	host.get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)
