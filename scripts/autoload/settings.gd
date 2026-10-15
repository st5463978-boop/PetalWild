extends Node

const JevCore := preload("res://scripts/game/jev_game_core.gd")

var master := 0.72
var large_text := false
var reduce_motion := false
var photosensitivity := false
var jev_game_core_url := ""

func _ready() -> void:
	load_settings()
	apply_audio()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return
	master = float(config.get_value("audio", "master", master))
	large_text = bool(config.get_value("access", "large_text", large_text))
	reduce_motion = bool(config.get_value("access", "reduce_motion", reduce_motion))
	photosensitivity = bool(config.get_value("access", "photosensitivity", photosensitivity))
	var saved_url := str(config.get_value("jev_game_core", "url", jev_game_core_url)).strip_edges()
	if JevCore.looks_like_ntfy(saved_url):
		jev_game_core_url = ""
	else:
		jev_game_core_url = saved_url

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master)
	config.set_value("access", "large_text", large_text)
	config.set_value("access", "reduce_motion", reduce_motion)
	config.set_value("access", "photosensitivity", photosensitivity)
	if JevCore.looks_like_ntfy(jev_game_core_url):
		jev_game_core_url = ""
	config.set_value("jev_game_core", "url", jev_game_core_url)
	config.save("user://settings.cfg")

func apply_audio() -> void:
	var linear := clampf(master, 0.0, 1.0)
	var db := -80.0 if linear <= 0.001 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(0, db)
