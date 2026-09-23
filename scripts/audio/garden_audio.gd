class_name GardenAudio
extends Node

var bank := {}
var wind: AudioStreamPlayer
var pad: AudioStreamPlayer
var bed_file := false

func _ready() -> void:
	bank["till"] = _tone(180.0, 0.12, 0.35, 18.0, true)
	bank["water"] = _noise(0.28, 0.25, 900.0)
	bank["plant"] = _tone(520.0, 0.09, 0.22, 12.0, false)
	bank["harvest"] = _arpeggio([523.0, 659.0, 784.0], 0.09)
	bank["squish"] = _tone(140.0, 0.16, 0.4, 10.0, true)
	bank["ui"] = _tone(660.0, 0.05, 0.16, 20.0, false)
	bank["coin"] = _arpeggio([880.0, 1174.0], 0.07)
	bank["discovery"] = _arpeggio([392.0, 494.0, 587.0, 784.0], 0.11)
	bank["ring"] = _arpeggio([784.0, 1174.0], 0.14)
	bank["chirp"] = _tone(1480.0, 0.08, 0.12, 16.0, false)
	wind = AudioStreamPlayer.new()
	wind.stream = _noise(3.2, 0.18, 420.0)
	wind.volume_db = -22.0
	add_child(wind)
	wind.play()
	pad = AudioStreamPlayer.new()
	_use_bed()
	add_child(pad)
	pad.play()

func play_kind(kind: String, db := -8.0) -> void:
	if not bank.has(kind):
		return
	var player := AudioStreamPlayer.new()
	player.stream = bank[kind]
	player.volume_db = db
	player.pitch_scale = randf_range(0.94, 1.06)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func set_weather(weather: String) -> void:
	if wind:
		wind.volume_db = -18.0 if weather == "rain" else (-30.0 if bed_file else -22.0)
	if pad:
		if bed_file:
			pad.volume_db = -26.0 if weather == "rain" else -18.0
		else:
			pad.volume_db = -30.0 if weather == "rain" else -26.0

func _use_bed() -> void:
	var path := "res://assets/third_party/opengameart/Forest_Ambience.mp3"
	if ResourceLoader.exists(path):
		var bed: Resource = load(path)
		if bed is AudioStreamMP3:
			(bed as AudioStreamMP3).loop = true
			pad.stream = bed
			pad.volume_db = -18.0
			bed_file = true
			return
	pad.stream = _pad()
	pad.volume_db = -26.0

func _tone(freq: float, duration: float, volume: float, decay: float, drop: bool) -> AudioStreamWAV:
	var rate := 22050
	var count := int(duration * rate)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(rate)
		var f := freq * (1.0 - t * 0.45) if drop else freq
		var env := exp(-t * decay)
		samples[i] = sin(phase) * volume * env
		phase += TAU * f / float(rate)
	return _wav_from(samples, rate, false)

func _arpeggio(notes: Array, note_len: float) -> AudioStreamWAV:
	var rate := 22050
	var samples: PackedFloat32Array = PackedFloat32Array()
	for freq in notes:
		var count := int(note_len * rate)
		var phase := 0.0
		for i in count:
			var t := float(i) / float(rate)
			var env := exp(-t * 8.0)
			samples.append(sin(phase) * 0.2 * env)
			phase += TAU * float(freq) / float(rate)
	return _wav_from(samples, rate, false)

func _noise(duration: float, volume: float, cutoff: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(duration * rate)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var hold := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 14017
	var coeff := clampf(cutoff / float(rate), 0.01, 0.4)
	for i in count:
		var white := rng.randf_range(-1.0, 1.0)
		hold += (white - hold) * coeff
		var fade := 1.0
		var edge := int(0.12 * rate)
		if i < edge:
			fade = float(i) / float(edge)
		elif i > count - edge:
			fade = float(count - i) / float(edge)
		samples[i] = hold * volume * fade
	return _wav_from(samples, rate, true)

func _pad() -> AudioStreamWAV:
	var rate := 22050
	var duration := 4.0
	var count := int(duration * rate)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var p1 := 0.0
	var p2 := 0.0
	for i in count:
		var t := float(i) / float(rate)
		p1 += TAU * 196.0 / float(rate)
		p2 += TAU * 246.9 / float(rate)
		var trem := 0.75 + 0.25 * sin(t * 0.7)
		var sample := (sin(p1) * 0.5 + sin(p2) * 0.35) * 0.12 * trem
		var edge := int(0.2 * rate)
		var fade := 1.0
		if i < edge:
			fade = float(i) / float(edge)
		elif i > count - edge:
			fade = float(count - i) / float(edge)
		samples[i] = sample * fade
	return _wav_from(samples, rate, true)

func _wav_from(samples: PackedFloat32Array, rate: int, looped: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var value := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data[i * 2] = value & 255
		data[i * 2 + 1] = (value >> 8) & 255
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream
