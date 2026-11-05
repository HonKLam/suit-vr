class_name Win
extends Area3D

signal player_win

func _on_body_entered(body: Node3D) -> void:
	if body is XRToolsPlayerBody:
		player_win.emit()
