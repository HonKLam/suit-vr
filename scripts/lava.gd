class_name Lava
extends Area3D

signal player_fell

var _rise_tween: Tween

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

## Raises the lava to [param target_y] (global) over [param duration] seconds.
func start_rising(target_y: float, duration: float) -> void:
	_rise_tween = create_tween()
	_rise_tween.tween_property(self, "global_position:y", target_y, duration)

func stop_rising() -> void:
	if _rise_tween:
		_rise_tween.kill()

func set_rising_paused(paused: bool) -> void:
	if not _rise_tween:
		return
	if paused:
		_rise_tween.pause()
	else:
		_rise_tween.play()

func _on_body_entered(body: Node3D) -> void:
	if body is XRToolsPlayerBody:
		player_fell.emit()
