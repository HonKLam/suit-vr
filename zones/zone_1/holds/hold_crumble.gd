## Component for climbing holds that crumble after being grabbed.
##
## Usage: add as a child node "HoldCrumble" under a Hold (see breaking_hold.tscn).
## It automatically takes over the existing material (textures, colors, emission)
## and replaces it with the crumble shader.
##
## The Hold calls grab() on the first grab. After crumble_time seconds the hold breaks:
## crumbled (collision off) -> pop animation -> finished (the Hold then frees itself).
class_name HoldCrumble
extends Node

## The hold is "gone" (collision off).
signal crumbled
## Pop animation finished.
signal finished

enum State { IDLE, CRUMBLING, BROKEN }

## Holds that are crumbling right now. Pausing the game stops their processing through this group.
const GROUP := "crumbling"
const SHADER := preload("res://zones/zone_1/holds/hold_crumble.gdshader")

## Curve of the texture change over time. Above 1 = fast at the start, slower towards the end.
const FADE_EXPONENT := 2.0
## Seconds before disappearing at which the hold starts to shake.
const SHAKE_TIME := 0.7
## Shake strength relative to the hold's size.
const SHAKE_STRENGTH := 0.04
## Crumbs per second right before the end (fewer at the start).
const CRUMB_RATE := 8.0
## The hold briefly puffs up before it disappears (seconds).
const POP_TIME := 0.12

## Short jolt when grabbing.
const HAPTIC_GRAB := 0.6
const HAPTIC_GRAB_TIME := 0.08
## Quiet time after grabbing (seconds) before the continuous vibration starts.
const HAPTIC_QUIET_TIME := 1.0
## Continuous vibration while crumbling: from light (start) to strong (start of the warning phase).
const HAPTIC_MIN := 0.1
const HAPTIC_MAX := 0.5
## Blinking vibration in the warning phase (same duration as SHAKE_TIME).
const HAPTIC_BLINK := 0.9
const HAPTIC_BLINK_HZ := 6.0
## Final jolt when breaking.
const HAPTIC_BREAK := 1.0
const HAPTIC_BREAK_TIME := 0.15

@export_group("Second texture set")
## Texture 2: albedo / base color.
@export var crumble_texture: Texture2D
## Texture 2: ORM (R = occlusion, G = roughness, B = metallic).
@export var crumble_orm_texture: Texture2D
## Texture 2: normal map.
@export var crumble_normal_texture: Texture2D
## Texture 2: emission.
@export var crumble_emission_texture: Texture2D

@export_group("Mask")
## Grayscale mask on the UVs (R channel): black = changes to texture 2 first, white = last.
@export var effect_mask: Texture2D
## Softness of the transition edge (0.01 = hard, 0.5 = very soft).
@export_range(0.01, 0.5) var spread_softness := 0.15

@export_group("End")
## Chunk color (randomly a bit lighter or darker).
@export var chunk_color := Color(0.45, 0.38, 0.30)

## Seconds from grabbing until breaking. Set by the Hold from its timer_time.
var crumble_time := 3.0
var state := State.IDLE
var progress := 0.0

@onready var target := get_parent() as Hold

var _materials: Array[ShaderMaterial] = []
var _crumb_accum := 0.0
var _haptic_time := 0.0
var _haptic_quiet_until := 0.0
var _crumb_mesh: SphereMesh
var _surface_points: Array = [] # [MeshInstance3D, PackedVector3Array]


func _ready() -> void:
	assert(target != null, "HoldCrumble must be a direct child of a Hold.")
	_setup_materials()
	set_process(false)


func grab() -> void:
	if state != State.IDLE:
		return
	state = State.CRUMBLING
	add_to_group(GROUP)
	_pulse(HAPTIC_GRAB, HAPTIC_GRAB_TIME)
	_haptic_quiet_until = _haptic_time + maxf(HAPTIC_GRAB_TIME, HAPTIC_QUIET_TIME)
	set_process(true)


func _process(delta: float) -> void:
	progress = minf(progress + delta / maxf(crumble_time, 0.001), 1.0)
	_set_shader("progress", 1.0 - pow(1.0 - progress, FADE_EXPONENT))
	_update_warning(delta)
	_update_haptics(delta)
	if progress >= 1.0:
		_break()


func _break() -> void:
	_pulse(HAPTIC_BREAK, HAPTIC_BREAK_TIME)
	state = State.BROKEN
	remove_from_group(GROUP)
	set_process(false)
	for shape in target.find_children("*", "CollisionShape3D", true, false):
		shape.set_deferred("disabled", true)
	_set_shader("shake", 0.0)
	crumbled.emit()
	var box := _world_aabb()
	var size := maxf(box.get_longest_axis_size(), 0.01)
	CrumbleParticles.spawn_chunks(_effect_host(), box.get_center(), box.size, size, chunk_color)
	CrumbleParticles.spawn_puff(_effect_host(), box.get_center(), size)
	var orig := target.scale
	var tw := create_tween()
	tw.tween_property(target, "scale", orig * 1.18, POP_TIME * 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "scale", orig * 0.01, POP_TIME * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(finished.emit)


# --------------------------------------------------------------------------- Warning

func _update_warning(delta: float) -> void:
	# Shaking: rises from 0 to 1 during the last SHAKE_TIME seconds
	var remaining := (1.0 - progress) * crumble_time
	var s := clampf(1.0 - remaining / SHAKE_TIME, 0.0, 1.0)
	_set_shader("shake", s * s)

	# Crumbs: the rate grows with progress
	_crumb_accum += delta * CRUMB_RATE * progress
	while _crumb_accum >= 1.0:
		_crumb_accum -= 1.0
		_spawn_crumb()


func _spawn_crumb() -> void:
	if _surface_points.is_empty():
		return
	var entry: Array = _surface_points.pick_random()
	var mi: MeshInstance3D = entry[0]
	var verts: PackedVector3Array = entry[1]
	if not is_instance_valid(mi) or verts.is_empty():
		return
	var at := mi.global_transform * verts[randi() % verts.size()]
	var size := maxf(_world_aabb().get_longest_axis_size(), 0.01)
	if _crumb_mesh == null:
		_crumb_mesh = CrumbleParticles.crumb_mesh(size)
	CrumbleParticles.spawn_crumb(_effect_host(), at, _crumb_mesh, size, chunk_color)


func _effect_host() -> Node:
	return get_tree().current_scene if get_tree().current_scene else get_tree().root


# --------------------------------------------------------------------------- Haptics

func _update_haptics(delta: float) -> void:
	_haptic_time += delta
	if _haptic_time < _haptic_quiet_until:
		return
	var remaining := (1.0 - progress) * crumble_time
	var amp := 0.0
	if remaining <= SHAKE_TIME:
		# Warning phase: blinking on/off
		if fmod(_haptic_time * HAPTIC_BLINK_HZ, 1.0) < 0.5:
			amp = HAPTIC_BLINK
	else:
		# after the quiet time, from light to strong until the warning phase starts
		var elapsed := progress * crumble_time
		var ramp_len := maxf(crumble_time - SHAKE_TIME - HAPTIC_QUIET_TIME, 0.001)
		var t := clampf((elapsed - HAPTIC_QUIET_TIME) / ramp_len, 0.0, 1.0)
		amp = lerpf(HAPTIC_MIN, HAPTIC_MAX, t * t)
	if amp > 0.0:
		_pulse(amp, 0.05) # short and renewed every frame, so the gaps while blinking stay noticeable


func _pulse(amplitude: float, duration: float) -> void:
	for c in _holding_controllers():
		Haptics.pulse(c, amplitude, duration)


## Controllers of the hands holding this hold right now.
func _holding_controllers() -> Array:
	var out := []
	for h in target.holders:
		var n: Node = h
		while n and not (n is XRController3D):
			n = n.get_parent()
		if n and not out.has(n):
			out.append(n)
	return out


func _world_aabb() -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes():
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(target.global_position - Vector3.ONE * 0.05, Vector3.ONE * 0.1)
	return box


# --------------------------------------------------------------------------- Material

func _setup_materials() -> void:
	for mi in _meshes():
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var sm := _make_shader_material(mi.get_active_material(i))
			sm.set_shader_parameter("shake_size", mi.get_aabb().get_longest_axis_size() * SHAKE_STRENGTH)
			mi.set_surface_override_material(i, sm)
			_materials.append(sm)
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			_surface_points.append([mi, arrays[Mesh.ARRAY_VERTEX]])
		mi.material_override = null


func _make_shader_material(src: Material) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = SHADER
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		sm.set_shader_parameter("albedo_texture", b.albedo_texture)
		sm.set_shader_parameter("albedo_color", b.albedo_color)
		# Assumes ORM: R = AO, G = roughness, B = metallic
		var orm: Texture2D = b.roughness_texture if b.roughness_texture else b.metallic_texture
		sm.set_shader_parameter("orm_texture", orm)
		sm.set_shader_parameter("metallic", b.metallic)
		sm.set_shader_parameter("roughness", b.roughness)
		sm.set_shader_parameter("ao_strength", 1.0 if b.ao_enabled else 0.0)
		if b.normal_enabled:
			sm.set_shader_parameter("normal_texture", b.normal_texture)
			sm.set_shader_parameter("normal_scale", b.normal_scale)
		if b.emission_enabled:
			sm.set_shader_parameter("emission_color", b.emission)
			sm.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
			sm.set_shader_parameter("emission_texture", b.emission_texture)
			var add := b.emission_operator == BaseMaterial3D.EMISSION_OP_ADD and b.emission_texture != null
			sm.set_shader_parameter("emission_add", add)
			sm.set_shader_parameter("crumble_emission_energy", b.emission_energy_multiplier)
		else:
			sm.set_shader_parameter("emission_energy", 0.0)
		sm.set_shader_parameter("uv1_scale", b.uv1_scale)
		sm.set_shader_parameter("uv1_offset", b.uv1_offset)
	elif src != null:
		push_warning("HoldCrumble: material of type %s is not taken over." % src.get_class())

	sm.set_shader_parameter("use_crumble_texture", crumble_texture != null)
	sm.set_shader_parameter("crumble_texture", crumble_texture)
	sm.set_shader_parameter("use_crumble_orm", crumble_orm_texture != null)
	sm.set_shader_parameter("crumble_orm_texture", crumble_orm_texture)
	sm.set_shader_parameter("use_crumble_normal", crumble_normal_texture != null)
	sm.set_shader_parameter("crumble_normal_texture", crumble_normal_texture)
	sm.set_shader_parameter("use_crumble_emission", crumble_emission_texture != null)
	sm.set_shader_parameter("crumble_emission_texture", crumble_emission_texture)
	sm.set_shader_parameter("use_effect_mask", effect_mask != null)
	sm.set_shader_parameter("effect_mask", effect_mask)
	sm.set_shader_parameter("spread_softness", spread_softness)
	return sm


func _set_shader(param: StringName, value: Variant) -> void:
	for sm in _materials:
		sm.set_shader_parameter(param, value)


func _meshes() -> Array[Node]:
	return target.find_children("*", "MeshInstance3D", true, false)
