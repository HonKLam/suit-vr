class_name ShovelAudio
extends Node3D
## Shovel sounds. Add as a direct child of a Shovel.
## - Stab: light / normal / strong, depending on the strength of Shovel.stabbed.
## - Scoop: earth trickles off after the lift, louder for a bigger hole.
## Both play together once earth was really removed, so a cancelled stab stays silent.

const STAB_SPREAD_DB := 3.0
const SCOOP_SPREAD_DB := 4.0
const PITCH := Vector2(0.92, 1.08)
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
var _next_stab := 0
var _next_scoop := 0
var _last := {}
var _pending := false # a stab waits for its hole
var _pending_strength := 0.0
var _pending_at := Vector3.ZERO


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
	_pending = true
	_pending_strength = strength
	_pending_at = at


func _on_scooped(at: Vector3, radius: float) -> void:
	if _pending:
		_pending = false
		_play_stab(_pending_strength, _pending_at)
	var size := clampf(inverse_lerp(Shovel.MIN_RADIUS, Shovel.MAX_RADIUS, radius), 0.0, 1.0)
	var db := scoop_volume_db + lerpf(-SCOOP_SPREAD_DB, SCOOP_SPREAD_DB, size)
	_next_scoop = _play(_scoop_voices, _next_scoop, _pick("scoop", scoops), at, db)


func _play_stab(strength: float, at: Vector3) -> void:
	var key := "light"
	var list := stab_light
	if strength >= strong_stab_from:
		key = "strong"
		list = stab_strong
	elif strength >= normal_stab_from:
		key = "normal"
		list = stab_normal
	var db := stab_volume_db + lerpf(-STAB_SPREAD_DB, STAB_SPREAD_DB, strength)
	_next_stab = _play(_stab_voices, _next_stab, _pick(key, list), at, db)


## Returns the index of the next voice.
func _play(pool: Array[AudioStreamPlayer3D], next: int, s: AudioStream, at: Vector3, db: float) -> int:
	if s == null:
		return next
	var p := pool[next]
	p.global_position = at
	p.stream = s
	p.volume_db = db
	p.pitch_scale = randf_range(PITCH.x, PITCH.y)
	p.play()
	return (next + 1) % pool.size()


## Random sound, never the same one twice in a row.
func _pick(key: String, list: Array[AudioStream]) -> AudioStream:
	if list.is_empty():
		return null
	var i := randi() % list.size()
	if list.size() > 1 and i == _last.get(key, -1):
		i = (i + 1) % list.size()
	_last[key] = i
	return list[i]


func _make_voice() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.top_level = true
	p.unit_size = UNIT_SIZE
	p.max_distance = MAX_DISTANCE
	add_child(p)
	return p
