@tool
extends ZoneMap
## Hot wire: thread the ring onto the green start of the wire and carry it to the red end.
## The ring waits at the green start; the round starts when you grab it. Letting go is allowed:
## the ring stays where it is. Touching the wire or an obstacle or slipping off the wire loses.
## - Obstacles: the spheres and boxes under Obstacles, so a huge ring doesn't just pass. Move,
##   rotate, scale or duplicate them in the editor (sphere: keep the scale uniform).
## - Closer than warn_distance to the wire or an obstacle: both controllers vibrate, the closer the
##   stronger. Closer than danger_distance: clear on/off pulses at full strength.
## - Halfway along the wire the guide says halfway_voice.

const IDLE_COLOR: Color = Color(0.9, 0.9, 0.9)
const ARMED_COLOR: Color = Color(0.2, 0.9, 0.3)
const LOST_COLOR: Color = Color(0.9, 0.15, 0.1)
## Points on the ring checked against box obstacles
const RING_SAMPLES: int = 64

## Length at both ends of the wire where touching doesn't count.
@export var safe_length: float = 0.3
## Must match the polygon of Wire/Mesh.
@export var wire_radius: float = 0.01
## Gap between ring and wire or obstacle (m) where the vibration starts
@export var warn_distance: float = 0.07
## Steady vibration grows from min to max strength while getting closer
@export_range(0.0, 1.0) var warn_strength_min: float = 0.15
@export_range(0.0, 1.0) var warn_strength_max: float = 0.5
## Gap (m) below which it pulses at full strength
@export var danger_distance: float = 0.03
## Pulses per second; slow enough that on and off are felt apart
@export var danger_pulse_rate: float = 7.0
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
@onready var obstacles: Node3D = $Obstacles


func _ready() -> void:
	_place_markers()
	if Engine.is_editor_hint():
		wire.curve_changed.connect(_place_markers) # markers follow live while editing the route
		return
	ring.set_process(false) # controllers are only known in start()
	_points = wire.global_transform * wire.curve.get_baked_points()
	_safe_count = int(safe_length / wire.curve.get_baked_length() * _points.size())
	_hot_points = _points.slice(_safe_count, _points.size() - _safe_count)
	ring.place(_start_transform())


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _running:
		return
	if not ring.held:
		return # resting: nothing moves, nothing to check
	var segment: int = ring.threaded_segment(_points)
	if not _armed:
		_armed = segment >= 0 and segment < _safe_count
		ring.set_color(ARMED_COLOR if _armed else IDLE_COLOR)
		return
	var gap := _closest_gap()
	if segment < 0 or gap < 0.0:
		_lose()
	elif segment >= _points.size() - 1 - _safe_count:
		won.emit()
	else:
		_warn_if_too_close(gap, delta)
		if not _halfway_said and segment >= _points.size() / 2:
			_halfway_said = true
			_say(halfway_voice)


## Near: steady vibration getting stronger. Too close: full-strength pulses with pauses.
func _warn_if_too_close(gap: float, delta: float) -> void:
	if gap >= warn_distance:
		_pulse_clock = 0.0
		return
	if gap > danger_distance:
		_pulse_clock = 0.0
		var closeness := inverse_lerp(warn_distance, danger_distance, gap)
		_vibrate(lerpf(warn_strength_min, warn_strength_max, closeness), delta * 2.0) # until the next frame
		return
	if _pulse_clock == 0.0 or floorf(_pulse_clock + delta * danger_pulse_rate) > floorf(_pulse_clock):
		_vibrate(1.0, 0.5 / danger_pulse_rate) # one pulse per cycle: on for half, then a felt pause
	_pulse_clock += delta * danger_pulse_rate


func _vibrate(strength: float, duration: float) -> void:
	Haptics.pulse(ring.left, strength, duration)
	Haptics.pulse(ring.right, strength, duration)


## Smallest gap between the ring's tube and the wire or an obstacle (negative = touching).
func _closest_gap() -> float:
	var to_local: Transform3D = ring.global_transform.affine_inverse()
	return minf(_gap_to(_hot_points, to_local) - wire_radius, _obstacle_gap(to_local))


func _gap_to(points: PackedVector3Array, to_local: Transform3D) -> float:
	var best := INF
	for point: Vector3 in points:
		var p: Vector3 = to_local * point
		best = minf(best, Vector2(Vector2(p.x, p.z).length() - ring.radius, p.y).length())
	return best - ring.tube_radius


## Gap between the ring's tube and the obstacles: SphereMesh or BoxMesh of size 1, sized by scale.
func _obstacle_gap(to_local: Transform3D) -> float:
	var circle := PackedVector3Array() # the ring's centre line, global
	for k in RING_SAMPLES:
		var angle := TAU * k / RING_SAMPLES
		circle.append(ring.global_transform * (Vector3(cos(angle), 0, sin(angle)) * ring.radius))
	var best := INF
	for obstacle: MeshInstance3D in obstacles.get_children():
		var half_size: Vector3 = obstacle.global_transform.basis.get_scale() * 0.5
		if obstacle.mesh is SphereMesh:
			var p: Vector3 = to_local * obstacle.global_position
			best = minf(best, Vector2(Vector2(p.x, p.z).length() - ring.radius, p.y).length() - half_size.x)
			continue
		var to_box := Transform3D(obstacle.global_transform.basis.orthonormalized(), obstacle.global_position).affine_inverse()
		for point: Vector3 in circle:
			best = minf(best, _box_distance(to_box * point, half_size))
	return best - ring.tube_radius


## Distance from a point to a box centred at the origin (negative inside).
func _box_distance(p: Vector3, half_size: Vector3) -> float:
	var outside: Vector3 = p.abs() - half_size
	return outside.max(Vector3.ZERO).length() + minf(maxf(outside.x, maxf(outside.y, outside.z)), 0.0)


func _say(line: AudioStream) -> void:
	var game := get_parent() as GameScene
	if game and line:
		game.narrator.say(line)


## On the wire in the middle of the green start, wire through the ring's hole.
func _start_transform() -> Transform3D:
	var index := _safe_count / 2
	var along: Vector3 = (_points[index + 5] - _points[maxi(index - 5, 0)]).normalized()
	var side: Vector3 = along.cross(Vector3.UP).normalized()
	return Transform3D(Basis(side, along, side.cross(along)), _points[index])


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


## Pausing drops the ring where it is.
func set_paused(paused: bool) -> void:
	_running = not paused
	ring.held = false


func _lose() -> void:
	_running = false
	ring.set_color(LOST_COLOR)
	Haptics.pulse(ring.left, 1.0, 0.4)
	Haptics.pulse(ring.right, 1.0, 0.4)
	lost.emit()
