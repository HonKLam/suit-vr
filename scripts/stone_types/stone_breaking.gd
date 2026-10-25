@tool
extends Stone

@export var timer_time: int = 5
@onready var timer: Timer = Timer.new()

var _breaking: bool = false
var _crumble: GriffCrumble # optionaler Zerfall-Effekt (Kind-Node "GriffCrumble")

func can_pick_up(by: Node3D) -> bool:
	return not _breaking and super(by)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	timer.wait_time = timer_time
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)
	if Engine.is_editor_hint():
		return
	for c in get_children():
		if c is GriffCrumble:
			_crumble = c
			_crumble.crumble_time = timer_time # Effekt läuft synchron zum Timer
			_crumble.auto_break = false # zerbrechen tut der Timer

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func on_grabbed(hand: String) -> void:
	super(hand)
	if timer.is_stopped() and not _breaking: # zweite Hand startet den Timer nicht neu
		print("starting timer")
		timer.start()
	if _crumble:
		_crumble.grab()

func _on_timer_timeout() -> void:
	_breaking = true
	if _crumble:
		_crumble.break_now() # Brocken + Staub fliegen, Griff weg
	queue_free()
	pass
