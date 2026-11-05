class_name Haptics
extends RefCounted
## Controller vibration, scaled by the player's vibration setting.
## Calls the controller directly instead of XRToolsRumbleManager: the manager always sends 0.1 s
## pulses, which would blur the short ticks and on/off blinking used here.

const ACTION := &"haptic"


static func pulse(controller: XRController3D, amplitude: float, duration: float) -> void:
	var strength := clampf(amplitude * XRToolsUserSettings.haptics_scale, 0.0, 1.0)
	controller.trigger_haptic_pulse(ACTION, 0.0, strength, duration, 0.0)
