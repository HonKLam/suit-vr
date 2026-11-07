class_name HoldAudio
extends Node3D
## Sounds for climbing holds. Add as a direct child of a Hold.
## - Grab: short crunch (for every hand).
## If the Hold also has a HoldCrumble, it adds:
## - Crumbling: scraping + trickling crumbs, gets louder and higher with progress.
## - Warning phase (HoldCrumble.SHAKE_TIME): crackling.
## - Breaking: crash + rubble. Afterwards the chunks sizzle in the lava (LavaAudio).

@export var grab_sounds: Array[AudioStream] = []
@export_range(-30.0, 12.0, 0.5) var grab_volume_db := -4.0

@export_group("Crumbling")
@export var grind_loop: AudioStream
## Volume at the start / right before breaking.
@export var grind_volume_db := Vector2(-20.0, -4.0)
@export var grind_pitch := Vector2(0.9, 1.15)
@export var trickle_loop: AudioStream
@export var trickle_volume_db := Vector2(-26.0, -6.0)
## Crumbs start trickling from this progress (0..1).
@export_range(0.0, 1.0, 0.05) var trickle_start := 0.2
@export var crackles: Array[AudioStream] = []
## Crackles per second in the warning phase.
@export_range(0.0, 30.0, 0.5) var crackle_rate := 9.0
@export_range(-30.0, 12.0, 0.5) var crackle_volume_db := -6.0

@export_group("Breaking")
@export var break_sounds: Array[AudioStream] = []
@export_range(-30.0, 12.0, 0.5) var break_volume_db := 0.0
## Chunks sizzle in the lava if there is a LavaAudio in the scene.
@export var lava_sizzle := true

@export_group("Space")
@export_range(0.1, 10.0, 0.1) var unit_size := 1.5
@export_range(1.0, 100.0, 1.0) var max_distance := 30.0

var _crumble: HoldCrumble
var _grab: AudioStreamPlayer3D
var _grind: AudioStreamPlayer3D
var _trickle: AudioStreamPlayer3D
var _crackle: AudioStreamPlayer3D
var _crackle_accum := 0.0
@onready var _hold := get_parent() as Hold


func _ready() -> void:
	assert(_hold != null, "HoldAudio must be a direct child of a Hold.")
	set_process(false)
	_hold.one_hand_grabbed.connect(_on_grabbed.unbind(1))
	_hold.both_hands_grabbed.connect(_on_grabbed.unbind(1))
	for c in _hold.get_children():
		if c is HoldCrumble:
			_crumble = c
			_crumble.crumbled.connect(_on_crumbled)


func _on_grabbed() -> void:
	if _grab == null: # only created on the first grab, the wall has many holds
		_grab = _player()
		_crackle = _player()
		_grind = _player(grind_loop)
		_trickle = _player(trickle_loop)
	_grab.stream = grab_sounds.pick_random() if not grab_sounds.is_empty() else null
	_grab.volume_db = grab_volume_db
	_grab.pitch_scale = randf_range(0.9, 1.1)
	if _grab.stream:
		_grab.play()
	if _crumble and not is_processing():
		set_process(true)


func _process(delta: float) -> void:
	if _crumble.state != HoldCrumble.State.CRUMBLING:
		return
	# Game paused: HoldCrumble stops processing, the loops pause with it.
	var paused := not _crumble.is_processing()
	_grind.stream_paused = paused
	_trickle.stream_paused = paused
	if paused:
		return
	var p := _crumble.progress
	_loop_at(_grind, p, grind_volume_db)
	_grind.pitch_scale = lerpf(grind_pitch.x, grind_pitch.y, p)
	_loop_at(_trickle, clampf((p - trickle_start) / maxf(1.0 - trickle_start, 0.001), 0.0, 1.0),
		trickle_volume_db, p >= trickle_start)

	var remaining := (1.0 - p) * _crumble.crumble_time
	if crackles.is_empty() or remaining > HoldCrumble.SHAKE_TIME:
		return
	_crackle_accum += delta * crackle_rate
	if _crackle_accum >= 1.0:
		_crackle_accum = 0.0
		_crackle.stream = crackles.pick_random()
		_crackle.volume_db = crackle_volume_db + randf_range(-4.0, 0.0)
		_crackle.pitch_scale = randf_range(0.85, 1.25)
		_crackle.play()


func _on_crumbled() -> void:
	set_process(false)
	for p in [_grind, _trickle]:
		if p:
			p.stop()
	var at := global_position
	if not break_sounds.is_empty():
		_one_shot(break_sounds.pick_random(), at)
	var lava := get_tree().get_first_node_in_group("lava_audio") as LavaAudio
	if lava_sizzle and lava:
		var h := at.y - lava.surface_y()
		if h > 0.0:
			# Fall time of the chunks (they fly up briefly first)
			get_tree().create_timer(sqrt(2.0 * h / 9.8) + 0.3).timeout.connect(lava.play_sizzle.bind(at))


## Loop plays with a volume between db.x (t=0) and db.y (t=1).
func _loop_at(p: AudioStreamPlayer3D, t: float, db: Vector2, on := true) -> void:
	if p.stream == null:
		return
	if on and not p.playing:
		p.play(randf() * p.stream.get_length())
	p.volume_db = lerpf(db.x, db.y, t * t)


func _player(s: AudioStream = null) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.unit_size = unit_size
	p.max_distance = max_distance
	if s is AudioStreamWAV and s.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	add_child(p)
	return p


## Keeps playing independently of the hold (it frees itself after breaking).
func _one_shot(s: AudioStream, at: Vector3) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = break_volume_db
	p.pitch_scale = randf_range(0.9, 1.1)
	p.unit_size = unit_size * 1.5
	p.max_distance = max_distance
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	host.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
