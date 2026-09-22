extends Node

signal time_changed(day: int, hour: float, weather: String)
signal weather_changed(next_weather: String)

var running := false
var day := 1
var minute := 15.2 * 60.0
var scale := 6.0
var weather := "golden"
var _last_bucket := -1

func _ready() -> void:
	weather = weather_for(hour(), day)

func _process(delta: float) -> void:
	if not running:
		return
	minute += delta * scale
	while minute >= 24.0 * 60.0:
		minute -= 24.0 * 60.0
		day += 1
	var next := weather_for(hour(), day)
	var bucket := int(minute)
	if bucket != _last_bucket:
		_last_bucket = bucket
		time_changed.emit(day, hour(), weather)
	if next != weather:
		weather = next
		weather_changed.emit(weather)
		time_changed.emit(day, hour(), weather)

func hour() -> float:
	return minute / 60.0

func clock_label() -> String:
	var h := hour()
	var name := "Night"
	if h >= 5.0 and h < 11.0:
		name = "Morning"
	elif h >= 11.0 and h < 16.5:
		name = "Golden"
	elif h >= 16.5 and h < 19.5:
		name = "Dusk"
	elif h >= 19.5 and h < 22.0:
		name = "Evening"
	return "Day %d  ·  %s" % [day, name]

func weather_for(h: float, d: int) -> String:
	if h >= 5.0 and h < 11.0:
		return "clear"
	if h >= 11.0 and h < 16.5:
		return "golden"
	if h >= 16.5 and h < 19.5:
		return "mist"
	if h >= 19.5 and h < 22.0:
		return "rain" if d % 2 == 1 else "mist"
	return "clear"

func set_hour(value: float) -> void:
	minute = fposmod(value, 24.0) * 60.0
	weather = weather_for(hour(), day)
	time_changed.emit(day, hour(), weather)
	weather_changed.emit(weather)

func reset_new() -> void:
	running = false
	day = 1
	minute = 15.2 * 60.0
	scale = 6.0
	weather = "golden"

func to_state() -> Dictionary:
	return {"day": day, "minute": minute, "scale": scale, "weather": weather}

func apply_state(data: Dictionary) -> void:
	day = int(data.get("day", 1))
	minute = float(data.get("minute", minute))
	scale = float(data.get("scale", scale))
	weather = str(data.get("weather", weather_for(hour(), day)))
