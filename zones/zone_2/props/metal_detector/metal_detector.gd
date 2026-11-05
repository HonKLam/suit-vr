class_name MetalDetector
extends Node3D
## Metal detector logic. Add as a child of an XRToolsPickable.
## While held, it measures the strongest metal signal at the coil
## (all MetalObjects in the group "metal") and shows it:
## - Beeping: a calm base rhythm without metal, faster and higher the closer the metal is.
##   The rhythm runs continuously (never more beeps than the current rhythm allows)
##   and the signal is smoothed, so a quick sweep does not cause constant beeping.
## - Light on the device: from green (nothing) to red (strong), flashes on every beep
## - Vibration in the holding hand, in time with the beeps

## Center of the search coil.
@export var coil: Node3D
## Light on the device (gets a glowing material).
@export var led: MeshInstance3D
@export var beep: AudioStreamPlayer3D
## Range of the coil (m). Further away = no signal.
@export_range(0.1, 3.0, 0.05) var detect_range := 1.0
## Below this signal the detector stays silent.
@export_range(0.0, 1.0, 0.01) var threshold := 0.05
@export_group("Beeping")
## Base rhythm without metal (s between two beeps) and its pitch.
@export var interval_idle := 1.2
@export var pitch_idle := 0.7
## Pause between two beeps at a weak / strong signal (s).
@export var interval_weak := 0.5
@export var interval_strong := 0.06
@export var pitch_weak := 0.9
@export var pitch_strong := 1.7
## How fast the shown signal rises / falls (per second). Lower = slower,
## so a short sweep has less effect.
@export_range(0.5, 30.0, 0.5) var signal_rise := 4.0
@export_range(0.5, 30.0, 0.5) var signal_fall := 3.0
@export_group("Haptics")
## Vibration on the base beep without metal (0 = off).
@export_range(0.0, 1.0, 0.05) var haptic_idle := 0.0
@export_range(0.0, 1.0, 0.05) var haptic_weak := 0.1
@export_range(0.0, 1.0, 0.05) var haptic_strong := 0.7
@export_range(0.01, 0.2, 0.005) var haptic_time := 0.035
@export_group("Light")
@export var led_idle := Color(0.1, 0.9, 0.2)
@export var led_alarm := Color(1.0, 0.1, 0.05)
@export_range(0.0, 8.0, 0.1) var led_energy := 3.0

## Current signal 0..1 (raw, for debugging or UI).
var signal_strength := 0.0
## Smoothed signal, which drives the beeps, light and vibration.
var smoothed_signal := 0.0

var _held := false
var _phase := 0.0
var _flash := 0.0
var _pickable: Node
var _led_mat: StandardMaterial3D


func _ready() -> void:
	_pickable = get_parent()
	if _pickable and _pickable.has_signal("picked_up"):
		_pickable.picked_up.connect(_on_picked_up)
		_pickable.dropped.connect(_on_dropped)
	if led:
		_led_mat = StandardMaterial3D.new()
		_led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_led_mat.emission_enabled = true
		led.material_override = _led_mat
	_update_led(0.0, 0.0)


func _process(delta: float) -> void:
	if not _held:
		return
	signal_strength = measure()
	var rate := signal_rise if signal_strength > smoothed_signal else signal_fall
	smoothed_signal = lerpf(smoothed_signal, signal_strength, 1.0 - exp(-rate * delta))
	_flash = maxf(_flash - delta * 8.0, 0.0)

	var active := smoothed_signal >= threshold
	var s := clampf((smoothed_signal - threshold) / (1.0 - threshold), 0.0, 1.0)
	var interval := lerpf(interval_weak, interval_strong, sqrt(s)) if active else interval_idle
	# The rhythm keeps running: at most one beep per beat, missed beeps are not made up
	_phase += delta / maxf(interval, 0.01)
	if _phase >= 1.0:
		_phase = fmod(_phase, 1.0)
		if beep:
			beep.pitch_scale = lerpf(pitch_weak, pitch_strong, s) if active else pitch_idle
			beep.play()
		_pulse(lerpf(haptic_weak, haptic_strong, s) if active else haptic_idle)
		_flash = 1.0
	_update_led(smoothed_signal, _flash)


## Signal at the coil: the strongest metal, weakened by distance.
func measure() -> float:
	if coil == null:
		return 0.0
	var p := coil.global_position
	var best := 0.0
	for m in get_tree().get_nodes_in_group(MetalObject.GROUP):
		var f := clampf(1.0 - p.distance_to(m.global_position) / detect_range, 0.0, 1.0)
		best = maxf(best, m.strength * f * f)
	return best


func _on_picked_up(_p) -> void:
	_held = true
	smoothed_signal = 0.0
	_phase = 0.8 # first beep shortly after grabbing


func _on_dropped(_p) -> void:
	_held = false
	signal_strength = 0.0
	smoothed_signal = 0.0
	_update_led(0.0, 0.0)


func _update_led(s: float, flash: float) -> void:
	if _led_mat == null:
		return
	var c := led_idle.lerp(led_alarm, clampf(s * 1.5, 0.0, 1.0))
	if not _held:
		c = Color(0.05, 0.05, 0.05)
	_led_mat.albedo_color = c
	_led_mat.emission = c
	_led_mat.emission_energy_multiplier = (0.0 if not _held else 0.6 + led_energy * flash)


func _pulse(amplitude: float) -> void:
	if amplitude <= 0.0:
		return
	var ctrl: XRController3D = _pickable.get_picked_up_by_controller()
	if ctrl:
		Haptics.pulse(ctrl, amplitude, haptic_time)
