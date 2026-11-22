class_name MetalObject
extends Node3D
## Marks something as metal for the metal detector (e.g. bomb, can, coin).
## Add as a child of the buried object.

const GROUP := "metal"


func _enter_tree() -> void:
	add_to_group(GROUP)
