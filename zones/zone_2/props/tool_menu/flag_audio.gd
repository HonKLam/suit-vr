class_name FlagAudio
extends Node3D
## Marker flag sounds. Add as a direct child of a MarkerFlag.
## - Menu: when the tool menu brings a new flag.
## - Pickup: when the flag is grabbed.
## - Drop: when it is let go and sticks in the ground (not when it disappears in the air).

const PITCH_RANGE := Vector2(0.92, 1.08)
const UNIT_SIZE: float = 2.0
const MAX_DISTANCE: float = 30.0

@export_group("Sounds")
## One of them is played
@export var menu_sounds: Array[AudioStream] = []
@export var pickup: AudioStream
@export var drop: AudioStream

@export_group("Volume")
@export_range(-30.0, 12.0, 0.5) var menu_volume_db: float = -8.0
@export_range(-30.0, 12.0, 0.5) var pickup_volume_db: float = -10.0
@export_range(-30.0, 12.0, 0.5) var drop_volume_db: float = -6.0

var _flag: MarkerFlag
var _voice: AudioStreamPlayer3D


func _ready() -> void:
	_flag = get_parent() as MarkerFlag
	assert(_flag != null, "FlagAudio must be a direct child of a MarkerFlag.")
	_flag.picked_up.connect(_on_picked_up)
	_flag.dropped.connect(_on_dropped)
	_voice = AudioStreamPlayer3D.new()
	_voice.unit_size = UNIT_SIZE
	_voice.max_distance = MAX_DISTANCE
	add_child(_voice)
	# the menu places the flag right after adding it
	_play_menu_sound.call_deferred()


func _play_menu_sound() -> void:
	if not menu_sounds.is_empty():
		_play(menu_sounds.pick_random(), menu_volume_db)


func _on_picked_up(_flag_picked_up: Node3D) -> void:
	_play(pickup, pickup_volume_db)


## dropped comes before the flag decides to stick or disappear -> check a moment later
func _on_dropped(_flag_dropped: Node3D) -> void:
	_play_drop_if_stuck.call_deferred()


func _play_drop_if_stuck() -> void:
	if _flag.freeze and not _flag.is_queued_for_deletion():
		_play(drop, drop_volume_db)


func _play(sound: AudioStream, volume_db: float) -> void:
	if sound == null:
		return
	_voice.stream = sound
	_voice.volume_db = volume_db
	_voice.pitch_scale = randf_range(PITCH_RANGE.x, PITCH_RANGE.y)
	_voice.play()
