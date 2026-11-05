class_name NatureWind
extends RefCounted
## Builds wind materials from imported plant materials (shaders in wind_*.gdshader).
## Same inputs give the same material (cached), so MultiMeshes share materials.

const OPAQUE := preload("res://zones/zone_2/nature/wind_opaque.gdshader")
const CUTOUT := preload("res://zones/zone_2/nature/wind_cutout.gdshader")

static var _cache := {}


## src: imported material. cutout: leaves with a hard edge.
## sway: sway (m) at the height sway_height (m). flutter: leaf flutter (m).
static func material(src: Material, cutout: bool, alpha_threshold: float, sway: float, sway_height: float,
		flutter: float, direction: Vector2, speed: float) -> Material:
	if not (src is BaseMaterial3D):
		return src
	var key := [src, cutout, alpha_threshold, sway, sway_height, flutter, direction, speed]
	if _cache.has(key):
		return _cache[key]
	var b := src as BaseMaterial3D
	var m := ShaderMaterial.new()
	m.shader = CUTOUT if cutout else OPAQUE
	m.resource_name = b.resource_name + "_Wind"
	m.set_shader_parameter("albedo_texture", b.albedo_texture)
	m.set_shader_parameter("albedo_color", b.albedo_color)
	m.set_shader_parameter("use_vertex_color", b.vertex_color_use_as_albedo)
	m.set_shader_parameter("roughness", b.roughness)
	if cutout:
		m.set_shader_parameter("alpha_scissor_threshold", alpha_threshold)
	m.set_shader_parameter("wind_direction", direction)
	m.set_shader_parameter("wind_speed", speed)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("sway_height", sway_height)
	m.set_shader_parameter("flutter", flutter)
	_cache[key] = m
	return m
