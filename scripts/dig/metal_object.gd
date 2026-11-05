class_name MetalObject
extends Node3D
## Markiert etwas als metallisch für den Metalldetektor (z.B. Bombe, Dose, Münze).
## Einfach als Kind an das vergrabene Objekt hängen.

const GROUP := "metal"

## Signalstärke 0..1. Ähnliche Werte machen es schwerer, die Bombe von Störobjekten zu unterscheiden.
@export_range(0.0, 1.0, 0.05) var strength := 1.0


func _enter_tree() -> void:
	add_to_group(GROUP)
