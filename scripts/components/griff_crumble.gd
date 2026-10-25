## Komponente für Klettergriffe, die nach dem Greifen zerfallen.
##
## Benutzung: als Kind-Node an einen Griff hängen (z.B. unter die Griff_Textured-Instanz).
## Die Komponente übernimmt automatisch das vorhandene Material (Texturen, Farben, Emission)
## und ersetzt es durch den Zerfalls-Shader.
##
## Von außen (später VR-Hand) nur zwei Aufrufe nötig:
##     griff.grab()     # Hand greift zu  -> Timer startet
##     griff.release()  # Hand lässt los
## Den passenden Griff zu einem getroffenen Collider findet man mit:
##     var griff := GriffCrumble.find_for(collider)
class_name GriffCrumble
extends Node

signal grab_started
signal grab_released
signal progress_changed(value: float)
## Wird bei jedem Vibrations-Puls gesendet (z.B. zum Debuggen oder für Sound).
signal haptic_pulse(amplitude: float, duration: float)
## Griff ist "weg" (Kollision aus). In VR hier die Hand zwangsweise loslassen.
signal crumbled
## Auflösen-Animation fertig, Griff unsichtbar / gelöscht.
signal finished

enum State { IDLE, CRUMBLING, DISSOLVING, GONE }
enum EndEffect { ZERFALLEN, VERBRENNEN }

const SHADER := preload("res://assets/holds/griff_crumble.gdshader")
const META_KEY := &"griff_crumble"

@export_group("Timing")
## Sekunden vom Greifen bis der Stein verschwindet.
@export var crumble_time := 3.0
## Nur beim Ende-Effekt "Verbrennen": Dauer der Auflös-Animation (0 = sofort weg).
@export var dissolve_time := 0.5
## true: Zerbricht von selbst, wenn crumble_time um ist.
## false: Bleibt bei 100 % stehen, bis break_now() aufgerufen wird (z.B. von stone_breaking.gd).
@export var auto_break := true
## true: Loslassen lässt den Griff sich wieder erholen. false: einmal angefasst, zerfällt er sicher.
@export var recover_on_release := false
## Sekunden, die das komplette Erholen von 100 % auf 0 % dauert.
@export var recover_time := 1.5
## Verlauf des Textur-Wechsels über die Zeit. 1 = gleichmäßig (linear).
## Größer als 1 = am Anfang schnell, zum Schluss langsamer (z.B. 2 oder 3).
## Kleiner als 1 = am Anfang langsam, zum Schluss schnell.
@export_range(0.25, 6.0, 0.05) var fade_exponent := 2.0
## Optional: eigene Kurve (x = Zeit 0..1, y = Textur-Wechsel 0..1). Wenn gesetzt, wird fade_exponent ignoriert.
@export var fade_curve: Curve

@export_group("Zweites Texturset")
## Textur 2: Albedo / Base Color. Leer = Textur 1 eingefärbt mit crumble_tint.
@export var crumble_texture: Texture2D
## Textur 2: ORM (R = Occlusion, G = Roughness, B = Metallic). Leer = crumble_roughness, nicht metallisch.
@export var crumble_orm_texture: Texture2D
## Textur 2: Normal Map. Leer = Normal Map von Textur 1.
@export var crumble_normal_texture: Texture2D
## Textur 2: Emission. Leer = Emission von Textur 1 in crumble_emission_color.
@export var crumble_emission_texture: Texture2D
## Nur ohne Albedo-Textur: Einfärbung von Textur 1.
@export var crumble_tint := Color(0.35, 0.30, 0.28)
@export var crumble_emission_color := Color(1.0, 0.15, 0.0)
@export_range(0.0, 1.0) var crumble_roughness := 1.0

@export_group("Maske")
## Graustufen-Maske auf den UVs (R-Kanal): schwarz = wechselt zuerst zu Textur 2, weiß = zuletzt.
## Leer = zufälliges Noise-Muster.
@export var effect_mask: Texture2D
## 1 = nur die Maske. Kleiner = Maske plus etwas Noise für unruhigere Kanten.
@export_range(0.0, 1.0) var mask_strength := 1.0
## Dreht die Maske um (weiß zuerst).
@export var invert_mask := false
## Weichheit der Übergangskante (0.01 = hart, 0.5 = sehr weich).
@export_range(0.01, 0.5) var spread_softness := 0.15

@export_group("Vorwarnung")
## Sekunden vor dem Verschwinden, ab denen der Stein zu wackeln beginnt (0 = aus).
@export_range(0.0, 3.0, 0.05) var shake_time := 0.7
## Stärke des Wackelns relativ zur Griffgröße.
@export_range(0.0, 0.2, 0.005) var shake_strength := 0.04
## Kleine Krümel fallen schon während des Zerfalls ab.
@export var crumbs_enabled := true
## Krümel pro Sekunde kurz vor Schluss (am Anfang weniger).
@export_range(0.0, 30.0, 0.5) var crumb_rate := 8.0

@export_group("Haptik")
## Controller-Vibration für die Hand/Hände, die den Griff halten.
@export var haptics_enabled := true
## Name der Haptik-Aktion in der OpenXR Action Map.
@export var haptic_action := "haptic"
## Kurzer Ruck beim Greifen.
@export_range(0.0, 1.0, 0.05) var haptic_grab := 0.6
@export_range(0.01, 0.5, 0.01) var haptic_grab_time := 0.08
## Dauer-Vibration während des Zerfalls: von leicht (Start) bis stark (Beginn der Warnphase).
@export_range(0.0, 1.0, 0.05) var haptic_min := 0.08
@export_range(0.0, 1.0, 0.05) var haptic_max := 0.5
## Blinkendes Vibrieren in der Warnphase (gleiche Dauer wie shake_time).
@export_range(0.0, 1.0, 0.05) var haptic_blink := 0.9
@export_range(1.0, 15.0, 0.5) var haptic_blink_hz := 6.0
## Letzter Stoß beim Zerbrechen.
@export_range(0.0, 1.0, 0.05) var haptic_break := 1.0
@export_range(0.01, 0.5, 0.01) var haptic_break_time := 0.15

@export_group("Ende")
## Zerfallen = Stein ploppt weg, Brocken fliegen (Comic). Verbrennen = löst sich mit Glutkante auf.
@export var end_effect := EndEffect.ZERFALLEN
## Anzahl der Brocken.
@export_range(0, 64) var chunk_count := 14
## Farbe der Brocken (zufällig etwas heller/dunkler).
@export var chunk_color := Color(0.45, 0.38, 0.30)
## Brockengröße relativ zur Griffgröße.
@export_range(0.05, 0.6) var chunk_size := 0.22
## Wie weit die Brocken fliegen (1 = normal).
@export_range(0.0, 4.0) var chunk_force := 1.0
## Staubwölkchen beim Zerfallen.
@export var puff_enabled := true
@export var puff_color := Color(1.0, 1.0, 1.0, 0.85)
## Der Stein bläht sich kurz auf, bevor er verschwindet (Sekunden, 0 = aus).
@export_range(0.0, 0.5) var pop_time := 0.12

@export_group("Aussehen")
## Nur beim Ende-Effekt "Verbrennen": Farbe der Glutkante.
@export var edge_color := Color(1.0, 0.4, 0.0)
## Größe des Noise-Musters (nur ohne Maske bzw. bei mask_strength < 1).
@export var noise_scale := 3.0

@export_group("Setup")
## Der Griff, der zerfällt. Leer = Eltern-Node.
@export var target: Node3D
## Legt automatisch eine StaticBody3D-Kollision (konvex) an, falls der Griff keine hat.
@export var auto_create_collision := true
## true: Griff wird nach dem Zerfall gelöscht. false: nur versteckt (reset() möglich).
@export var free_when_finished := false

var state := State.IDLE
var progress := 0.0

var _dissolve := 0.0
var _grab_count := 0 # zwei Hände können gleichzeitig greifen
var _materials: Array[ShaderMaterial] = []
var _orig_scale := Vector3.ONE
var _crumb_accum := 0.0
var _haptic_time := 0.0
var _haptic_quiet_until := 0.0
var _crumb_mesh: SphereMesh
var _surface_points: Array = [] # [MeshInstance3D, PackedVector3Array]
var _pop_tween: Tween


## Sucht ausgehend von einem Node (z.B. Collider) die zugehörige GriffCrumble-Komponente.
static func find_for(node: Node) -> GriffCrumble:
	while node:
		if node.has_meta(META_KEY):
			return node.get_meta(META_KEY) as GriffCrumble
		node = node.get_parent()
	return null


func _ready() -> void:
	if target == null:
		target = get_parent() as Node3D
	if target == null:
		push_error("GriffCrumble: kein target gefunden (Eltern-Node muss ein Node3D sein).")
		return
	target.set_meta(META_KEY, self)
	_orig_scale = target.scale
	add_to_group(&"griffe")
	_setup_materials()
	if auto_create_collision and _find_collision_objects(target).is_empty():
		_create_collision()
	set_process(false)


# --------------------------------------------------------------------------- API

func grab() -> void:
	if state == State.DISSOLVING or state == State.GONE:
		return
	_grab_count += 1
	if _grab_count == 1:
		grab_started.emit()
	_pulse(_holding_controllers(), haptic_grab, haptic_grab_time)
	_haptic_quiet_until = _haptic_time + haptic_grab_time
	if state == State.IDLE:
		state = State.CRUMBLING
	set_process(true)


func release() -> void:
	if _grab_count == 0:
		return
	_grab_count -= 1
	if _grab_count == 0:
		grab_released.emit()


func is_held() -> bool:
	return _grab_count > 0


## Setzt den Griff komplett zurück (nur wenn free_when_finished = false).
func reset() -> void:
	state = State.IDLE
	progress = 0.0
	_dissolve = 0.0
	_grab_count = 0
	_set_shader("progress", 0.0)
	_set_shader("dissolve", 0.0)
	_set_shader("shake", 0.0)
	_crumb_accum = 0.0
	if _pop_tween:
		_pop_tween.kill()
	target.scale = _orig_scale
	target.visible = true
	_set_collision_enabled(true)
	set_process(false)
	progress_changed.emit(progress)


# --------------------------------------------------------------------------- Ablauf

func _process(delta: float) -> void:
	match state:
		State.CRUMBLING:
			if is_held() or not recover_on_release:
				progress = minf(progress + delta / maxf(crumble_time, 0.001), 1.0)
			else:
				progress = maxf(progress - delta / maxf(recover_time, 0.001), 0.0)
			_set_shader("progress", _shaped(progress))
			_update_warning(delta)
			_update_haptics(delta)
			progress_changed.emit(progress)
			if progress >= 1.0:
				if auto_break:
					_start_dissolve()
				# sonst: bleibt bei 100 % und wackelt, bis break_now() kommt
			elif progress <= 0.0 and not is_held():
				state = State.IDLE
				set_process(false)
		State.DISSOLVING:
			_dissolve = minf(_dissolve + delta / maxf(dissolve_time, 0.001), 1.0)
			_set_shader("dissolve", _dissolve)
			if _dissolve >= 1.0:
				_finish()
		_:
			set_process(false)


## Sofort zerbrechen (von außen, z.B. vom Timer in stone_breaking.gd):
## Kollision aus, Brocken + Staub fliegen los, Griff unsichtbar. Ohne Plopp-Animation,
## damit der Besitzer den Griff direkt danach löschen kann.
func break_now() -> void:
	if state == State.DISSOLVING or state == State.GONE:
		return
	progress = 1.0
	_set_shader("progress", 1.0)
	_set_shader("shake", 0.0)
	_pulse(_holding_controllers(), haptic_break, haptic_break_time)
	state = State.DISSOLVING
	_grab_count = 0
	_set_collision_enabled(false)
	crumbled.emit()
	if end_effect == EndEffect.ZERFALLEN:
		var box := _world_aabb()
		var size := maxf(box.get_longest_axis_size(), 0.01)
		_spawn_chunks(box.get_center(), box.size, size)
		if puff_enabled:
			_spawn_puff(box.get_center(), size)
	free_when_finished = false
	_finish()


func _start_dissolve() -> void:
	_pulse(_holding_controllers(), haptic_break, haptic_break_time)
	state = State.DISSOLVING
	_grab_count = 0
	_set_collision_enabled(false)
	_set_shader("shake", 0.0)
	crumbled.emit()
	if end_effect == EndEffect.ZERFALLEN:
		set_process(false)
		_break_apart()
	elif dissolve_time <= 0.0:
		_finish()


func _finish() -> void:
	state = State.GONE
	set_process(false)
	finished.emit()
	if free_when_finished:
		target.queue_free()
	else:
		target.visible = false


## Wandelt die lineare Zeit (0..1) in den sichtbaren Textur-Wechsel um.
func _shaped(t: float) -> float:
	if t <= 0.0 or t >= 1.0:
		return clampf(t, 0.0, 1.0)
	if fade_curve:
		return clampf(fade_curve.sample_baked(t), 0.0, 1.0)
	return 1.0 - pow(1.0 - t, fade_exponent) # Ease-Out


# --------------------------------------------------------------------------- Vorwarnung

func _update_warning(delta: float) -> void:
	# Wackeln: steigt in den letzten shake_time Sekunden von 0 auf 1
	var remaining := (1.0 - progress) * crumble_time
	var s := 0.0
	if shake_time > 0.0:
		s = clampf(1.0 - remaining / shake_time, 0.0, 1.0)
	_set_shader("shake", s * s)

	# Krümel: Rate wächst mit dem Fortschritt, nur solange der Zerfall voranschreitet
	if crumbs_enabled and crumb_rate > 0.0 and (is_held() or not recover_on_release):
		_crumb_accum += delta * crumb_rate * progress
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
		_crumb_mesh = SphereMesh.new()
		_crumb_mesh.radial_segments = 4
		_crumb_mesh.rings = 2
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
		mat.roughness = 1.0
		_crumb_mesh.material = mat
	_crumb_mesh.radius = size * chunk_size * 0.18
	_crumb_mesh.height = size * chunk_size * 0.36
	var p := CPUParticles3D.new()
	p.name = "GriffCrumb"
	p.mesh = _crumb_mesh
	p.amount = 2
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = size * 1.0
	p.initial_velocity_max = size * 3.0
	p.gravity = Vector3(0, -9.8, 0)
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.75, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var ramp := Gradient.new()
	ramp.set_color(0, chunk_color.darkened(0.25))
	ramp.set_color(1, chunk_color.lightened(0.2))
	p.color_initial_ramp = ramp
	_add_effect(p, at)


# --------------------------------------------------------------------------- Haptik

func _update_haptics(delta: float) -> void:
	_haptic_time += delta
	if not haptics_enabled or _haptic_time < _haptic_quiet_until:
		return
	var ctrls := _holding_controllers()
	if ctrls.is_empty():
		return
	var remaining := (1.0 - progress) * crumble_time
	var amp := 0.0
	if shake_time > 0.0 and remaining <= shake_time:
		# Warnphase: blinkendes An/Aus
		if fmod(_haptic_time * haptic_blink_hz, 1.0) < 0.5:
			amp = haptic_blink
	else:
		# von leicht bis stark bis zum Beginn der Warnphase
		var warn_start := 1.0 - shake_time / maxf(crumble_time, 0.001)
		var t := clampf(progress / maxf(warn_start, 0.001), 0.0, 1.0)
		amp = lerpf(haptic_min, haptic_max, t * t)
	if amp > 0.0:
		_pulse(ctrls, amp, 0.05) # kurz, wird jedes Frame erneuert -> Pausen beim Blinken bleiben spürbar


func _pulse(ctrls: Array, amplitude: float, duration: float) -> void:
	if not haptics_enabled or amplitude <= 0.0 or ctrls.is_empty():
		return
	var scale := 1.0
	var us := get_node_or_null("/root/XRToolsUserSettings")
	if us and "haptics_scale" in us:
		scale = us.haptics_scale
	for c in ctrls:
		c.trigger_haptic_pulse(haptic_action, 0.0, clampf(amplitude * scale, 0.0, 1.0), duration, 0.0)
	haptic_pulse.emit(amplitude * scale, duration)


## Controller der Hände, die den Griff gerade halten (liest _holders vom Stone).
func _holding_controllers() -> Array:
	var out := []
	if target == null or not is_instance_valid(target):
		return out
	var hs = target.get("_holders")
	if not (hs is Array):
		return out
	for h in hs:
		var n: Node = h
		while n and not (n is XRController3D):
			n = n.get_parent()
		if n and not out.has(n):
			out.append(n)
	return out


# --------------------------------------------------------------------------- Zerfallen (Comic)

func _break_apart() -> void:
	var box := _world_aabb()
	var center := box.get_center()
	var size := maxf(box.get_longest_axis_size(), 0.01)
	_spawn_chunks(center, box.size, size)
	if puff_enabled:
		_spawn_puff(center, size)
	if pop_time > 0.0:
		_pop_tween = create_tween()
		_pop_tween.tween_property(target, "scale", _orig_scale * 1.18, pop_time * 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_pop_tween.tween_property(target, "scale", _orig_scale * 0.01, pop_time * 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_pop_tween.tween_callback(_finish_pop)
	else:
		_finish_pop()


func _finish_pop() -> void:
	if not free_when_finished:
		target.scale = _orig_scale
	_finish()


func _spawn_chunks(center: Vector3, extents: Vector3, size: float) -> void:
	if chunk_count <= 0:
		return
	var p := CPUParticles3D.new()
	p.name = "GriffChunks"
	var mesh := SphereMesh.new() # wenig Segmente = kantiger Brocken
	mesh.radius = size * chunk_size * 0.5
	mesh.height = size * chunk_size
	mesh.radial_segments = 5
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.roughness = 1.0
	mesh.material = mat
	p.mesh = mesh
	p.amount = chunk_count
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents * 0.35
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = size * 4.0 * chunk_force
	p.initial_velocity_max = size * 9.0 * chunk_force
	p.gravity = Vector3(0, -9.8, 0)
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var shrink := Curve.new() # bleibt groß, schrumpft am Ende weg (Comic-Plopp)
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.7, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var ramp := Gradient.new() # zufällige Farbe pro Brocken
	ramp.set_color(0, chunk_color.darkened(0.25))
	ramp.set_color(1, chunk_color.lightened(0.2))
	p.color_initial_ramp = ramp
	_add_effect(p, center)


func _spawn_puff(center: Vector3, size: float) -> void:
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
	fade.set_color(0, puff_color)
	fade.set_color(1, Color(puff_color, 0.0))
	p.color_ramp = fade
	_add_effect(p, center)


func _add_effect(p: CPUParticles3D, at: Vector3) -> void:
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	host.add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


func _world_aabb() -> AABB:
	var box := AABB()
	var first := true
	for mi in _find_meshes(target):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(target.global_position - Vector3.ONE * 0.05, Vector3.ONE * 0.1)
	return box


# --------------------------------------------------------------------------- Material

func _setup_materials() -> void:
	for mi in _find_meshes(target):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var sm := _make_shader_material(mi.get_active_material(i))
			sm.set_shader_parameter("shake_size", mi.get_aabb().get_longest_axis_size() * shake_strength)
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
	sm.set_shader_parameter("crumble_tint", crumble_tint)
	sm.set_shader_parameter("crumble_emission_color", crumble_emission_color)
	sm.set_shader_parameter("crumble_roughness", crumble_roughness)
	sm.set_shader_parameter("use_effect_mask", effect_mask != null)
	sm.set_shader_parameter("effect_mask", effect_mask)
	sm.set_shader_parameter("mask_strength", mask_strength)
	sm.set_shader_parameter("invert_mask", invert_mask)
	sm.set_shader_parameter("edge_color", edge_color)
	sm.set_shader_parameter("noise_scale", noise_scale)
	sm.set_shader_parameter("spread_softness", spread_softness)
	sm.set_shader_parameter("progress", 0.0)
	sm.set_shader_parameter("dissolve", 0.0)
	return sm


func _set_shader(param: StringName, value: Variant) -> void:
	for sm in _materials:
		sm.set_shader_parameter(param, value)


# --------------------------------------------------------------------------- Kollision

func _create_collision() -> void:
	for mi in _find_meshes(target):
		if mi.mesh == null:
			continue
		var body := StaticBody3D.new()
		body.name = "GriffCollision"
		var shape := CollisionShape3D.new()
		shape.shape = mi.mesh.create_convex_shape()
		body.add_child(shape)
		mi.add_child(body) # übernimmt automatisch die Transform des Meshes
		body.set_meta(META_KEY, self)


func _set_collision_enabled(enabled: bool) -> void:
	for n in _find_nodes(target, func(x): return x is CollisionShape3D or x is CollisionPolygon3D):
		n.set_deferred("disabled", not enabled)


func _find_collision_objects(root: Node) -> Array:
	return _find_nodes(root, func(x): return x is CollisionObject3D)


func _find_meshes(root: Node) -> Array:
	return _find_nodes(root, func(x): return x is MeshInstance3D)


func _find_nodes(root: Node, pred: Callable) -> Array:
	var out := []
	if pred.call(root):
		out.append(root)
	for c in root.get_children():
		if c == self:
			continue
		out.append_array(_find_nodes(c, pred))
	return out
