extends Node3D
## Godot 4: two independent, subtle light pulses for the closed shrine.
## The static GLB texture itself does not animate; these lights illuminate the facade.

@export_range(0.2, 5.0, 0.01, "suffix:s") var upper_period: float = 1.25
@export_range(0.2, 5.0, 0.01, "suffix:s") var lower_period: float = 0.88
@export_range(0.0, 2.0, 0.01) var upper_base_energy: float = 0.04
@export_range(0.0, 2.0, 0.01) var lower_base_energy: float = 0.04
@export_range(0.0, 2.0, 0.01) var upper_pulse_energy: float = 0.16
@export_range(0.0, 2.0, 0.01) var lower_pulse_energy: float = 0.13

@onready var upper_light: OmniLight3D = $UpperHeartbeatLight
@onready var lower_light: OmniLight3D = $LowerHeartbeatLight
var elapsed: float = 0.0

func _process(delta: float) -> void:
	elapsed += delta
	upper_light.light_energy = upper_base_energy + upper_pulse_energy * _heartbeat(elapsed, upper_period)
	lower_light.light_energy = lower_base_energy + lower_pulse_energy * _heartbeat(elapsed + 0.31, lower_period)

func _heartbeat(time: float, period: float) -> float:
	var phase: float = fposmod(time, maxf(period, 0.001)) / maxf(period, 0.001)
	var first_distance: float = minf(phase, 1.0 - phase)
	var first: float = exp(-pow(first_distance / 0.075, 2.0))
	var second: float = exp(-pow((phase - 0.18) / 0.06, 2.0)) * 0.55
	return minf(first + second, 1.0)
