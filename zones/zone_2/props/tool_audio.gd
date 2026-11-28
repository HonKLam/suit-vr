class_name ToolAudio
extends Node3D
## Tool sounds (shovel, metal detector). Add as a direct child of the XRToolsPickable.
## - Pickup: when the tool is grabbed.
## - Bring: the tool menu shows the tool in front of the player (menu sound + appear sound).
## - Put away: the tool goes back into the menu (menu sound), e.g. when it is let go.
## The tool menu shows and hides the tool, so this listens to its visibility.

const PITCH_RANGE := Vector2(0.92, 1.08)
const UNIT_SIZE: float = 2.0
const MAX_DISTANCE: float = 30.0
const VOICES: int = 3

@export_group("Sounds")
@export var pickup_sounds: Array[AudioStream] = []
## The tool appears in front of the player
@export var appear_sounds: Array[AudioStream] = []
## Bringing and putting away
@export var menu_sounds: Array[AudioStream] = []

@export_group("Volume")
@export_range(-30.0, 12.0, 0.5) var pickup_volume_db: float = -10.0
@export_range(-30.0, 12.0, 0.5) var appear_volume_db: float = -12.0
@export_range(-30.0, 12.0, 0.5) var menu_volume_db: float = -8.0

var _tool: XRToolsPickable
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _last_sound_index: Dictionary = {} # sound kind -> index of the last sound played
var _is_out_of_menu: bool = false # the first hide at the start is silent


func _ready() -> void:
	_tool = get_parent() as XRToolsPickable
	assert(_tool != null, "ToolAudio must be a direct child of an XRToolsPickable.")
	_tool.picked_up.connect(_on_picked_up)
	_tool.visibility_changed.connect(_on_visibility_changed)
	for i in VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.unit_size = UNIT_SIZE
		voice.max_distance = MAX_DISTANCE
		add_child(voice)
		_voices.append(voice)


func _on_picked_up(_pickable: Node3D) -> void:
	_play(_pick("pickup", pickup_sounds), pickup_volume_db)


func _on_visibility_changed() -> void:
	if _tool.visible:
		_is_out_of_menu = true
		_play(_pick("menu", menu_sounds), menu_volume_db)
		_play(_pick("appear", appear_sounds), appear_volume_db)
	elif _is_out_of_menu:
		_is_out_of_menu = false
		_play(_pick("menu", menu_sounds), menu_volume_db)


func _play(sound: AudioStream, volume_db: float) -> void:
	if sound == null:
		return
	var voice: AudioStreamPlayer3D = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = sound
	voice.volume_db = volume_db
	voice.pitch_scale = randf_range(PITCH_RANGE.x, PITCH_RANGE.y)
	voice.play()


## Random sound, never the same one twice in a row.
func _pick(sound_kind: String, sounds: Array[AudioStream]) -> AudioStream:
	if sounds.is_empty():
		return null
	var sound_index: int = randi() % sounds.size()
	if sounds.size() > 1 and sound_index == _last_sound_index.get(sound_kind, -1):
		sound_index = (sound_index + 1) % sounds.size()
	_last_sound_index[sound_kind] = sound_index
	return sounds[sound_index]
