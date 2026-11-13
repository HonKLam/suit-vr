class_name ForestAudio
extends Node3D
## Forest soundscape. Add as a child of the map.
## - Wind: quiet bed without direction that swells up and down. Not a loop, so two players
##   take turns and crossfade.
## - Birds / distant forest: long recordings played at random places around the player.
##   Now and then a voice fades out, jumps elsewhere and fades back in.
## - Calls: single bird songs at random places around the player.

const SILENT_DB := -60.0
const WIND_CROSSFADE := 4.0
const BIRDS_HEIGHT := Vector2(1.0, 7.0)
const BIRDS_HOP := Vector2(8.0, 25.0)
const BIRDS_FADE := 1.5
const BIRDS_UNIT_SIZE := 10.0
const DISTANT_COUNT := 2
const DISTANT_DISTANCE := Vector2(25.0, 50.0)
const DISTANT_HEIGHT := Vector2(0.0, 6.0)
const DISTANT_HOP := Vector2(15.0, 40.0)
const DISTANT_FADE := 2.5
const DISTANT_UNIT_SIZE := 10.0
const CALL_DISTANCE := Vector2(6.0, 20.0)
const CALL_HEIGHT := Vector2(1.0, 6.0)
const CALL_PITCH := Vector2(0.92, 1.08)
const CALL_UNIT_SIZE := 4.0
const CALL_VOICES := 3

@export_group("Sounds")
@export var wind: AudioStream
## One long recording of many birds.
@export var birds: AudioStream
## One long recording of the forest far away.
@export var distant: AudioStream
## Single bird songs.
@export var calls: Array[AudioStream] = []

@export_group("Volume")
@export_range(-60.0, 12.0, 0.5) var wind_volume_db := -9.0
@export_range(-60.0, 12.0, 0.5) var birds_volume_db := -3.0
@export_range(-60.0, 12.0, 0.5) var distant_volume_db := -7.5
@export_range(-60.0, 12.0, 0.5) var call_volume_db := -6.0

@export_group("Wind")
## How much the wind swells down from its volume and back up (dB). 0 = constant wind.
@export_range(0.0, 30.0, 0.5) var wind_swell_db := 8.0

@export_group("Birds")
## How many places play the bird recording at the same time. 0 = no birds.
@export_range(0, 6) var birds_count := 3
## Average distance of the birds from the player (m). Smaller = closer.
@export_range(3.0, 40.0, 1.0) var birds_distance := 16.0

@export_group("Calls")
## Average pause between two single bird songs (seconds).
@export_range(3.0, 120.0, 1.0) var call_pause := 22.0

class Roamer:
	var player: AudioStreamPlayer3D
	var volume_db: float
	var distance: Vector2
	var height: Vector2
	var hop_interval: Vector2
	var fade: float
	var timer := 0.0

var _started := false
var _wind: Array[AudioStreamPlayer] = []
var _wind_fade: Array[float] = [0.0, 0.0] # 0..1 per player
var _wind_cur := 0
var _wind_level := 0.0 # dB below wind_volume_db
var _wind_target := 0.0
var _wind_timer := 0.0
var _roamers: Array[Roamer] = []
var _call_voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _last_call := -1
var _call_timer := 0.0


func _ready() -> void:
	if wind:
		for i in 2:
			var p := AudioStreamPlayer.new()
			p.stream = wind
			p.volume_db = SILENT_DB
			add_child(p)
			_wind.append(p)
	if birds:
		_add_roamers(birds, birds_count, birds_volume_db, BIRDS_UNIT_SIZE,
			Vector2(birds_distance * 0.5, birds_distance * 1.5), BIRDS_HEIGHT, BIRDS_HOP, BIRDS_FADE)
	if distant:
		_add_roamers(distant, DISTANT_COUNT, distant_volume_db, DISTANT_UNIT_SIZE,
			DISTANT_DISTANCE, DISTANT_HEIGHT, DISTANT_HOP, DISTANT_FADE)
	for i in CALL_VOICES:
		_call_voices.append(_make_player(CALL_UNIT_SIZE))
	_call_timer = _next_call_pause()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if not _started:
		_start(cam.global_position)
	_update_wind(delta)
	for r in _roamers:
		r.timer -= delta
		if r.timer <= 0.0:
			_hop(r)
	_call_timer -= delta
	if _call_timer <= 0.0:
		_call_timer = _next_call_pause()
		_play_call(cam.global_position)


func _start(head: Vector3) -> void:
	_started = true
	if not _wind.is_empty():
		_wind[0].play(randf() * wind.get_length() * 0.9)
	for r in _roamers:
		_place(r, head)
		r.player.play(randf() * r.player.stream.get_length())
		r.timer = randf_range(r.hop_interval.x, r.hop_interval.y)
		create_tween().tween_property(r.player, "volume_db", r.volume_db, r.fade)


func _next_call_pause() -> float:
	return call_pause * randf_range(0.5, 1.5)


## Wind level wanders; the other player takes over before the recording ends.
func _update_wind(delta: float) -> void:
	if _wind.is_empty():
		return
	_wind_timer -= delta
	if _wind_timer <= 0.0:
		_wind_timer = randf_range(6.0, 18.0)
		_wind_target = -randf_range(0.0, wind_swell_db)
	_wind_level = lerpf(_wind_level, _wind_target, 1.0 - exp(-0.5 * delta))

	var cur := _wind[_wind_cur]
	if cur.playing and wind.get_length() - cur.get_playback_position() <= WIND_CROSSFADE:
		_wind_cur = 1 - _wind_cur
		_wind[_wind_cur].play()
	var step := delta / WIND_CROSSFADE
	for i in 2:
		var p := _wind[i]
		_wind_fade[i] = move_toward(_wind_fade[i], 1.0 if i == _wind_cur else 0.0, step)
		if _wind_fade[i] <= 0.0 and i != _wind_cur and p.playing:
			p.stop()
		# Equal power: the two fades add up to 1, so the loudness stays the same in the middle
		var gain := sin(_wind_fade[i] * PI * 0.5)
		p.volume_db = wind_volume_db + _wind_level + linear_to_db(maxf(gain, 0.0001))


func _hop(r: Roamer) -> void:
	r.timer = randf_range(r.hop_interval.x, r.hop_interval.y) + 2.0 * r.fade
	var tw := create_tween()
	tw.tween_property(r.player, "volume_db", SILENT_DB, r.fade)
	tw.tween_callback(_relocate.bind(r))
	tw.tween_property(r.player, "volume_db", r.volume_db, r.fade)


func _relocate(r: Roamer) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		_place(r, cam.global_position)
	r.player.play(randf() * r.player.stream.get_length())


func _place(r: Roamer, head: Vector3) -> void:
	r.player.global_position = _ring_point(head, r.distance, r.height)


func _add_roamers(stream: AudioStream, count: int, volume_db: float, unit_size: float,
		distance: Vector2, height: Vector2, hop_interval: Vector2, fade: float) -> void:
	for i in count:
		var r := Roamer.new()
		r.player = _make_player(unit_size)
		r.player.stream = stream
		r.player.volume_db = SILENT_DB
		r.volume_db = volume_db
		r.distance = distance
		r.height = height
		r.hop_interval = hop_interval
		r.fade = fade
		# The recording is not a loop: when it ends, start somewhere else in it
		r.player.finished.connect(_relocate.bind(r))
		_roamers.append(r)


func _play_call(head: Vector3) -> void:
	if calls.is_empty():
		return
	var i := randi() % calls.size()
	if calls.size() > 1 and i == _last_call:
		i = (i + 1) % calls.size()
	_last_call = i
	var p := _call_voices[_next_voice]
	_next_voice = (_next_voice + 1) % _call_voices.size()
	p.global_position = _ring_point(head, CALL_DISTANCE, CALL_HEIGHT)
	p.stream = calls[i]
	p.volume_db = call_volume_db
	p.pitch_scale = randf_range(CALL_PITCH.x, CALL_PITCH.y)
	p.play()


## Random point around the head: distance on the ground plane, height above the head.
func _ring_point(head: Vector3, distance: Vector2, height: Vector2) -> Vector3:
	var off := Vector2.from_angle(randf() * TAU) * randf_range(distance.x, distance.y)
	return head + Vector3(off.x, randf_range(height.x, height.y), off.y)


func _make_player(unit_size: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.top_level = true
	p.unit_size = unit_size
	add_child(p)
	return p
