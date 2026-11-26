@tool
extends ZoneMap
## Hot wire: thread the ring onto the green start of the wire and carry it to the red end.
## Touching the wire, slipping off it or letting go of the ring loses.
## - Too close to the wire: both controllers pulse fast at full strength.
## - Halfway along the wire the guide says halfway_voice.

const IDLE_COLOR: Color = Color(0.9, 0.9, 0.9)
const ARMED_COLOR: Color = Color(0.2, 0.9, 0.3)
const LOST_COLOR: Color = Color(0.9, 0.15, 0.1)

## Length at both ends of the wire where touching doesn't count.
@export var safe_length: float = 0.3
## Must match the polygon of Wire/Mesh.
@export var wire_radius: float = 0.01
## Gap between ring and wire (m) below which the controllers pulse
@export var danger_distance: float = 0.025
## Pulses per second when too close
@export var danger_pulse_rate: float = 20.0
## Guide's line when the ring is halfway
@export var halfway_voice: AudioStream

var _points: PackedVector3Array # whole wire, global
var _hot_points: PackedVector3Array # without the safe ends
var _safe_count: int
var _running: bool = false
var _armed: bool = false
var _halfway_said: bool = false
var _pulse_clock: float = 0.0

@onready var ring: HotRing = $Ring
@onready var wire: Path3D = $Wire


func _ready() -> void:
	_place_markers()
	if Engine.is_editor_hint():
		wire.curve_changed.connect(_place_markers) # markers follow live while editing the route
		return
	ring.set_process(false) # controllers are only known in start()
	ring.visible = false
	_points = wire.global_transform * wire.curve.get_baked_points()
	_safe_count = int(safe_length / wire.curve.get_baked_length() * _points.size())
	_hot_points = _points.slice(_safe_count, _points.size() - _safe_count)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _running:
		return
	if not ring.held:
		if _armed:
			_lose()
		return
	var segment: int = ring.threaded_segment(_points)
	if not _armed:
		_armed = segment >= 0 and segment < _safe_count
		ring.set_color(ARMED_COLOR if _armed else IDLE_COLOR)
	elif segment < 0 or ring.touches(_hot_points, wire_radius):
		_lose()
	elif segment >= _points.size() - 1 - _safe_count:
		won.emit()
	else:
		_warn_if_too_close(delta)
		if not _halfway_said and segment >= _points.size() / 2:
			_halfway_said = true
			_say(halfway_voice)


## Full-strength fast pulses on both controllers while the ring is closer than danger_distance.
func _warn_if_too_close(delta: float) -> void:
	if _closest_gap() >= danger_distance:
		_pulse_clock = 0.0
		return
	_pulse_clock += delta * danger_pulse_rate
	if fmod(_pulse_clock, 1.0) < 0.5: # on half of each pulse
		var pulse_length := 0.5 / danger_pulse_rate
		Haptics.pulse(ring.left, 1.0, pulse_length)
		Haptics.pulse(ring.right, 1.0, pulse_length)


## Smallest gap between the ring's tube and the wire surface.
func _closest_gap() -> float:
	var to_local: Transform3D = ring.global_transform.affine_inverse()
	var best := INF
	for point: Vector3 in _hot_points:
		var p: Vector3 = to_local * point
		best = minf(best, Vector2(Vector2(p.x, p.z).length() - ring.radius, p.y).length())
	return best - ring.tube_radius - wire_radius


func _say(line: AudioStream) -> void:
	var game := get_parent() as GameScene
	if game and line:
		game.narrator.say(line)


## Middle of the safe section at each end of the wire.
func _place_markers() -> void:
	var length: float = wire.curve.get_baked_length()
	$StartMarker.global_position = wire.to_global(wire.curve.sample_baked(safe_length / 2.0))
	$EndMarker.global_position = wire.to_global(wire.curve.sample_baked(length - safe_length / 2.0))


func start() -> void:
	ring.left = player.get_node("XRController3D_left")
	ring.right = player.get_node("XRController3D_right")
	ring.set_process(true)
	_running = true


func stop() -> void:
	_running = false


## Pausing drops the ring: after resuming, start again at the green end.
func set_paused(paused: bool) -> void:
	_running = not paused
	_armed = false
	ring.set_color(IDLE_COLOR)


func _lose() -> void:
	_running = false
	ring.set_color(LOST_COLOR)
	Haptics.pulse(ring.left, 1.0, 0.4)
	Haptics.pulse(ring.right, 1.0, 0.4)
	lost.emit()
