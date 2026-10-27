class_name MetalDetector
extends Node3D
## Logik des Metalldetektors. Als Kind eines XRToolsPickable einhängen.
## Solange er gehalten wird, misst er an der Spule (coil) das stärkste Metall-Signal
## (alle MetalObject in der Gruppe "metal") und zeigt es an:
## - Piepen: je näher, desto schneller und höher
## - Leuchte am Gerät: von grün (nichts) bis rot (stark), blitzt bei jedem Piep
## - Vibration in der haltenden Hand, im Takt des Piepens

## Mittelpunkt der Suchspule.
@export var coil: Node3D
## Leuchte am Gerät (bekommt ein leuchtendes Material).
@export var led: MeshInstance3D
@export var beep: AudioStreamPlayer3D
## Reichweite der Spule (m). Weiter weg = kein Signal.
@export_range(0.1, 3.0, 0.05) var detect_range := 1.0
## Unter diesem Signal bleibt der Detektor still.
@export_range(0.0, 1.0, 0.01) var threshold := 0.05
@export_group("Piepen")
## Pause zwischen zwei Pieps bei schwachem / starkem Signal (s).
@export var interval_weak := 0.9
@export var interval_strong := 0.07
@export var pitch_weak := 0.85
@export var pitch_strong := 1.7
@export_group("Haptik")
@export var haptics_enabled := true
@export var haptic_action := "haptic"
@export_range(0.0, 1.0, 0.05) var haptic_weak := 0.1
@export_range(0.0, 1.0, 0.05) var haptic_strong := 0.7
@export_range(0.01, 0.2, 0.005) var haptic_time := 0.035
@export_group("Leuchte")
@export var led_idle := Color(0.1, 0.9, 0.2)
@export var led_alarm := Color(1.0, 0.1, 0.05)
@export_range(0.0, 8.0, 0.1) var led_energy := 3.0

## Aktuelles Signal 0..1 (zum Debuggen oder für UI).
var signal_strength := 0.0

var _held := false
var _timer := 0.0
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
	_flash = maxf(_flash - delta * 8.0, 0.0)
	if signal_strength < threshold:
		_timer = 0.0
	else:
		_timer -= delta
		if _timer <= 0.0:
			var s := clampf((signal_strength - threshold) / (1.0 - threshold), 0.0, 1.0)
			_timer = lerpf(interval_weak, interval_strong, sqrt(s))
			if beep:
				beep.pitch_scale = lerpf(pitch_weak, pitch_strong, s)
				beep.play()
			_pulse(lerpf(haptic_weak, haptic_strong, s))
			_flash = 1.0
	_update_led(signal_strength, _flash)


## Signal an der Spule: stärkstes Metall, abgeschwächt mit dem Abstand.
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
	_timer = 0.0


func _on_dropped(_p) -> void:
	_held = false
	signal_strength = 0.0
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
	if not haptics_enabled or _pickable == null or not _pickable.has_method("get_picked_up_by_controller"):
		return
	var ctrl: XRController3D = _pickable.get_picked_up_by_controller()
	if ctrl == null:
		return
	var scale := 1.0
	var us := get_node_or_null("/root/XRToolsUserSettings")
	if us and "haptics_scale" in us:
		scale = us.haptics_scale
	ctrl.trigger_haptic_pulse(haptic_action, 0.0, clampf(amplitude * scale, 0.0, 1.0), haptic_time, 0.0)
