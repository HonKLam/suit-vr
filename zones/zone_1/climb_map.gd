@tool
class_name ClimbMap
extends ZoneMap
## Climbing rules: lava rises to the win area over time_limit seconds. Touching the lava loses,
## reaching the win area wins.

## Turn off to test a level without the lava rising.
@export var lava_rises: bool = true

@onready var lava: Lava = get_node_or_null("Lava")
@onready var win_area: WinArea = get_node_or_null("WinArea")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for hold: Hold in get_tree().get_nodes_in_group("holds"):
		if is_ancestor_of(hold):
			hold.one_hand_grabbed.connect(_on_one_hand_grabbed)
			hold.both_hands_grabbed.connect(_on_both_hands_grabbed)
	lava.player_fell.connect(lost.emit)
	win_area.player_win.connect(won.emit)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not get_node_or_null("Lava"):
		warnings.append("Missing child \"Lava\" (zones/zone_1/lava/lava.tscn).")
	if not get_node_or_null("WinArea"):
		warnings.append("Missing child \"WinArea\" (zones/zone_1/win_area.tscn).")
	return warnings

func start() -> void:
	if lava_rises:
		lava.start_rising(win_area.global_position.y, time_limit)

func stop() -> void:
	lava.stop_rising()

func set_paused(paused: bool) -> void:
	lava.set_rising_paused(paused)
	get_tree().call_group(HoldCrumble.GROUP, "set_process", not paused)

func _on_one_hand_grabbed(_by: Hold) -> void:
	player.set_fling_boost(1.0)

func _on_both_hands_grabbed(by: Hold) -> void:
	if by.fling_boost_allowed:
		player.set_fling_boost(1.5)
