@tool
class_name GameScene
extends XRToolsSceneBase
## Base of every playable scene: player, countdown, pause menu and round end.
## A zone inherits game_scene.tscn and adds its sky, sun and a ZoneMap child named "Map".

enum State { COUNTDOWN, PLAYING, PAUSED, WON, LOST }

## 0 = start right away, without countdown or "GO!".
@export var countdown_seconds: int = 3

var state: State = State.COUNTDOWN
var time_left: float
var wrist_menu: WristMenu

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
	if countdown_seconds <= 0:
		return
	status_label.text = "GO!"
	await get_tree().create_timer(1.0).timeout
	status_label.text = ""

func _set_paused(paused: bool) -> void:
	state = State.PAUSED if paused else State.PLAYING
	player.set_frozen(paused)
	player.set_menu_open(paused)
	map.set_paused(paused)
	if paused:
		wrist_menu.show_menu("Paused", true)
	else:
		_show_status()

func _end_round(new_state: State, text: String) -> void:
	state = new_state
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
	if button != "menu_button":
		return
	if state == State.PLAYING:
		_set_paused(true)
	elif state == State.PAUSED:
		_set_paused(false)

func _on_lobby_pressed() -> void:
	pass # TODO: no lobby yet
