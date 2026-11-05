## Komponente für Klettergriffe, die nach dem Greifen zerfallen.
##
## Benutzung: als Kind-Node "GriffCrumble" unter einen Stone hängen (siehe stone_breaking.tscn).
## Die Komponente übernimmt automatisch das vorhandene Material (Texturen, Farben, Emission)
## und ersetzt es durch den Zerfalls-Shader.
##
## Der Stone ruft grab() beim ersten Greifen auf. Nach crumble_time Sekunden zerbricht der Griff:
## crumbled (Kollision aus) -> Plopp-Animation -> finished (Stone löscht sich dann selbst).
class_name GriffCrumble
extends Node

## Griff ist "weg" (Kollision aus).
signal crumbled
## Plopp-Animation fertig.
signal finished

enum State { IDLE, CRUMBLING, BROKEN }

## Holds that are crumbling right now. Pausing the game stops their processing through this group.
const GROUP := "crumbling"
const SHADER := preload("res://assets/holds/griff_crumble.gdshader")

## Verlauf des Textur-Wechsels über die Zeit. Größer als 1 = am Anfang schnell, zum Schluss langsamer.
const FADE_EXPONENT := 2.0
## Sekunden vor dem Verschwinden, ab denen der Stein zu wackeln beginnt.
const SHAKE_TIME := 0.7
## Stärke des Wackelns relativ zur Griffgröße.
const SHAKE_STRENGTH := 0.04
## Krümel pro Sekunde kurz vor Schluss (am Anfang weniger).
const CRUMB_RATE := 8.0
## Der Stein bläht sich kurz auf, bevor er verschwindet (Sekunden).
const POP_TIME := 0.12

## Kurzer Ruck beim Greifen.
const HAPTIC_GRAB := 0.6
const HAPTIC_GRAB_TIME := 0.08
## Ruhe nach dem Greifen (Sekunden), erst danach setzt das Dauer-Vibrieren ein.
const HAPTIC_QUIET_TIME := 1.0
## Dauer-Vibration während des Zerfalls: von leicht (Start) bis stark (Beginn der Warnphase).
const HAPTIC_MIN := 0.1
const HAPTIC_MAX := 0.5
## Blinkendes Vibrieren in der Warnphase (gleiche Dauer wie SHAKE_TIME).
const HAPTIC_BLINK := 0.9
const HAPTIC_BLINK_HZ := 6.0
## Letzter Stoß beim Zerbrechen.
const HAPTIC_BREAK := 1.0
const HAPTIC_BREAK_TIME := 0.15

@export_group("Zweites Texturset")
## Textur 2: Albedo / Base Color.
@export var crumble_texture: Texture2D
## Textur 2: ORM (R = Occlusion, G = Roughness, B = Metallic).
@export var crumble_orm_texture: Texture2D
## Textur 2: Normal Map.
@export var crumble_normal_texture: Texture2D
## Textur 2: Emission.
@export var crumble_emission_texture: Texture2D

@export_group("Maske")
## Graustufen-Maske auf den UVs (R-Kanal): schwarz = wechselt zuerst zu Textur 2, weiß = zuletzt.
@export var effect_mask: Texture2D
## Weichheit der Übergangskante (0.01 = hart, 0.5 = sehr weich).
@export_range(0.01, 0.5) var spread_softness := 0.15

@export_group("Ende")
## Farbe der Brocken (zufällig etwas heller/dunkler).
@export var chunk_color := Color(0.45, 0.38, 0.30)

## Sekunden vom Greifen bis zum Zerbrechen. Setzt der Stone aus seinem timer_time.
var crumble_time := 3.0
var state := State.IDLE
var progress := 0.0

@onready var target := get_parent() as Stone

var _materials: Array[ShaderMaterial] = []
var _crumb_accum := 0.0
var _haptic_time := 0.0
var _haptic_quiet_until := 0.0
var _crumb_mesh: SphereMesh
var _surface_points: Array = [] # [MeshInstance3D, PackedVector3Array]


func _ready() -> void:
	assert(target != null, "GriffCrumble muss direkt unter einem Stone hängen.")
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


# --------------------------------------------------------------------------- Vorwarnung

func _update_warning(delta: float) -> void:
	# Wackeln: steigt in den letzten SHAKE_TIME Sekunden von 0 auf 1
	var remaining := (1.0 - progress) * crumble_time
	var s := clampf(1.0 - remaining / SHAKE_TIME, 0.0, 1.0)
	_set_shader("shake", s * s)

	# Krümel: Rate wächst mit dem Fortschritt
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


# --------------------------------------------------------------------------- Haptik

func _update_haptics(delta: float) -> void:
	_haptic_time += delta
	if _haptic_time < _haptic_quiet_until:
		return
	var remaining := (1.0 - progress) * crumble_time
	var amp := 0.0
	if remaining <= SHAKE_TIME:
		# Warnphase: blinkendes An/Aus
		if fmod(_haptic_time * HAPTIC_BLINK_HZ, 1.0) < 0.5:
			amp = HAPTIC_BLINK
	else:
		# nach der Ruhephase von leicht bis stark bis zum Beginn der Warnphase
		var elapsed := progress * crumble_time
		var ramp_len := maxf(crumble_time - SHAKE_TIME - HAPTIC_QUIET_TIME, 0.001)
		var t := clampf((elapsed - HAPTIC_QUIET_TIME) / ramp_len, 0.0, 1.0)
		amp = lerpf(HAPTIC_MIN, HAPTIC_MAX, t * t)
	if amp > 0.0:
		_pulse(amp, 0.05) # kurz, wird jedes Frame erneuert -> Pausen beim Blinken bleiben spürbar


func _pulse(amplitude: float, duration: float) -> void:
	for c in _holding_controllers():
		Haptics.pulse(c, amplitude, duration)


## Controller der Hände, die den Griff gerade halten.
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
		# ORM-Annahme: R = AO, G = Roughness, B = Metallic
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
		push_warning("GriffCrumble: Material von Typ %s wird nicht übernommen." % src.get_class())

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
