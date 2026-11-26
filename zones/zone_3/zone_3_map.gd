@tool
extends ZoneMap
## Hot wire: thread the ring onto the green start of the wire and carry it to the red end.
## Touching the wire or an obstacle, slipping off the wire or letting go of the ring loses.
## - Obstacles: random rods along the wire, 10-17 cm from it, so a huge ring doesn't just pass.
##   New layout every round (or a fixed one with obstacle_seed).
## - Too close to the wire or an obstacle: both controllers pulse fast at full strength.
## - Halfway along the wire the guide says halfway_voice.

const IDLE_COLOR: Color = Color(0.9, 0.9, 0.9)
const ARMED_COLOR: Color = Color(0.2, 0.9, 0.3)
const LOST_COLOR: Color = Color(0.9, 0.15, 0.1)
const OBSTACLE_ATTEMPTS: int = 4
## A rod keeps at least this gap to other parts of the wire and to other rods (m)
const OBSTACLE_CLEARANCE: float = 0.09

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
@export_group("Obstacles")
## One obstacle about every ... m along the wire (0 = none)
@export var obstacle_spacing: float = 0.25
## Distance of an obstacle from the wire axis (m): the ring must stay smaller than this
@export var obstacle_distance_min: float = 0.10
@export var obstacle_distance_max: float = 0.17
@export var obstacle_length_min: float = 0.15
@export var obstacle_length_max: float = 0.3
@export var obstacle_radius: float = 0.012
## 0 = new random layout every round
@export var obstacle_seed: int = 0

var _points: PackedVector3Array # whole wire, global
var _hot_points: PackedVector3Array # without the safe ends
var _safe_count: int
var _running: bool = false
var _armed: bool = false
var _halfway_said: bool = false
var _pulse_clock: float = 0.0
var _obstacle_points: PackedVector3Array # sampled every cm along each rod, global

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
	_place_obstacles()


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


## Full-strength fast pulses on both controllers while the ring is closer than danger_distance.
func _warn_if_too_close(gap: float, delta: float) -> void:
	if gap >= danger_distance:
		_pulse_clock = 0.0
		return
	_pulse_clock += delta * danger_pulse_rate
	if fmod(_pulse_clock, 1.0) < 0.5: # on half of each pulse
		var pulse_length := 0.5 / danger_pulse_rate
		Haptics.pulse(ring.left, 1.0, pulse_length)
		Haptics.pulse(ring.right, 1.0, pulse_length)


## Smallest gap between the ring's tube and the wire or an obstacle (negative = touching).
func _closest_gap() -> float:
	var to_local: Transform3D = ring.global_transform.affine_inverse()
	return minf(_gap_to(_hot_points, to_local) - wire_radius, _gap_to(_obstacle_points, to_local) - obstacle_radius)


func _gap_to(points: PackedVector3Array, to_local: Transform3D) -> float:
	var best := INF
	for point: Vector3 in points:
		var p: Vector3 = to_local * point
		best = minf(best, Vector2(Vector2(p.x, p.z).length() - ring.radius, p.y).length())
	return best - ring.tube_radius


## Rods next to the wire, roughly parallel to it, at a random angle around it. A rod is skipped if
## it would come close to another part of the wire (corkscrew windings) or another rod.
func _place_obstacles() -> void:
	if obstacle_spacing <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	if obstacle_seed != 0:
		rng.seed = obstacle_seed
	var colors: Array[Color] = [Color(0.8, 0.1, 0.08), Color(0.1, 0.6, 0.15), Color(0.95, 0.72, 0.05), Color(0.1, 0.3, 0.9)]
	var step := maxi(1, int(obstacle_spacing / wire.curve.bake_interval))
	var floor_y: float = $Floor.global_position.y + $Floor.size.y * 0.5
	for index in range(_safe_count + step / 2, _points.size() - _safe_count, step):
		var along: Vector3 = (_points[mini(index + 3, _points.size() - 1)] - _points[index - 3]).normalized()
		var side: Vector3 = along.cross(Vector3.UP)
		if side.length() < 0.1:
			side = along.cross(Vector3.RIGHT)
		for attempt in OBSTACLE_ATTEMPTS: # a few random tries per spot
			var around: Vector3 = side.normalized().rotated(along, rng.randf() * TAU)
			var centre: Vector3 = _points[index] + around * rng.randf_range(obstacle_distance_min, obstacle_distance_max)
			var direction: Vector3 = along.rotated(around, rng.randf_range(-0.35, 0.35))
			var half_length := rng.randf_range(obstacle_length_min, obstacle_length_max) * 0.5
			var a := centre - direction * half_length
			var b := centre + direction * half_length
			if minf(a.y, b.y) < floor_y + 0.05 or not _rod_is_free(a, b, index):
				continue
			for k in range(int(half_length * 2.0 / 0.01) + 1):
				_obstacle_points.append(a.lerp(b, k * 0.01 / (half_length * 2.0)))
			_add_rod_mesh(a, b, colors[rng.randi() % colors.size()])
			break


## Far enough from the wire (except the part it belongs to) and from the other rods.
func _rod_is_free(a: Vector3, b: Vector3, index: int) -> bool:
	var near_range := int(0.3 / wire.curve.bake_interval)
	for k in range(0, 11):
		var p := a.lerp(b, k / 10.0)
		for i in range(0, _points.size(), 2):
			var too_close_to_own_part := absi(i - index) <= near_range and p.distance_to(_points[i]) < obstacle_distance_min - 0.01
			var too_close_elsewhere := absi(i - index) > near_range and p.distance_to(_points[i]) < OBSTACLE_CLEARANCE
			if too_close_to_own_part or too_close_elsewhere:
				return false
		for q: Vector3 in _obstacle_points:
			if p.distance_to(q) < OBSTACLE_CLEARANCE:
				return false
	return true


func _add_rod_mesh(a: Vector3, b: Vector3, color: Color) -> void:
	var rod := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = obstacle_radius
	mesh.bottom_radius = obstacle_radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 10
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	mesh.material = material
	rod.mesh = mesh
	add_child(rod)
	var up := (b - a).normalized()
	var any_side := up.cross(Vector3.RIGHT) if absf(up.x) < 0.9 else up.cross(Vector3.FORWARD)
	rod.global_transform = Transform3D(Basis(any_side.normalized(), up, any_side.cross(up).normalized()).orthonormalized(), (a + b) * 0.5)


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
