class_name LavaAudio
extends AudioStreamPlayer3D
## Lava soundscape. Add as a child of the Lava node.
## - Bubbling loop (stream): slides along the surface to stay below the player,
##   so the lava sounds like it comes from below. The higher you climb, the quieter it gets.
## - Rumble: deep bass without direction, gets louder the closer you are to the lava.
## - Heat: hiss that is only audible right above the lava.
## - Events around the player: blobs, cracking crust, steam, shifting crust.
## - Eruptions: a rare big outburst with flickering light and a light vibration.
## - play_sizzle(): e.g. when chunks of a hold fall into the lava (see HoldAudio).

## Half the size of the lava surface (m, local). Sounds stay inside this area.
@export var half_extent := Vector2(13, 13)
## Height of the surface relative to the Lava node (m).
@export var surface_height := 0.2
## How fast the loop follows the player (higher = more direct).
@export_range(0.5, 20.0, 0.5) var follow_speed := 4.0
## Number of single sounds that can play at once (blobs, cracks, hisses ...).
@export_range(1, 16) var voices := 8

@export_group("Blobs")
@export var blobs: Array[AudioStream] = []
## Random pause between two blobs (seconds, min/max).
@export var blob_interval := Vector2(2.5, 6.0)
## Blobs play within this radius (m) around the point below the player.
@export_range(1.0, 15.0, 0.5) var blob_radius := 6.0
@export_range(-30.0, 12.0, 0.5) var blob_volume_db := -8.0
## Random pitch (min/max), so the blobs never sound the same.
@export var blob_pitch := Vector2(0.85, 1.2)

@export_group("Rumble")
@export var rumble: AudioStream
## Volume right above the lava.
@export_range(-40.0, 12.0, 0.5) var rumble_volume_db := -9.0
## Volume from rumble_fade_height meters above the lava.
@export_range(-60.0, 12.0, 0.5) var rumble_far_db := -24.0
@export_range(1.0, 40.0, 0.5) var rumble_fade_height := 12.0

@export_group("Heat")
@export var heat: AudioStream
## Volume right above the lava. Gone from heat_height meters up.
@export_range(-40.0, 12.0, 0.5) var heat_volume_db := -14.0
@export_range(0.5, 10.0, 0.5) var heat_height := 3.0

@export_group("Crust & steam")
## Crust cracks open.
@export var cracks: Array[AudioStream] = []
@export var crack_interval := Vector2(8.0, 18.0)
@export_range(-30.0, 12.0, 0.5) var crack_volume_db := -12.0
## Steam hisses.
@export var hisses: Array[AudioStream] = []
@export var hiss_interval := Vector2(10.0, 22.0)
@export_range(-30.0, 12.0, 0.5) var hiss_volume_db := -18.0
## Crust shifts slowly (deep scraping).
@export var groans: Array[AudioStream] = []
@export var groan_interval := Vector2(25.0, 50.0)
@export_range(-30.0, 12.0, 0.5) var groan_volume_db := -14.0
## Radius (m) around the point below the player.
@export_range(1.0, 15.0, 0.5) var crust_radius := 9.0

@export_group("Eruption")
@export var eruptions: Array[AudioStream] = []
## Random pause between two eruptions (seconds, min/max).
@export var eruption_interval := Vector2(35.0, 70.0)
@export_range(-30.0, 12.0, 0.5) var eruption_volume_db := -5.0
## Distance (m, min/max) from the point below the player.
@export var eruption_distance := Vector2(3.0, 9.0)
## Light that flares up during an eruption (empty = off).
@export var eruption_light: OmniLight3D
@export_range(1.0, 5.0, 0.1) var eruption_light_boost := 2.2
## Vibration of both controllers (0 = off). Gets weaker with distance.
@export_range(0.0, 1.0, 0.05) var eruption_haptic := 0.2
@export_range(0.05, 2.0, 0.05) var eruption_haptic_time := 0.5

@export_group("Chunk sizzle")
@export var sizzles: Array[AudioStream] = []
@export_range(-30.0, 12.0, 0.5) var sizzle_volume_db := -4.0

var _snapped := false
var _player_local := Vector3.ZERO
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _last := {}
var _timers := {}
var _rumble: AudioStreamPlayer
var _heat: AudioStreamPlayer
var _light_energy := 0.0
@onready var _lava := get_parent() as Node3D


func _ready() -> void:
	add_to_group("lava_audio")
	_loop(stream)
	play()
	_rumble = _make_loop(rumble)
	_heat = _make_loop(heat)
	for i in voices:
		var p := AudioStreamPlayer3D.new()
		p.top_level = true
		p.unit_size = unit_size
		p.max_distance = max_distance
		p.bus = bus
		add_child(p)
		_voices.append(p)
	for k in ["blob", "crack", "hiss", "groan", "eruption"]:
		var iv: Vector2 = get(k + "_interval")
		_timers[k] = randf_range(iv.x, iv.y)
	if eruption_light:
		_light_energy = eruption_light.light_energy


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _lava == null:
		return
	_player_local = _lava.to_local(cam.global_position)
	var target := _lava.to_global(_on_surface(_player_local.x, _player_local.z))
	if not _snapped:
		global_position = target
		_snapped = true
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-follow_speed * delta))

	var height := maxf(cam.global_position.y - surface_y(), 0.0)
	if _rumble:
		_rumble.volume_db = lerpf(rumble_volume_db, rumble_far_db, clampf(height / rumble_fade_height, 0.0, 1.0))
	if _heat:
		var h := clampf(1.0 - height / heat_height, 0.0, 1.0)
		_heat.volume_db = linear_to_db(maxf(h * h, 0.0001)) + heat_volume_db

	_tick("blob", delta, blobs, blob_radius, 0.0, blob_volume_db, blob_pitch)
	_tick("crack", delta, cracks, crust_radius, 0.0, crack_volume_db, Vector2(0.8, 1.15))
	_tick("hiss", delta, hisses, crust_radius, 0.0, hiss_volume_db, Vector2(0.85, 1.2))
	_tick("groan", delta, groans, crust_radius, 3.0, groan_volume_db, Vector2(0.8, 1.1))
	if _tick("eruption", delta, eruptions, eruption_distance.y, eruption_distance.x, eruption_volume_db, Vector2(0.9, 1.1)):
		_eruption_fx()


## Global height of the lava surface.
func surface_y() -> float:
	return _lava.to_global(Vector3(0, surface_height, 0)).y


## Sizzle + splash at the point of the surface below [param at] (global).
func play_sizzle(at: Vector3) -> void:
	var l := _lava.to_local(at)
	_play(_pick("sizzle", sizzles), _lava.to_global(_on_surface(l.x, l.z)), sizzle_volume_db, randf_range(0.85, 1.15))


func _on_surface(x: float, z: float) -> Vector3:
	return Vector3(clampf(x, -half_extent.x, half_extent.x), surface_height,
		clampf(z, -half_extent.y, half_extent.y))


## Counts down the timer of one event type and at 0 plays a random sound
## in a ring (min_r..radius) around the point below the player. true = played.
func _tick(key: String, delta: float, list: Array[AudioStream], radius: float, min_r: float,
		db: float, pitch: Vector2) -> bool:
	if list.is_empty():
		return false
	_timers[key] -= delta
	if _timers[key] > 0.0:
		return false
	var iv: Vector2 = get(key + "_interval")
	_timers[key] = randf_range(iv.x, iv.y)
	var r := sqrt(randf_range((min_r * min_r) / (radius * radius), 1.0)) * radius
	var off := Vector2.from_angle(randf() * TAU) * r
	var pos := _lava.to_global(_on_surface(_player_local.x + off.x, _player_local.z + off.y))
	_play(_pick(key, list), pos, db, randf_range(pitch.x, pitch.y))
	return true


## Random sound from the list, never the same one twice in a row.
func _pick(key: String, list: Array[AudioStream]) -> AudioStream:
	if list.is_empty():
		return null
	var i := randi() % list.size()
	if list.size() > 1 and i == _last.get(key, -1):
		i = (i + 1) % list.size()
	_last[key] = i
	return list[i]


func _play(s: AudioStream, at: Vector3, db: float, pitch: float) -> void:
	if s == null or _voices.is_empty():
		return
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.global_position = at
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func _eruption_fx() -> void:
	if eruption_light:
		var tw := create_tween()
		tw.tween_property(eruption_light, "light_energy", _light_energy * eruption_light_boost, 0.12)
		for i in 4:
			tw.tween_property(eruption_light, "light_energy", _light_energy * randf_range(1.2, 1.8), 0.08)
			tw.tween_property(eruption_light, "light_energy", _light_energy * randf_range(1.6, eruption_light_boost), 0.08)
		tw.tween_property(eruption_light, "light_energy", _light_energy, 1.4).set_ease(Tween.EASE_OUT)
	if eruption_haptic <= 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	var near := 1.0
	if cam:
		near = clampf(1.0 - (cam.global_position.y - surface_y()) / rumble_fade_height, 0.2, 1.0)
	for c in get_tree().root.find_children("*", "XRController3D", true, false):
		Haptics.pulse(c, eruption_haptic * near, eruption_haptic_time)


func _make_loop(s: AudioStream) -> AudioStreamPlayer:
	if s == null:
		return null
	_loop(s)
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	add_child(p)
	p.play()
	return p


## Makes a stream loop endlessly (in case the import did not set a loop).
func _loop(s: AudioStream) -> void:
	var wav := s as AudioStreamWAV
	if wav and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
