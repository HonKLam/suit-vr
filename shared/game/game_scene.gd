@tool
class_name GameScene
extends XRToolsSceneBase
## Base of every playable scene: player, countdown, pause menu, round end and the guide's voice.
## The intro can be skipped with A/X or B/Y (hint below the view while it plays).
## A zone inherits game_scene.tscn and adds its sky, sun and a ZoneMap child named "Map".

enum State { COUNTDOWN, PLAYING, PAUSED, WON, LOST }

const SKIP_BUTTONS: Array[String] = ["ax_button", "by_button"]
const SKIP_HINT_TEXT := "A / X: Tutorial überspringen"

## The intro text is over (also fires right away when there is no intro).
signal intro_finished

## 0 = start right away, without countdown or "GO!".
@export var countdown_seconds: int = 3
## Spoken intro of the guide.
@export var intro_voice: AudioStream
## On: intro plays before the countdown (player frozen). Off: intro plays after "GO!" (player can move).
@export var intro_before_start: bool = true

var state: State = State.COUNTDOWN
var time_left: float
var wrist_menu: WristMenu
var narrator: Narrator
var _intro_playing: bool = false

@onready var map: ZoneMap = get_node_or_null("Map")
@onready var player: Player = $XROrigin3D
@onready var status_label: Label3D = $StatusLabel
@onready var wrist_screen: XRToolsViewport2DIn3D = $XROrigin3D/XRController3D_left/WristMenu

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	map.player = player
	map.lost.connect(_on_map_lost)
	map.won.connect(_on_map_won)
	$XROrigin3D/XRController3D_left.button_pressed.connect(_on_button_pressed)
	$XROrigin3D/XRController3D_right.button_pressed.connect(_on_button_pressed)
	wrist_menu = wrist_screen.get_scene_instance()
	wrist_menu.resume_pressed.connect(_set_paused.bind(false))
	wrist_menu.restart_pressed.connect(reset_scene)
	wrist_menu.lobby_pressed.connect(_on_lobby_pressed)
	time_left = map.time_limit
	narrator = Narrator.new()
	narrator.name = "Narrator"
	add_child(narrator)
	_show_status()
	player.set_frozen(true)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if state == State.PLAYING and map.time_limit > 0.0:
		time_left = maxf(time_left - delta, 0.0)
		_show_status()

# Called by staging once the fade-in is done, so the countdown isn't missed.
func scene_visible(user_data = null) -> void:
	super(user_data)
	if intro_before_start:
		await _play_intro()
		intro_finished.emit()
	_run_countdown()

func _run_countdown() -> void:
	for i in range(countdown_seconds, 0, -1):
		status_label.text = str(i)
		await get_tree().create_timer(1.0).timeout
	_start_round()

func _start_round() -> void:
	state = State.PLAYING
	player.set_frozen(false)
	map.start()
	if not intro_before_start:
		_play_intro_after_start()
	if countdown_seconds <= 0:
		return
	status_label.text = "GO!"
	await get_tree().create_timer(1.0).timeout
	status_label.text = ""

func _play_intro_after_start() -> void:
	await _play_intro()
	intro_finished.emit()

## Plays the intro with the skip hint below the view.
func _play_intro() -> void:
	if intro_voice == null:
		return
	var skip_hint := Label3D.new()
	skip_hint.text = SKIP_HINT_TEXT
	skip_hint.pixel_size = 0.0008
	skip_hint.font_size = 32
	skip_hint.outline_size = 8
	skip_hint.modulate = Color(1.0, 1.0, 1.0, 0.8)
	skip_hint.no_depth_test = true
	skip_hint.position = Vector3(0.0, -0.22, -0.7) # below the middle of the view
	$XROrigin3D/XRCamera3D.add_child(skip_hint)
	_intro_playing = true
	await narrator.say_and_wait(intro_voice)
	_intro_playing = false
	skip_hint.queue_free()

func _set_paused(paused: bool) -> void:
	state = State.PAUSED if paused else State.PLAYING
	narrator.stream_paused = paused
	player.set_frozen(paused)
	player.set_menu_open(paused)
	map.set_paused(paused)
	if paused:
		wrist_menu.show_menu("Paused", true)
	else:
		_show_status()

func _end_round(new_state: State, text: String) -> void:
	state = new_state
	narrator.stop_all()
	map.stop()
	player.set_frozen(true)
	player.set_menu_open(true)
	wrist_menu.show_menu(text, false)

func _show_status() -> void:
	if map.time_limit > 0.0:
		wrist_menu.show_time(time_left)
	else:
		wrist_menu.show_status("")

func _on_map_lost() -> void:
	if state == State.PLAYING:
		_end_round(State.LOST, "Game Over!")

func _on_map_won() -> void:
	if state == State.PLAYING:
		_end_round(State.WON, "You win!")

func _on_button_pressed(button: String) -> void:
	if _intro_playing and button in SKIP_BUTTONS:
		narrator.skip()
		return
	if button != "menu_button":
		return
	if state == State.PLAYING:
		_set_paused(true)
	elif state == State.PAUSED:
		_set_paused(false)

func _on_lobby_pressed() -> void:
	pass # TODO: no lobby yet
