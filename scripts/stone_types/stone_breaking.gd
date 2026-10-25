@tool
extends Stone

@export var timer_time: int = 5
@onready var timer: Timer = Timer.new()

var _breaking: bool = false

func can_pick_up(by: Node3D) -> bool:
	return not _breaking and super(by)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	timer.wait_time = timer_time
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func on_grabbed() -> void:
	super()
	print("starting timer")
	timer.start()

func _on_timer_timeout() -> void:
	_breaking = true
	queue_free()
	pass
