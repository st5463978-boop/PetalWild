extends Node

var wind: AudioStreamPlayer
var rain: AudioStreamPlayer
var chirp: AudioStreamPlayer
var blip: AudioStreamPlayer
var squish: AudioStreamPlayer
var chirp_timer := 2.0


func build() -> void:
	wind = _player(_noise(1.6, 1800.0, 0.08), true, -18.0)
	rain = _player(_noise(1.2, 5000.0, 0.16), true, -16.0)
	rain.stream_paused = true
	chirp = _player(_chirp_sample(), false, -8.0)
	blip = _player(_tone(660.0, 0.06, 0.2), false, -6.0)
	squish = _player(_squish_sample(), false, -4.0)
	refresh()


func refresh() -> void:
	var db := linear_to_db(clampf(Session.master_volume, 0.001, 1.0))
	for player in [wind, rain, chirp, blip, squish]:
		if player:
			player.volume_db = db - 8.0


func set_weather(weather: String) -> void:
	if rain:
		rain.stream_paused = weather != "rain"


func ui() -> void:
	if blip and not blip.playing:
		blip.play()


func impact() -> void:
	if squish:
		squish.play()


func _process(delta: float) -> void:
	chirp_timer -= delta
	if chirp_timer > 0.0 or chirp == null:
		return
	chirp_timer = randf_range(3.5, 8.0)
	if Session.weather != "rain":
		chirp.play()


func _player(stream: AudioStream, looped: bool, db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = db
	player.autoplay = looped
	add_child(player)
	if looped:
		player.play()
	return player


func _tone(freq: float, length: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(length * rate)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / float(rate)
		var env := 1.0 - t / length
		samples[i] = sin(TAU * freq * t) * volume * env
	return _wav(samples, false)


func _chirp_sample() -> AudioStreamWAV:
	var rate := 22050
	var count := int(0.18 * rate)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / float(rate)
		var freq := lerpf(1400.0, 2300.0, t / 0.18)
		var env := sin(PI * t / 0.18)
		samples[i] = sin(TAU * freq * t) * 0.18 * env
	return _wav(samples, false)


func _squish_sample() -> AudioStreamWAV:
	var rate := 22050
	var count := int(0.12 * rate)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / float(rate)
		var env := exp(-t * 28.0)
		samples[i] = sin(TAU * 140.0 * t) * env * 0.4
	return _wav(samples, false)


func _noise(length: float, cutoff: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(length * rate)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var hold := 0.0
	for i in count:
		hold = lerpf(hold, randf_range(-1.0, 1.0), clampf(cutoff / float(rate), 0.0, 1.0))
		samples[i] = hold * volume
	return _wav(samples, true)


func _wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var value := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data[i * 2] = value & 255
		data[i * 2 + 1] = (value >> 8) & 255
	stream.data = data
	return stream
