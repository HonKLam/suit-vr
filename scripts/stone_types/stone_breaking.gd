@tool
extends Stone

## Sekunden vom Greifen bis der Stein zerbricht.
@export var timer_time: float = 5

var _breaking: bool = false
@onready var _crumble: GriffCrumble = $GriffCrumble

func can_pick_up(by: Node3D) -> bool:
	return not _breaking and super(by)

func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_crumble.crumble_time = timer_time
	_crumble.crumbled.connect(_on_crumbled)
	_crumble.finished.connect(queue_free)

func on_grabbed() -> void:
	super()
	_crumble.grab()

func _on_crumbled() -> void:
	_breaking = true
	# Without a proper drop, the climbing code would not switch to the other hand.
	for hand in holders.duplicate():
		hand.drop_object()
