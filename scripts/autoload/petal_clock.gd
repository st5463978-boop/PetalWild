extends Node

const Rules = preload("res://scripts/sim/petal_rules.gd")

var paused := false


func apply(state: Dictionary, delta: float) -> void:
	if paused or state.is_empty():
		return
	var scale := maxf(float(state.get("time_scale", 1.0)), 0.0)
	state["minute_acc"] = float(state.get("minute_acc", 0.0)) + delta * scale * 4.0
	while float(state["minute_acc"]) >= 1.0:
		state["minute_acc"] = float(state["minute_acc"]) - 1.0
		state["minute"] = int(state.get("minute", 0)) + 1
		if int(state["minute"]) >= 1440:
			state["minute"] = 0
			state["day"] = int(state.get("day", 1)) + 1


func phase(state: Dictionary) -> String:
	return Rules.phase_for(int(state.get("minute", 0)))


func clock_label(state: Dictionary) -> String:
	var minute := int(state.get("minute", 0))
	var hour := int(minute / 60) % 24
	var mins := minute % 60
	return "Day %d  %02d:%02d  %s" % [int(state.get("day", 1)), hour, mins, phase(state).capitalize()]
