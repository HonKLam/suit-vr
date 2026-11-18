class_name Bomb
extends Node3D
## The bomb: flap on the hinge, countdown on the timer display.
## - start_countdown() / stop_countdown()
## - open_flap() / close_flap()
## - time_up fires when the timer reaches 00:00

signal time_up

## Countdown length (s)
@export var countdown_seconds: float = 300.0
## Starts the countdown as soon as the bomb is in the scene
@export var autostart: bool = false
## How far the flap opens (degrees) and how long it takes (s)
@export var flap_open_angle: float = 100.0
@export var flap_open_time: float = 1.2
## Last seconds: the display blinks
@export var blink_below_seconds: float = 10.0

@onready var _flap: Node3D = $Model/Flap
@onready var _display: Label3D = $TimerLabel

var time_left: float = 0.0
var is_running: bool = false
var is_flap_open: bool = false
var _flap_tween: Tween


func _ready() -> void:
	time_left = countdown_seconds
	_show_time()
	if autostart:
		start_countdown()


func _process(delta: float) -> void:
	if not is_running:
		return
	time_left = maxf(time_left - delta, 0.0)
	_show_time()
	if time_left <= 0.0:
		is_running = false
		time_up.emit()


func start_countdown(seconds: float = -1.0) -> void:
	if seconds >= 0.0:
		time_left = seconds
	is_running = true


func stop_countdown() -> void:
	is_running = false
	_display.visible = true


func open_flap() -> void:
	is_flap_open = true
	_turn_flap(deg_to_rad(flap_open_angle))


func close_flap() -> void:
	is_flap_open = false
	_turn_flap(0.0)


func _turn_flap(angle: float) -> void:
	if _flap_tween:
		_flap_tween.kill()
	_flap_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flap_tween.tween_property(_flap, "rotation:x", angle, flap_open_time)


## MM:SS, rounded up (shows 00:01 until the very end)
func _show_time() -> void:
	var whole_seconds := int(ceil(time_left))
	_display.text = "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]
	var blinking := is_running and time_left < blink_below_seconds
	_display.visible = not blinking or fmod(time_left, 0.5) > 0.25
