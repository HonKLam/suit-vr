class_name MetalObject
extends Node3D
## Marks something as metal for the metal detector (e.g. bomb, can, coin).
## Add as a child of the buried object.

const GROUP := "metal"

## Signal strength 0..1. Similar values make it harder to tell the bomb from decoys.
@export_range(0.0, 1.0, 0.05) var strength := 1.0


func _enter_tree() -> void:
	add_to_group(GROUP)
