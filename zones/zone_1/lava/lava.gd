@tool
class_name Lava
extends Area3D

signal player_fell

## Radius of the round lava pool (m).
@export var radius := 13.0:
	set(value):
		radius = value
		if is_node_ready():
			_apply_radius()
## Radius when the lava has risen to the top. Smaller than [member radius] if the pit gets
## narrower upwards, so the pool keeps filling it.
@export var end_radius := 13.0

var _rise_tween: Tween

func _ready() -> void:
	_apply_radius()

## Raises the lava to [param target_y] (global) over [param duration] seconds.
func start_rising(target_y: float, duration: float) -> void:
	_rise_tween = create_tween().set_parallel()
	_rise_tween.tween_property(self, "global_position:y", target_y, duration)
	_rise_tween.tween_property(self, "radius", end_radius, duration)

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

func _apply_radius() -> void:
	var mesh := $Mesh.mesh as CylinderMesh
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	($CollisionShape3D.shape as CylinderShape3D).radius = radius

func _on_body_entered(body: Node3D) -> void:
	if body is XRToolsPlayerBody:
		player_fell.emit()
