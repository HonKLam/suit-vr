extends MeshInstance3D
## Ring on the earth where the blade of the Shovel will go in. Direct child of a Shovel.

const RING_RADIUS: float = 0.05
const RING_THICKNESS: float = 0.008
## Lifted a bit, so it isn't hidden in the earth
const LIFT: float = 0.01

var _shovel: Shovel


func _ready() -> void:
	_shovel = get_parent() as Shovel
	assert(_shovel != null, "StabMarker must be a direct child of a Shovel.")
	top_level = true
	visible = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var ring := TorusMesh.new()
	ring.inner_radius = RING_RADIUS - RING_THICKNESS
	ring.outer_radius = RING_RADIUS
	ring.rings = 24
	mesh = ring

	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	material_override = ring_material


func _process(_delta: float) -> void:
	visible = _shovel.has_stab_target and not _shovel.is_stuck()
	if visible:
		global_position = _shovel.stab_target + Vector3.UP * LIFT
