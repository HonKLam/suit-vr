class_name LavaAudio
extends AudioStreamPlayer3D
## Lava-Sound. Als Kind des Lava-Nodes einhängen.
## - Brodel-Loop (stream): rutscht auf der Oberfläche immer unter den Spieler,
##   damit die Lava von unten klingt. Je höher man klettert, desto leiser.
## - Blubb-Sounds (blobs): spielen zufällig an Stellen rund um den Spieler.

## Halbe Größe der Lavafläche (m, lokal). Sounds bleiben innerhalb dieser Fläche.
@export var half_extent := Vector2(13, 13)
## Höhe der Oberfläche relativ zum Lava-Node (m).
@export var surface_height := 0.2
## Wie schnell der Loop dem Spieler folgt (höher = direkter).
@export_range(0.5, 20.0, 0.5) var follow_speed := 4.0

@export_group("Blubb")
@export var blobs: Array[AudioStream] = []
## Zufällige Pause zwischen zwei Blubbs (Sekunden, min/max).
@export var blob_interval := Vector2(1.5, 4.0)
## In diesem Umkreis (m) um den Punkt unter dem Spieler blubbert es.
@export_range(1.0, 15.0, 0.5) var blob_radius := 6.0
@export_range(-30.0, 12.0, 0.5) var blob_volume_db := -8.0
## Zufällige Tonhöhe (min/max), damit sich die Blubbs nie gleich anhören.
@export var blob_pitch := Vector2(0.85, 1.2)
@export_range(1, 8) var blob_voices := 4

var _snapped := false
var _blob_timer := 0.0
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _last_blob := -1
@onready var _lava := get_parent() as Node3D


func _ready() -> void:
	var wav := stream as AudioStreamWAV
	if wav and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	elif stream and not wav:
		finished.connect(play)
	play()
	for i in blob_voices:
		var p := AudioStreamPlayer3D.new()
		p.top_level = true
		p.unit_size = unit_size
		p.max_distance = max_distance
		p.bus = bus
		add_child(p)
		_voices.append(p)
	_blob_timer = randf_range(blob_interval.x, blob_interval.y)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _lava == null:
		return
	var local := _lava.to_local(cam.global_position)
	var target := _lava.to_global(_on_surface(local.x, local.z))
	if not _snapped:
		global_position = target
		_snapped = true
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-follow_speed * delta))

	_blob_timer -= delta
	if _blob_timer <= 0.0:
		_blob_timer = randf_range(blob_interval.x, blob_interval.y)
		_play_blob(local)


func _on_surface(x: float, z: float) -> Vector3:
	return Vector3(clampf(x, -half_extent.x, half_extent.x), surface_height,
		clampf(z, -half_extent.y, half_extent.y))


func _play_blob(player_local: Vector3) -> void:
	if blobs.is_empty() or _voices.is_empty():
		return
	var i := randi() % blobs.size()
	if blobs.size() > 1 and i == _last_blob:
		i = (i + 1) % blobs.size()
	_last_blob = i
	var off := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * blob_radius
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.global_position = _lava.to_global(_on_surface(player_local.x + off.x, player_local.z + off.y))
	p.stream = blobs[i]
	p.volume_db = blob_volume_db
	p.pitch_scale = randf_range(blob_pitch.x, blob_pitch.y)
	p.play()
