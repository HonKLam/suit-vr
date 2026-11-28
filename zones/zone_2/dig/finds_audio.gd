class_name FindsAudio
extends Node
## Sounds of the bomb countdown and the finds. Add as a direct child of DigFinds.
## - Tick: once a second while the countdown runs (the tick sounds are slightly muffled).
## - Last seconds: the ticks get faster, higher and louder until the explosion.
## - Explosion: when the time is up.
## - Pickup + time bonus: when a coin/can is selected (bonus only while the countdown runs).
## - Bomb found: the bomb flies up and its timer switches off.
## Pause, bomb found and time bonus need nothing extra for the ticks: it only ticks while the time goes down.

const TICK_VOICES: int = 6
## Pickup, bonus, bomb found and timer off can sound at the same time
const ONE_SHOT_VOICES: int = 4

@export_group("Sounds")
## Played in turns
@export var ticks: Array[AudioStream] = []
@export var explosion: AudioStream
@export var pickup: AudioStream
@export var time_bonus: AudioStream
@export var bomb_found: AudioStream
## The bomb timer switches off
@export var bomb_off: AudioStream

@export_group("Volume")
@export_range(-40.0, 12.0, 0.5) var tick_volume_db: float = -10.0
@export_range(-40.0, 12.0, 0.5) var explosion_volume_db: float = -4.5
@export_range(-40.0, 12.0, 0.5) var pickup_volume_db: float = -10.0
@export_range(-40.0, 12.0, 0.5) var time_bonus_volume_db: float = -12.0
@export_range(-40.0, 12.0, 0.5) var bomb_found_volume_db: float = -6.0
@export_range(-40.0, 12.0, 0.5) var bomb_off_volume_db: float = -8.0

@export_group("Speed up")
## The ticking gets faster during the last seconds (s).
@export_range(1.0, 30.0, 0.5) var speed_up_seconds: float = 10.0
## Time between two ticks when the speed up starts (s). 1 = no jump, smaller = faster right away.
@export_range(0.1, 1.0, 0.01) var start_interval: float = 0.5
## Time between two ticks right before the explosion (s). Smaller = more stress.
@export_range(0.05, 1.0, 0.01) var final_interval: float = 0.1
## Pitch of the ticks right before the explosion (1 = normal).
@export_range(1.0, 2.0, 0.05) var final_pitch: float = 1.4
## Extra volume of the ticks right before the explosion (dB).
@export_range(0.0, 12.0, 0.5) var final_extra_db: float = 4.0

var _finds: DigFinds
var _tick_voices: Array[AudioStreamPlayer] = []
var _one_shot_voices: Array[AudioStreamPlayer] = []
var _next_tick_voice: int = 0
var _next_one_shot_voice: int = 0
var _next_tick: int = 0
var _last_time_left: float = 0.0
var _time_since_tick: float = 0.0 # countdown seconds, not real time


func _ready() -> void:
	_finds = get_parent() as DigFinds
	assert(_finds != null, "FindsAudio must be a direct child of DigFinds.")
	_finds.time_up.connect(_on_time_up)
	_finds.trash_selected.connect(_on_trash_selected)
	_finds.bomb_selected.connect(_on_bomb_selected)
	for i in TICK_VOICES:
		_tick_voices.append(_make_player())
	for i in ONE_SHOT_VOICES:
		_one_shot_voices.append(_make_player())


func _process(_delta: float) -> void:
	var time_left: float = _finds.time_left
	var last_time_left: float = _last_time_left
	_last_time_left = time_left
	if not _finds.is_counting_down or time_left >= last_time_left:
		return # not running, paused or time bonus
	_time_since_tick += last_time_left - time_left
	if time_left >= speed_up_seconds:
		# in step with the seconds on the display
		if floori(time_left) < floori(last_time_left):
			_tick(time_left)
	elif _time_since_tick >= lerpf(final_interval, start_interval, time_left / speed_up_seconds):
		_tick(time_left)


func _tick(time_left: float) -> void:
	_time_since_tick = 0.0
	if ticks.is_empty():
		return
	var stress: float = 1.0 - clampf(time_left / speed_up_seconds, 0.0, 1.0) # 0 = normal, 1 = explosion
	var voice: AudioStreamPlayer = _tick_voices[_next_tick_voice]
	_next_tick_voice = (_next_tick_voice + 1) % _tick_voices.size()
	voice.stream = ticks[_next_tick]
	_next_tick = (_next_tick + 1) % ticks.size()
	voice.volume_db = tick_volume_db + final_extra_db * stress
	voice.pitch_scale = lerpf(1.0, final_pitch, stress)
	voice.play()


func _on_time_up() -> void:
	_stop_ticks()
	_play(explosion, explosion_volume_db)


func _on_trash_selected(_trash_count: int) -> void:
	_play(pickup, pickup_volume_db)
	if _finds.is_counting_down and _finds.bonus_seconds > 0.0:
		_play(time_bonus, time_bonus_volume_db)


func _on_bomb_selected(_bomb: Bomb) -> void:
	_stop_ticks()
	_play(bomb_off, bomb_off_volume_db)
	_play(bomb_found, bomb_found_volume_db)


func _stop_ticks() -> void:
	for voice in _tick_voices:
		voice.stop()


func _play(sound: AudioStream, volume_db: float) -> void:
	if sound == null:
		return
	var voice: AudioStreamPlayer = _one_shot_voices[_next_one_shot_voice]
	_next_one_shot_voice = (_next_one_shot_voice + 1) % _one_shot_voices.size()
	voice.stream = sound
	voice.volume_db = volume_db
	voice.play()


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	return player
