class_name ToolAudio
extends Node3D
## Pickup and drop sounds. Add as a direct child of an XRToolsPickable (shovel, metal detector).
## The drop sound plays when the tool hits something after being let go, louder for a harder impact.

const DROP_MAX_SPEED := 5.0
const DROP_SPREAD_DB := 6.0
const DROP_COOLDOWN := 0.25
## After letting go, the throw speed is not taken for an impact.
const SETTLE_TIME := 0.15
const PITCH := Vector2(0.92, 1.08)
const UNIT_SIZE := 2.0
const MAX_DISTANCE := 30.0

@export_group("Sounds")
@export var pickup_sounds: Array[AudioStream] = []
@export var drop_sounds: Array[AudioStream] = []

@export_group("Volume")
@export_range(-30.0, 12.0, 0.5) var pickup_volume_db := -6.0
@export_range(-30.0, 12.0, 0.5) var drop_volume_db := -8.0

@export_group("Drop")
## How hard it has to hit something to make a sound (m/s). Higher = only hard drops.
## Below this nothing plays (rolling, small bumps).
@export_range(0.5, 4.0, 0.1) var drop_min_speed := 1.0

var _tool: XRToolsPickable
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _last := {}
var _armed := false # silent until the first pickup
var _held := false
var _settle := 0.0
var _cooldown := 0.0
var _last_velocity := Vector3.ZERO


func _ready() -> void:
	_tool = get_parent() as XRToolsPickable
	assert(_tool != null, "ToolAudio must be a direct child of an XRToolsPickable.")
	_tool.picked_up.connect(_on_picked_up)
	_tool.dropped.connect(_on_dropped)
	for i in 3:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = UNIT_SIZE
		p.max_distance = MAX_DISTANCE
		add_child(p)
		_voices.append(p)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_settle = maxf(_settle - delta, 0.0)
	var v := _tool.linear_velocity
	var change := (v - _last_velocity).length()
	_last_velocity = v
	if not _armed or _held or _settle > 0.0 or _cooldown > 0.0 or change < drop_min_speed:
		return
	_cooldown = DROP_COOLDOWN
	var t := clampf(inverse_lerp(drop_min_speed, DROP_MAX_SPEED, change), 0.0, 1.0)
	_play(_pick("drop", drop_sounds), drop_volume_db + lerpf(-DROP_SPREAD_DB, DROP_SPREAD_DB, t))


func _on_picked_up(_p) -> void:
	_armed = true
	_held = true
	_play(_pick("pickup", pickup_sounds), pickup_volume_db)


func _on_dropped(_p) -> void:
	_held = false
	_settle = SETTLE_TIME


func _play(s: AudioStream, db: float) -> void:
	if s == null:
		return
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = randf_range(PITCH.x, PITCH.y)
	p.play()


## Random sound, never the same one twice in a row.
func _pick(key: String, list: Array[AudioStream]) -> AudioStream:
	if list.is_empty():
		return null
	var i := randi() % list.size()
	if list.size() > 1 and i == _last.get(key, -1):
		i = (i + 1) % list.size()
	_last[key] = i
	return list[i]
