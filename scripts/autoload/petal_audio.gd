extends Node

var _streams := {}
var _wind: AudioStreamPlayer
var _music: AudioStreamPlayer
var _wind_play: AudioStreamGeneratorPlayback
var _phase := 0.0
var _chirp := 0.0
var enabled := true


func _ready() -> void:
	_streams["dig"] = _noise(0.09, 0.28)
	_streams["water"] = _tone(740.0, 0.12, 0.18)
	_streams["coin"] = _melody([523.0, 659.0, 784.0], 0.07)
	_streams["squish"] = _noise(0.08, 0.22)
	_streams["harvest"] = _tone(392.0, 0.14, 0.2)
	_streams["chime"] = _melody([523.0, 659.0, 784.0, 1046.0], 0.09)
	_streams["ui"] = _tone(880.0, 0.04, 0.12)
	_streams["talk"] = _tone(310.0, 0.06, 0.08)
	_use_file("ui", "res://assets/third_party/kenney/interface-sounds/Audio/select_006.ogg")
	_use_file("coin", "res://assets/third_party/kenney/interface-sounds/Audio/maximize_005.ogg")
	_use_file("error", "res://assets/third_party/kenney/interface-sounds/Audio/error_007.ogg")
	_use_file("dig", "res://assets/third_party/kenney/interface-sounds/Audio/scratch_003.ogg")
	_use_file("harvest", "res://assets/third_party/kenney/interface-sounds/Audio/open_002.ogg")
	_use_file("chime", "res://assets/third_party/kenney/interface-sounds/Audio/glass_006.ogg")
	_music = AudioStreamPlayer.new()
	_music.stream = _pad()
	_music.volume_db = -22.0
	_music.autoplay = false
	add_child(_music)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.25
	_wind = AudioStreamPlayer.new()
	_wind.stream = gen
	_wind.volume_db = -18.0
	add_child(_wind)


func start_bed() -> void:
	if not enabled:
		return
	if not _music.playing:
		_music.play()
	if not _wind.playing:
		_wind.play()
		_wind_play = _wind.get_stream_playback()


func stop_bed() -> void:
	if _music:
		_music.stop()
	if _wind:
		_wind.stop()


func set_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(linear, 0.001, 1.0)))


func set_weather(weather: String, phase: String) -> void:
	if _music == null:
		return
	if weather == "rain" or phase == "night":
		_music.volume_db = -26.0
		_music.pitch_scale = 0.92
	elif weather == "golden":
		_music.volume_db = -18.0
		_music.pitch_scale = 1.04
	else:
		_music.volume_db = -22.0
		_music.pitch_scale = 1.0


func _use_file(id: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream = load(path)
	if stream != null:
		_streams[id] = stream


func play(id: String) -> void:
	if not enabled or not _streams.has(id):
		return
	var player := AudioStreamPlayer.new()
	player.stream = _streams[id]
	player.volume_db = -6.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _process(delta: float) -> void:
	if _wind_play == null:
		return
	_chirp -= delta
	var frames := _wind_play.get_frames_available()
	while frames > 0:
		_phase += 0.018
		var gust := sin(_phase * 0.37) * 0.5 + 0.5
		var sample := sin(_phase) * 0.012 * gust + (randf() - 0.5) * 0.018 * gust
		if _chirp < 0.0 and randf() < 0.002:
			_chirp = randf_range(0.4, 1.6)
		if _chirp > 0.0:
			sample += sin(_phase * randf_range(7.0, 11.0)) * 0.02 * clampf(_chirp, 0.0, 0.2)
		_wind_play.push_frame(Vector2(sample, sample * 0.9))
		frames -= 1


func _tone(freq: float, length: float, amp: float) -> AudioStreamWAV:
	return _melody([freq], length, amp)


func _melody(freqs: Array, step: float, amp: float = 0.3) -> AudioStreamWAV:
	var rate := 22050
	var total := int(rate * step * freqs.size())
	var data := PackedByteArray()
	data.resize(total * 2)
	var index := 0
	for freq in freqs:
		var count := int(rate * step)
		for s in count:
			var env := 1.0 - float(s) / float(maxi(count, 1))
			var sample := sin(TAU * float(freq) * float(s) / float(rate)) * env * amp
			var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
			data[index] = value & 255
			data[index + 1] = (value >> 8) & 255
			index += 2
	return _wav(data, rate)


func _noise(length: float, amp: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var index := 0
	for s in count:
		var env := 1.0 - float(s) / float(maxi(count, 1))
		var sample := (randf() * 2.0 - 1.0) * env * amp
		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data[index] = value & 255
		data[index + 1] = (value >> 8) & 255
		index += 2
	return _wav(data, rate)


func _pad() -> AudioStreamWAV:
	var rate := 22050
	var seconds := 8.0
	var count := int(rate * seconds)
	var scale := [196.0, 247.0, 294.0, 330.0, 392.0]
	var data := PackedByteArray()
	data.resize(count * 2)
	var index := 0
	for s in count:
		var t := float(s) / float(rate)
		var chord: float = float(scale[int(t / 2.0) % scale.size()])
		var sample := sin(TAU * chord * t) * 0.08 + sin(TAU * chord * 2.0 * t) * 0.03
		sample += sin(TAU * (chord * 1.5) * t) * 0.02
		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data[index] = value & 255
		data[index + 1] = (value >> 8) & 255
		index += 2
	var wav := _wav(data, rate)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = count
	return wav


func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
