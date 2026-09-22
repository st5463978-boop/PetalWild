extends Node

const State = preload("res://scripts/sim/world_state.gd")

var state: Dictionary = {}
var slot := 1
var playing := false
var reduce_motion := false


func start_new(which: int) -> void:
	slot = which
	state = State.fresh(PetalContent.catalogs())
	playing = true


func adopt(loaded: Dictionary, which: int) -> void:
	slot = which
	state = State.ensure(loaded, PetalContent.catalogs())
	playing = true
