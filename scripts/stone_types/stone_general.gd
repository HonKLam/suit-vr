@tool
class_name Stone
extends XRToolsClimbable

signal both_hands_grabbed(by: Stone)
signal one_hand_grabbed(by: Stone)

@export var two_hands_allowed: bool = false:
	set(value):
			two_hands_allowed = value
			notify_property_list_changed() # refresh the inspector

@export var fling_boost_allowed: bool = false

func _validate_property(property: Dictionary) -> void:
	if property.name == "fling_boost_allowed" and not two_hands_allowed:
		property.usage = PROPERTY_USAGE_NO_EDITOR

## Pickup-Nodes der Hände, die den Stein gerade halten (liest GriffCrumble für die Vibration).
var holders: Array[Node3D] = []

func _ready() -> void:
	add_to_group("stones")

func _update() -> void:
	pass

func pick_up(by: Node3D) -> void:
	super(by)
	holders.append(by)
	if holders.size() == 1:
		on_grabbed()
		one_hand_grabbed.emit(self)
	if holders.size() == 2:
		both_hands_grabbed.emit(self)

func let_go(by: Node3D, _p_linear_velocity: Vector3, _p_angular_velocity: Vector3) -> void:
	super(by, _p_linear_velocity, _p_angular_velocity)
	holders.erase(by)

func can_pick_up(by: Node3D) -> bool:
	if holders.is_empty():
		return super(by)
	if two_hands_allowed == true:
		return super(by)
	return false
	
func on_grabbed():
	pass
		
	
