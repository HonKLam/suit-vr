class_name ShovelAudio
extends Node3D
## Shovel sounds. Add as a direct child of a Shovel.
## - Stab: light / normal / strong, depending on the strength of Shovel.stabbed.
##   Plays right away, as the shovel then sticks in the ground.
## - Hit: on top of the stab when the blade hits a find in the ground (coin, can, bomb),
##   louder for a harder stab.
## - Scoop: earth trickles off when the shovel pops out, louder for a bigger hole.

const STAB_SPREAD_DB: float = 3.0
const HIT_SPREAD_DB: float = 6.0
const SCOOP_SPREAD_DB: float = 4.0
## Random pitch range
const PITCH_RANGE := Vector2(0.92, 1.08)
const UNIT_SIZE: float = 2.0
const MAX_DISTANCE: float = 30.0
## The blade counts as hitting a find this close to its bounds (m)
const HIT_MARGIN: float = 0.02
## Blade points checked from the tip upward, this far apart (m)
const HIT_CHECK_STEP: float = 0.02

@export_group("Sounds")
@export var stab_light: Array[AudioStream] = []
@export var stab_normal: Array[AudioStream] = []
@export var stab_strong: Array[AudioStream] = []
@export var hits: Array[AudioStream] = []
@export var scoops: Array[AudioStream] = []

@export_group("Volume")
@export_range(-30.0, 12.0, 0.5) var stab_volume_db: float = -5.0
@export_range(-30.0, 12.0, 0.5) var hit_volume_db: float = -8.0
@export_range(-30.0, 12.0, 0.5) var scoop_volume_db: float = -10.0

@export_group("Stab strength")
## From this stab strength (0..1) the stab sounds normal. Lower = normal sounds sooner.
@export_range(0.0, 1.0, 0.05) var normal_stab_from: float = 0.25
## From this stab strength (0..1) the stab sounds strong. Lower = strong sounds sooner.
@export_range(0.0, 1.0, 0.05) var strong_stab_from: float = 0.55

var _shovel: Shovel
var _stab_voices: Array[AudioStreamPlayer3D] = []
var _hit_voices: Array[AudioStreamPlayer3D] = []
var _scoop_voices: Array[AudioStreamPlayer3D] = []
var _next_stab_voice: int = 0
var _next_hit_voice: int = 0
var _next_scoop_voice: int = 0
var _last_sound_index: Dictionary = {} # sound kind -> index of the last sound played


func _ready() -> void:
	_shovel = get_parent() as Shovel
	assert(_shovel != null, "ShovelAudio must be a direct child of a Shovel.")
	_shovel.stabbed.connect(_on_stabbed)
	_shovel.scooped.connect(_on_scooped)
	# Own voices per kind, so a long scoop is not cut by the next stab
	for i in 3:
		_stab_voices.append(_make_voice())
	for i in 2:
		_hit_voices.append(_make_voice())
	for i in 4:
		_scoop_voices.append(_make_voice())


func _on_stabbed(strength: float, at: Vector3) -> void:
	var sound_kind: String = "light"
	var sounds: Array[AudioStream] = stab_light
	if strength >= strong_stab_from:
		sound_kind = "strong"
		sounds = stab_strong
	elif strength >= normal_stab_from:
		sound_kind = "normal"
		sounds = stab_normal
	var stab_db: float = stab_volume_db + lerpf(-STAB_SPREAD_DB, STAB_SPREAD_DB, strength)
	_next_stab_voice = _play(_stab_voices, _next_stab_voice, _pick(sound_kind, sounds), at, stab_db)

	var hit_find: Node3D = _find_under_blade(at)
	if hit_find:
		var hit_db: float = hit_volume_db + lerpf(-HIT_SPREAD_DB, HIT_SPREAD_DB, strength)
		_next_hit_voice = _play(_hit_voices, _next_hit_voice, _pick("hit", hits), hit_find.global_position, hit_db)


func _on_scooped(at: Vector3, radius: float) -> void:
	var hole_size: float = clampf(inverse_lerp(Shovel.MIN_HOLE_RADIUS, Shovel.MAX_HOLE_RADIUS, radius), 0.0, 1.0)
	var scoop_db: float = scoop_volume_db + lerpf(-SCOOP_SPREAD_DB, SCOOP_SPREAD_DB, hole_size)
	_next_scoop_voice = _play(_scoop_voices, _next_scoop_voice, _pick("scoop", scoops), at, scoop_db)


## Find (MetalObject spot with a model) that the stuck blade touches, or null.
## Checks points from the tip up along the shaft.
func _find_under_blade(tip: Vector3) -> Node3D:
	var shaft_up: Vector3 = _shovel.global_basis.y.normalized()
	for spot: Node3D in get_tree().get_nodes_in_group(MetalObject.GROUP):
		var bounds: AABB = _visual_bounds(spot)
		if bounds.size == Vector3.ZERO:
			continue # find already collected
		bounds = bounds.grow(HIT_MARGIN)
		var world_to_spot: Transform3D = spot.global_transform.affine_inverse()
		var distance_from_tip: float = 0.0
		while distance_from_tip <= Shovel.MAX_DEPTH:
			if bounds.has_point(world_to_spot * (tip + shaft_up * distance_from_tip)):
				return spot
			distance_from_tip += HIT_CHECK_STEP
	return null


## Bounds of all meshes below the spot, in spot space. Empty if it has none.
func _visual_bounds(spot: Node3D) -> AABB:
	var bounds := AABB()
	var is_first: bool = true
	var world_to_spot: Transform3D = spot.global_transform.affine_inverse()
	for mesh: MeshInstance3D in spot.find_children("*", "MeshInstance3D", true, false):
		var mesh_bounds: AABB = world_to_spot * mesh.global_transform * mesh.get_aabb()
		bounds = mesh_bounds if is_first else bounds.merge(mesh_bounds)
		is_first = false
	return bounds


## Returns the index of the next voice.
func _play(voices: Array[AudioStreamPlayer3D], voice_index: int, sound: AudioStream, at: Vector3, volume_db: float) -> int:
	if sound == null:
		return voice_index
	var voice: AudioStreamPlayer3D = voices[voice_index]
	voice.global_position = at
	voice.stream = sound
	voice.volume_db = volume_db
	voice.pitch_scale = randf_range(PITCH_RANGE.x, PITCH_RANGE.y)
	voice.play()
	return (voice_index + 1) % voices.size()


## Random sound, never the same one twice in a row.
func _pick(sound_kind: String, sounds: Array[AudioStream]) -> AudioStream:
	if sounds.is_empty():
		return null
	var sound_index: int = randi() % sounds.size()
	if sounds.size() > 1 and sound_index == _last_sound_index.get(sound_kind, -1):
		sound_index = (sound_index + 1) % sounds.size()
	_last_sound_index[sound_kind] = sound_index
	return sounds[sound_index]


func _make_voice() -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.top_level = true
	voice.unit_size = UNIT_SIZE
	voice.max_distance = MAX_DISTANCE
	add_child(voice)
	return voice
