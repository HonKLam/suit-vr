@tool
extends Hold

## Seconds until the hold breaks, per 100 cm² of its front area: bigger holds last longer.
@export var seconds_per_100_cm2: float = 3.5
## Fragile holds break almost instantly. They already look half crumbled
## and drop a crumb now and then, so the player can see it.
@export var fragile: bool = false

const FRAGILE_TIME := 0.5
const FRAGILE_LOOK := 0.6

var _breaking: bool = false
@onready var _crumble: HoldCrumble = $HoldCrumble

func can_pick_up(by: Node3D) -> bool:
	return not _breaking and super(by)

func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	if fragile:
		_crumble.crumble_time = FRAGILE_TIME
		_crumble.start_look = FRAGILE_LOOK
	else:
		_crumble.crumble_time = _front_area_cm2() / 100.0 * seconds_per_100_cm2
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

## Front area of the model (its X/Y extent, the hold faces +Z) in cm².
func _front_area_cm2() -> float:
	var model := $Model as MeshInstance3D
	var size := model.get_aabb().size * model.global_basis.get_scale()
	return size.x * size.y * 10000.0
