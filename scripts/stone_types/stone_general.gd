@tool
class_name Stone
extends XRToolsClimbable

signal both_hands_grabbed(by: Stone)

@export var two_hands_allowed: bool = false
@export var fling_boost_allowed: bool = false

var _holders: Array[Node3D] = []

func _ready() -> void:
	add_to_group("stones")

func _update() -> void:
	pass

func pick_up(by: Node3D) -> void:
	super(by)
	_holders.append(by)
	if _holders.size() == 2:
		both_hands_grabbed.emit(self)

func let_go(by: Node3D, _p_linear_velocity: Vector3, _p_angular_velocity: Vector3) -> void:
	super(by, _p_linear_velocity, _p_angular_velocity)
	_holders.erase(by)

func can_pick_up(by: Node3D) -> bool:
	if _holders.is_empty():
		return super(by)
	if two_hands_allowed == true:
		return super(by)
	return false
	
func on_grabbed(hand: String):
	pass
		
	
