class_name ExplosionFade
extends Node
## Fades the world to black when the bomb explodes. Add as a direct child of DigFinds.
## A black sphere around the head: hands and wrist menu inside it stay visible.

const SPHERE_RADIUS: float = 0.9

@export_range(0.0, 3.0, 0.05) var fade_time: float = 0.15


func _ready() -> void:
	var finds := get_parent() as DigFinds
	assert(finds != null, "ExplosionFade must be a direct child of DigFinds.")
	finds.time_up.connect(_fade_to_black)


func _fade_to_black() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	black.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	black.disable_fog = true
	black.render_priority = Material.RENDER_PRIORITY_MIN # below the wrist menu
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = SPHERE_RADIUS
	sphere_mesh.height = SPHERE_RADIUS * 2.0
	sphere_mesh.flip_faces = true
	sphere_mesh.material = black
	var sphere := MeshInstance3D.new()
	sphere.mesh = sphere_mesh
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(sphere)
	create_tween().tween_property(black, "albedo_color:a", 1.0, fade_time)
