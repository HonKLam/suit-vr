extends MeshInstance3D
## Pull progress of a stuck Shovel, floats above the hands. Direct child of a Shovel.

const RING_SHADER := preload("res://zones/zone_2/props/shovel/pull_ring.gdshader")

const RING_SIZE: float = 0.12
const HEIGHT_ABOVE_HANDS: float = 0.2

var _shovel: Shovel
var _ring_material: ShaderMaterial


func _ready() -> void:
	_shovel = get_parent() as Shovel
	assert(_shovel != null, "PullRing must be a direct child of a Shovel.")
	top_level = true
	visible = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * RING_SIZE
	mesh = quad

	_ring_material = ShaderMaterial.new()
	_ring_material.shader = RING_SHADER
	material_override = _ring_material


func _process(_delta: float) -> void:
	visible = _shovel.is_stuck() and _shovel.is_two_handed()
	if not visible:
		return
	global_position = _shovel.get_hands_center() + Vector3.UP * HEIGHT_ABOVE_HANDS
	_ring_material.set_shader_parameter("progress", _shovel.pull_progress)
