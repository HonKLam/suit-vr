class_name Bomb
extends Node3D
## The bomb: flap on the hinge, timer display (SS:CC, seconds and hundredths).
## - show_time(seconds): the countdown itself runs in DigFinds, the bomb only shows it
## - open_flap() / close_flap()

## How far the flap opens (degrees) and how long it takes (s)
@export var flap_open_angle: float = 100.0
@export var flap_open_time: float = 1.2
## Last seconds: the display blinks
@export var blink_below_seconds: float = 10.0

@onready var _flap: Node3D = $Model/Flap
@onready var _timer_label: Label3D = $TimerLabel

var is_flap_open: bool = false
var _flap_tween: Tween


## SS:CC, at most 99:99. Blinks in the last seconds while the time is running.
func show_time(seconds: float, is_running: bool = true) -> void:
	var hundredths := clampi(int(seconds * 100.0), 0, 9999)
	_timer_label.text = "%02d:%02d" % [hundredths / 100, hundredths % 100]
	var is_blinking := is_running and seconds < blink_below_seconds
	_timer_label.visible = not is_blinking or fmod(seconds, 0.5) > 0.25


func open_flap() -> void:
	is_flap_open = true
	_rotate_flap_to(deg_to_rad(flap_open_angle))


func close_flap() -> void:
	is_flap_open = false
	_rotate_flap_to(0.0)


func _rotate_flap_to(angle: float) -> void:
	if _flap_tween:
		_flap_tween.kill()
	_flap_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flap_tween.tween_property(_flap, "rotation:x", angle, flap_open_time)
