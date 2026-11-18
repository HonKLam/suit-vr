class_name ShovelAudio
extends Node3D
## Shovel sounds. Add as a direct child of a Shovel.
## - Stab: light / normal / strong, depending on the strength of Shovel.stabbed.
##   Plays right away, as the shovel then sticks in the ground.
## - Scoop: earth trickles off when the shovel pops out, louder for a bigger hole.

const STAB_SPREAD_DB := 3.0
const SCOOP_SPREAD_DB := 4.0
## Random pitch range
const PITCH_RANGE := Vector2(0.92, 1.08)
const UNIT_SIZE := 2.0
const MAX_DISTANCE := 30.0

@export_group("Sounds")
@export var stab_light: Array[AudioStream] = []
@export var stab_normal: Array[AudioStream] = []
@export var stab_strong: Array[AudioStream] = []
@export var scoops: Array[AudioStream] = []

@export_group("Volume")
@export_range(-30.0, 12.0, 0.5) var stab_volume_db := -5.0
@export_range(-30.0, 12.0, 0.5) var scoop_volume_db := -10.0

@export_group("Stab strength")
## From this stab strength (0..1) the stab sounds normal. Lower = normal sounds sooner.
@export_range(0.0, 1.0, 0.05) var normal_stab_from := 0.25
## From this stab strength (0..1) the stab sounds strong. Lower = strong sounds sooner.
@export_range(0.0, 1.0, 0.05) var strong_stab_from := 0.55

var _stab_voices: Array[AudioStreamPlayer3D] = []
var _scoop_voices: Array[AudioStreamPlayer3D] = []
var _next_stab_voice := 0
var _next_scoop_voice := 0
var _last_sound_index := {} # sound kind -> index of the last sound played


func _ready() -> void:
	var shovel := get_parent() as Shovel
	assert(shovel != null, "ShovelAudio must be a direct child of a Shovel.")
	shovel.stabbed.connect(_on_stabbed)
	shovel.scooped.connect(_on_scooped)
	# Own voices, so a long scoop is not cut by the next stab
	for i in 3:
		_stab_voices.append(_make_voice())
	for i in 4:
		_scoop_voices.append(_make_voice())


func _on_stabbed(strength: float, at: Vector3) -> void:
	_play_stab(strength, at)


func _on_scooped(at: Vector3, radius: float) -> void:
	var hole_size := clampf(inverse_lerp(Shovel.MIN_HOLE_RADIUS, Shovel.MAX_HOLE_RADIUS, radius), 0.0, 1.0)
	var volume_db := scoop_volume_db + lerpf(-SCOOP_SPREAD_DB, SCOOP_SPREAD_DB, hole_size)
	_next_scoop_voice = _play(_scoop_voices, _next_scoop_voice, _pick("scoop", scoops), at, volume_db)


func _play_stab(strength: float, at: Vector3) -> void:
	var sound_kind := "light"
	var sounds := stab_light
	if strength >= strong_stab_from:
		sound_kind = "strong"
		sounds = stab_strong
	elif strength >= normal_stab_from:
		sound_kind = "normal"
		sounds = stab_normal
	var volume_db := stab_volume_db + lerpf(-STAB_SPREAD_DB, STAB_SPREAD_DB, strength)
	_next_stab_voice = _play(_stab_voices, _next_stab_voice, _pick(sound_kind, sounds), at, volume_db)


## Returns the index of the next voice.
func _play(voices: Array[AudioStreamPlayer3D], voice_index: int, sound: AudioStream, at: Vector3, volume_db: float) -> int:
	if sound == null:
		return voice_index
	var voice := voices[voice_index]
	voice.global_position = at
	voice.stream = sound
	voice.volume_db = volume_db
	voice.pitch_scale = randf_range(PITCH_RANGE.x, PITCH_RANGE.y)
	voice.play()
	return (voice_index + 1) % voices.size()


## Random sound, never the same one twice in a row.
func _pick(sound_kind: String, sounds: Array[AudioStream]) -> AudioStream:
	if sounds.is_empty():
		return null
	var sound_index := randi() % sounds.size()
	if sounds.size() > 1 and sound_index == _last_sound_index.get(sound_kind, -1):
		sound_index = (sound_index + 1) % sounds.size()
	_last_sound_index[sound_kind] = sound_index
	return sounds[sound_index]


func _make_voice() -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.top_level = true
	voice.unit_size = UNIT_SIZE
	voice.max_distance = MAX_DISTANCE
	add_child(voice)
	return voice
