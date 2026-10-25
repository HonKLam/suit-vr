@tool
class_name GameSceneBase
extends XRToolsSceneBase

enum State { COUNTDOWN, PLAYING, PAUSED, WON, LOST }

@export var rise_time: float = 60.0
@export var countdown_seconds: int = 3
## Turn off to test a level without the lava rising.
@export var lava_rises: bool = true

var state: State = State.COUNTDOWN
var time_left: float
var wrist_menu: WristMenu

@onready var map: Map = $Map
@onready var player: Player = $XROrigin3D
@onready var movement_climb: XRToolsMovementClimb = $XROrigin3D/MovementClimb
@onready var status_label: Label3D = $StatusLabel
@onready var wrist_screen: XRToolsViewport2DIn3D = $XROrigin3D/XRController3D_left/WristMenu

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	map.fling_boost_active.connect(player.set_fling_boost.bind(1.5))
	map.fling_boost_inactive.connect(player.set_fling_boost.bind(1.0))
	map.player_fell.connect(_on_player_fell)
	map.player_won.connect(_on_player_won)
	$XROrigin3D/XRController3D_left.button_pressed.connect(_on_button_pressed)
	$XROrigin3D/XRController3D_right.button_pressed.connect(_on_button_pressed)
	wrist_menu = wrist_screen.get_scene_instance()
	wrist_menu.resume_pressed.connect(_set_paused.bind(false))
	wrist_menu.restart_pressed.connect(reset_scene)
	wrist_menu.lobby_pressed.connect(_on_lobby_pressed)
	time_left = rise_time
	wrist_menu.show_time(time_left)
	player.set_frozen(true)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if state == State.PLAYING:
		time_left = maxf(time_left - delta, 0.0)
		wrist_menu.show_time(time_left)

# Called by staging once the fade-in is done, so the countdown isn't missed.
func scene_visible(user_data = null) -> void:
	super(user_data)
	_run_countdown()

func _run_countdown() -> void:
	for i in range(countdown_seconds, 0, -1):
		status_label.text = str(i)
		await get_tree().create_timer(1.0).timeout
	status_label.text = "GO!"
	_start_round()

func _start_round() -> void:
	state = State.PLAYING
	player.set_frozen(false)
	if lava_rises:
		map.lava.start_rising(map.win_area.global_position.y, rise_time)
	await get_tree().create_timer(1.0).timeout
	if state == State.PLAYING:
		status_label.text = ""

func _set_paused(paused: bool) -> void:
	state = State.PAUSED if paused else State.PLAYING
	player.set_frozen(paused)
	map.lava.set_rising_paused(paused)
	if paused:
		wrist_menu.show_menu("Paused", true)
	else:
		wrist_menu.show_time(time_left)

func _end_round(new_state: State, text: String) -> void:
	state = new_state
	map.lava.stop_rising()
	player.set_frozen(true)
	var camera = player.get_node("XRCamera3D")
	status_label.global_position = camera.global_position - camera.global_basis.z * 5
	status_label.text = text
	wrist_menu.show_menu(text, false)

func _on_player_fell() -> void:
	if state == State.PLAYING:
		_end_round(State.LOST, "Game Over!")

func _on_player_won() -> void:
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
