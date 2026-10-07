extends Node
## 程序化音效与音乐：运行时合成波形，无需任何外部音频素材。

const RATE := 22050

var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_name := ""
var _lowpass: AudioEffectLowPassFilter
var _music_bus := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in 28:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		# Keep the Godot mixer and Music low-pass bus effects on Web as well.
		# Player enum Stream=1; project setting Stream=0 (different enums).
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_music)
	_preload_baked()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if (window.pawAudio) window.pawAudio.setReady();", true)


## 预载 assets/sfx 里烘焙好的音效（由 scripts/tools/bake_audio.gd 生成）
func _preload_baked() -> void:
	var dir := DirAccess.open("res://assets/sfx")
	if dir == null:
		return
	for f in dir.get_files():
		var fn := f.trim_suffix(".import").trim_suffix(".remap")
		if not fn.ends_with(".wav"):
			continue
		var n := fn.get_basename()
		if _cache.has(n):
			continue
		var s = load("res://assets/sfx/" + fn)
		if s is AudioStreamWAV:
			if n.begins_with("music_"):
				var w := s as AudioStreamWAV
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_begin = 0
				w.loop_end = int(w.get_length() * w.mix_rate)
			_cache[n] = s


func _setup_buses() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "SFX")
		AudioServer.set_bus_send(i, "Master")
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		var j := AudioServer.bus_count - 1
		AudioServer.set_bus_name(j, "Music")
		AudioServer.set_bus_send(j, "Master")
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 700.0
		AudioServer.add_bus_effect(j, _lowpass)
		AudioServer.set_bus_effect_enabled(j, 0, false)
	_music_bus = AudioServer.get_bus_index("Music")


func set_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(i, linear <= 0.001)
	_publish_web_mix()


func _publish_web_mix() -> void:
	if not OS.has_feature("web"):
		return
	var levels := {}
	for bus in ["SFX", "Music"]:
		var i := AudioServer.get_bus_index(bus)
		levels[bus.to_lower()] = 0.0 if i < 0 or AudioServer.is_bus_mute(i) else db_to_linear(AudioServer.get_bus_volume_db(i))
	JavaScriptBridge.eval("if (window.pawAudio) window.pawAudio.setMix(" + JSON.stringify(levels) + ");", true)


## 子弹时间：音乐闷住
func muffle(on: bool) -> void:
	if _music_bus >= 0 and AudioServer.get_bus_effect_count(_music_bus) > 0:
		AudioServer.set_bus_effect_enabled(_music_bus, 0, on)


func play(sound: String, vol_db := 0.0, pitch := 1.0, pitch_rand := 0.05) -> void:
	var s := _stream(sound)
	if s == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-pitch_rand, pitch_rand)))
	p.play()


func music(track: String) -> void:
	if track == _music_name and _music.playing:
		return
	_music_name = track
	if track == "":
		_music.stop()
		return
	_music.stream = _stream("music_" + track)
	_music.volume_db = -6.0
	_music.play()


func _stream(sound: String) -> AudioStreamWAV:
	# 烘焙文件缺失时才现场合成（会有一次性开销）
	if not _cache.has(sound):
		var data := _synth(sound)
		if data.is_empty():
			return null
		_cache[sound] = _to_wav(data, sound.begins_with("music_"))
	return _cache[sound]


func _to_wav(data: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w


# ------------------------------------------------------------------ 合成器

static func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	b.fill(0.0)
	return b


## 噪声：lp 越小越闷；env_k 为指数衰减速度
static func _add_noise(b: PackedFloat32Array, start: float, dur: float, amp: float, env_k: float, lp := 1.0, hp := false) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var y := 0.0
	var prev := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= b.size():
			break
		var t := float(i) / RATE
		y += (randf_range(-1.0, 1.0) - y) * lp
		var v := y
		if hp:
			v = y - prev
			prev = y
		b[idx] += v * amp * exp(-t * env_k)


## 音调：频率从 f0 指数滑到 f1；wave: 0 正弦 1 方波 2 三角 3 锯齿
static func _add_tone(b: PackedFloat32Array, start: float, dur: float, amp: float, f0: float, f1: float,
		env_k: float, wave := 0, attack := 0.003) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= b.size():
			break
		var t := float(i) / RATE
		var k := t / dur
		var f := f0 * pow(f1 / f0, k)
		ph += f / RATE
		var x := fmod(ph, 1.0)
		var v := 0.0
		match wave:
			0: v = sin(TAU * x)
			1: v = 1.0 if x < 0.5 else -1.0
			2: v = 4.0 * absf(x - 0.5) - 1.0
			3: v = 2.0 * x - 1.0
		var env := exp(-t * env_k) * minf(1.0, t / attack)
		b[idx] += v * amp * env


## 钟声（多个泛音）
static func _add_bell(b: PackedFloat32Array, start: float, dur: float, amp: float, f: float) -> void:
	_add_tone(b, start, dur, amp, f, f, 4.0, 0, 0.002)
	_add_tone(b, start, dur, amp * 0.5, f * 2.01, f * 2.01, 6.0, 0, 0.002)
	_add_tone(b, start, dur, amp * 0.25, f * 3.02, f * 3.02, 9.0, 0, 0.002)


static func _note(semi_from_a4: float) -> float:
	return 440.0 * pow(2.0, semi_from_a4 / 12.0)


func _synth(sound: String) -> PackedFloat32Array:
	var b: PackedFloat32Array
	match sound:
		"shot":
			b = _buf(0.22)
			_add_noise(b, 0, 0.2, 0.75, 26.0, 0.55)
			_add_tone(b, 0, 0.16, 0.8, 170.0, 45.0, 16.0)
			_add_noise(b, 0, 0.02, 0.5, 80.0, 1.0, true)
		"shot_buff":
			b = _buf(0.25)
			_add_noise(b, 0, 0.22, 0.75, 22.0, 0.6)
			_add_tone(b, 0, 0.2, 0.9, 220.0, 40.0, 13.0)
			_add_tone(b, 0, 0.08, 0.25, 1600.0, 600.0, 30.0, 3)
		"enemy_shot":
			b = _buf(0.2)
			_add_tone(b, 0, 0.18, 0.45, 1500.0, 260.0, 18.0, 1)
			_add_noise(b, 0, 0.1, 0.4, 35.0, 0.7)
			_add_tone(b, 0, 0.12, 0.5, 140.0, 60.0, 20.0)
		"hit":
			b = _buf(0.08)
			_add_noise(b, 0, 0.06, 0.6, 60.0, 1.0, true)
			_add_tone(b, 0, 0.06, 0.45, 950.0, 500.0, 45.0, 2)
		"hit_player":
			b = _buf(0.25)
			_add_tone(b, 0, 0.22, 0.9, 140.0, 55.0, 12.0)
			_add_noise(b, 0, 0.15, 0.5, 25.0, 0.3)
		"bonk":
			b = _buf(0.45)
			_add_tone(b, 0, 0.42, 0.7, 820.0, 160.0, 6.0, 2)
			_add_noise(b, 0, 0.04, 0.6, 60.0, 0.8)
			_add_tone(b, 0, 0.1, 0.6, 120.0, 60.0, 25.0)
		"cuff":
			b = _buf(0.3)
			for st in [0.0, 0.09]:
				_add_tone(b, st, 0.15, 0.4, 2600.0, 2600.0, 40.0)
				_add_tone(b, st, 0.15, 0.3, 3720.0, 3720.0, 50.0)
				_add_noise(b, st, 0.02, 0.5, 120.0, 1.0, true)
		"reload_start":
			b = _buf(0.15)
			_add_noise(b, 0, 0.03, 0.6, 100.0, 1.0, true)
			_add_tone(b, 0.05, 0.06, 0.4, 380.0, 300.0, 50.0, 1)
		"reload_done":
			b = _buf(0.16)
			_add_noise(b, 0, 0.04, 0.6, 80.0, 0.9, true)
			_add_tone(b, 0.0, 0.1, 0.5, 520.0, 260.0, 40.0, 1)
			_add_noise(b, 0.07, 0.05, 0.5, 90.0, 0.9, true)
		"perfect":
			b = _buf(0.5)
			var notes := [0.0, 4.0, 7.0, 12.0]
			for i in notes.size():
				_add_tone(b, i * 0.055, 0.3, 0.32, _note(notes[i] + 3), _note(notes[i] + 3), 9.0, 2)
		"jam":
			b = _buf(0.3)
			_add_tone(b, 0, 0.28, 0.35, 110.0, 95.0, 6.0, 1)
			_add_noise(b, 0, 0.05, 0.4, 60.0, 1.0, true)
		"empty":
			b = _buf(0.06)
			_add_noise(b, 0, 0.03, 0.5, 120.0, 1.0, true)
		"roll":
			b = _buf(0.3)
			var n := b.size()
			var y := 0.0
			for i in n:
				var t := float(i) / n
				y += (randf_range(-1, 1) - y) * (0.08 + 0.3 * sin(PI * t))
				b[i] = y * sin(PI * t) * 0.9
		"dash":
			b = _buf(0.45)
			var n2 := b.size()
			var y2 := 0.0
			for i in n2:
				var t2 := float(i) / n2
				y2 += (randf_range(-1, 1) - y2) * (0.1 + 0.4 * (1.0 - t2))
				b[i] = y2 * (1.0 - t2) * 1.0
			_add_tone(b, 0, 0.3, 0.5, 90.0, 50.0, 6.0)
		"breach":
			b = _buf(1.0)
			_add_noise(b, 0, 0.9, 1.0, 5.0, 0.18)
			_add_tone(b, 0, 0.8, 1.0, 75.0, 32.0, 4.5)
			_add_noise(b, 0, 0.08, 0.8, 40.0, 1.0, true)
			_add_tone(b, 0.0, 0.12, 0.5, 300.0, 120.0, 25.0, 3)
		"slowmo":
			b = _buf(1.2)
			_add_tone(b, 0, 1.2, 0.5, 260.0, 45.0, 1.6, 3, 0.05)
			_add_tone(b, 0, 1.2, 0.4, 130.0, 30.0, 1.4, 0, 0.05)
		"alert":
			b = _buf(0.2)
			_add_tone(b, 0, 0.07, 0.3, 660.0, 700.0, 10.0, 1)
			_add_tone(b, 0.08, 0.1, 0.3, 990.0, 1050.0, 12.0, 1)
		"telegraph":
			b = _buf(0.25)
			_add_tone(b, 0, 0.22, 0.18, 1800.0, 2600.0, 5.0, 0, 0.02)
		"ui_hover":
			b = _buf(0.05)
			_add_tone(b, 0, 0.04, 0.22, 1900.0, 2100.0, 80.0, 2)
		"ui_click":
			b = _buf(0.12)
			_add_tone(b, 0, 0.1, 0.45, 700.0, 280.0, 30.0, 2)
			_add_noise(b, 0, 0.02, 0.3, 100.0, 1.0, true)
		"ui_deny":
			b = _buf(0.2)
			_add_tone(b, 0, 0.08, 0.3, 220.0, 200.0, 20.0, 1)
			_add_tone(b, 0.09, 0.1, 0.3, 165.0, 150.0, 20.0, 1)
		"type":
			b = _buf(0.03)
			_add_tone(b, 0, 0.025, 0.12, 1250.0, 1150.0, 80.0, 1)
		"radio":
			b = _buf(0.22)
			_add_noise(b, 0, 0.18, 0.35, 12.0, 1.0, true)
			_add_tone(b, 0.14, 0.07, 0.25, 1500.0, 1500.0, 30.0, 0)
		"stamp":
			b = _buf(0.35)
			_add_tone(b, 0, 0.3, 1.0, 110.0, 45.0, 10.0)
			_add_noise(b, 0, 0.12, 0.7, 28.0, 0.35)
		"paper":
			b = _buf(0.45)
			var n3 := b.size()
			var y3 := 0.0
			for i in n3:
				var t3 := float(i) / n3
				y3 += (randf_range(-1, 1) - y3) * 0.5
				b[i] = y3 * sin(PI * t3) * 0.35 * (0.6 + 0.4 * sin(t3 * 60.0))
		"chime":
			b = _buf(1.6)
			_add_bell(b, 0.0, 0.8, 0.35, _note(7))
			_add_bell(b, 0.35, 1.2, 0.35, _note(3))
		"bite":
			b = _buf(0.1)
			_add_noise(b, 0, 0.05, 0.7, 70.0, 1.0, true)
			_add_tone(b, 0, 0.08, 0.4, 500.0, 200.0, 40.0, 1)
		"swing":
			b = _buf(0.2)
			_add_noise(b, 0, 0.18, 0.4, 14.0, 0.15)
		"heartbeat":
			b = _buf(0.5)
			_add_tone(b, 0, 0.15, 0.8, 70.0, 45.0, 22.0)
			_add_tone(b, 0.17, 0.15, 0.6, 65.0, 42.0, 22.0)
		"score":
			b = _buf(0.1)
			_add_tone(b, 0, 0.08, 0.2, 1320.0, 1760.0, 30.0, 2)
		"dodge":
			b = _buf(0.2)
			_add_tone(b, 0, 0.18, 0.25, 600.0, 1400.0, 12.0, 2)
		"block":
			b = _buf(0.18)
			_add_tone(b, 0, 0.16, 0.25, 2200.0, 1900.0, 25.0, 0)
			_add_noise(b, 0, 0.03, 0.4, 100.0, 1.0, true)
		"wake":
			b = _buf(0.3)
			_add_tone(b, 0, 0.28, 0.3, 200.0, 500.0, 6.0, 3)
		"victory":
			b = _buf(1.4)
			var mel := [[0.0, 0], [0.12, 4], [0.24, 7], [0.36, 12], [0.6, 7], [0.72, 12]]
			for e in mel:
				var f := _note(e[1] + 3)
				_add_tone(b, e[0], 0.5, 0.22, f, f, 5.0, 1)
				_add_tone(b, e[0], 0.5, 0.2, f * 0.5, f * 0.5, 5.0, 2)
		"fail":
			b = _buf(1.4)
			var mel2 := [[0.0, -2], [0.3, -3], [0.6, -4], [0.9, -5]]
			for e2 in mel2:
				var f2 := _note(e2[1] - 12)
				var d := 0.5 if e2[0] < 0.9 else 0.5
				_add_tone(b, e2[0], d, 0.3, f2, f2 * (0.94 if e2[0] >= 0.9 else 1.0), 3.0, 3, 0.02)
		"shotgun":
			b = _buf(0.45)
			_add_noise(b, 0, 0.4, 1.0, 9.0, 0.35)
			_add_tone(b, 0, 0.3, 1.0, 120.0, 38.0, 9.0)
			_add_noise(b, 0, 0.03, 0.7, 70.0, 1.0, true)
		"laser":
			b = _buf(0.2)
			_add_tone(b, 0, 0.2, 0.22, 880.0, 860.0, 4.0, 3)
			_add_tone(b, 0, 0.2, 0.18, 1320.0, 1300.0, 4.0, 1)
			_add_tone(b, 0, 0.2, 0.2, 110.0, 110.0, 2.0, 1)
		"rocket":
			b = _buf(0.5)
			var n4 := b.size()
			var y4 := 0.0
			for i in n4:
				var t4 := float(i) / n4
				y4 += (randf_range(-1, 1) - y4) * (0.15 + 0.5 * t4)
				b[i] = y4 * (1.0 - t4) * 0.9
			_add_tone(b, 0, 0.2, 0.6, 200.0, 60.0, 12.0)
		"explosion":
			b = _buf(1.1)
			_add_noise(b, 0, 1.0, 1.0, 4.0, 0.12)
			_add_tone(b, 0, 0.9, 1.0, 70.0, 28.0, 3.5)
			_add_noise(b, 0, 0.1, 0.7, 30.0, 0.9)
		"groan":
			b = _buf(0.7)
			var n5 := b.size()
			var ph := 0.0
			for i in n5:
				var t5 := float(i) / RATE
				var f5 := 210.0 + 40.0 * sin(t5 * 9.0) - t5 * 60.0
				ph += f5 / RATE
				var v5 := sin(TAU * ph) * 0.5 + sin(TAU * ph * 2.0) * 0.25 + sin(TAU * ph * 3.0) * 0.12
				b[i] = v5 * sin(PI * t5 / 0.7) * 0.35
		"splat":
			b = _buf(0.3)
			_add_tone(b, 0, 0.12, 0.6, 600.0, 1400.0, 14.0, 2)
			_add_noise(b, 0, 0.12, 0.5, 30.0, 0.5)
			_add_tone(b, 0.06, 0.2, 0.25, 1600.0, 2400.0, 10.0, 0)
		"pickup":
			b = _buf(0.7)
			var notes2 := [0.0, 7.0, 12.0, 16.0, 19.0]
			for i in notes2.size():
				_add_tone(b, i * 0.06, 0.4, 0.22, _note(notes2[i] + 3), _note(notes2[i] + 3), 7.0, 1)
				_add_bell(b, i * 0.06, 0.4, 0.08, _note(notes2[i] + 15))
		"alarm":
			b = _buf(1.6)
			for k in 4:
				_add_tone(b, k * 0.4, 0.38, 0.3, 700.0, 1100.0, 1.0, 1, 0.02)
		"clank":
			b = _buf(0.25)
			_add_tone(b, 0, 0.2, 0.4, 1800.0, 1700.0, 18.0, 0)
			_add_tone(b, 0, 0.2, 0.3, 2650.0, 2600.0, 22.0, 0)
			_add_noise(b, 0, 0.04, 0.6, 80.0, 1.0, true)
			_add_tone(b, 0, 0.1, 0.5, 160.0, 80.0, 30.0)
		"transform":
			b = _buf(1.2)
			_add_tone(b, 0, 1.2, 0.35, 120.0, 900.0, 0.8, 3, 0.05)
			var n6 := b.size()
			var y6 := 0.0
			for i in n6:
				var t6 := float(i) / n6
				y6 += (randf_range(-1, 1) - y6) * (0.05 + 0.5 * t6)
				b[i] += y6 * t6 * 0.4
		"powerup":
			b = _buf(1.0)
			var notes3 := [0.0, 4.0, 7.0, 12.0, 16.0, 19.0, 24.0]
			for i in notes3.size():
				_add_tone(b, i * 0.05, 0.6, 0.18, _note(notes3[i]), _note(notes3[i]), 4.0, 1)
			_add_bell(b, 0.35, 0.65, 0.3, _note(24))
		"shout_fire":
			# 不是真人声：一个短促有力的“FAI-YAH!”式合成喊叫 + 爆发
			b = _buf(0.9)
			_add_noise(b, 0, 0.09, 0.7, 20.0, 1.0, true)
			var n7 := b.size()
			var ph7 := 0.0
			for i in n7:
				var t7 := float(i) / RATE
				if t7 < 0.07 or t7 > 0.62:
					continue
				var k7 := (t7 - 0.07) / 0.55
				var f7 := lerpf(300.0, 210.0, k7) * (1.0 + 0.02 * sin(t7 * 40.0))
				ph7 += f7 / RATE
				var x7 := fmod(ph7, 1.0)
				var saw := 2.0 * x7 - 1.0
				var form := sin(TAU * ph7 * lerpf(3.0, 2.0, k7)) * 0.5 + sin(TAU * ph7 * 7.0) * 0.2
				var env7 := minf(1.0, (t7 - 0.07) * 30.0) * (1.0 - k7 * 0.6)
				b[i] += (saw * 0.35 + form * 0.45) * env7 * 0.8
			_add_tone(b, 0.05, 0.5, 0.9, 90.0, 35.0, 5.0)
		"music_wave":
			b = _music_wave()
		"music_menu":
			b = _music_menu()
		"music_combat":
			b = _music_combat()
		_:
			return PackedFloat32Array()
	return b


## 菜单音乐：慢速 lo-fi 和弦 + 轻鼓
func _music_menu() -> PackedFloat32Array:
	var bpm := 84.0
	var beat := 60.0 / bpm
	var bars := 4
	var b := _buf(beat * 4 * bars)
	var chords := [[-12, -5, 0, 3], [-16, -9, -4, 0], [-19, -12, -7, -3], [-14, -7, -2, 2]]
	for bar in bars:
		var t0 := bar * 4 * beat
		for semi in chords[bar]:
			var f := _note(semi - 12)
			_add_tone(b, t0, beat * 4, 0.07, f, f, 0.5, 2, 0.15)
			_add_tone(b, t0, beat * 4, 0.03, f * 2.0, f * 2.0, 0.8, 0, 0.2)
		var root := _note(chords[bar][0] - 24)
		_add_tone(b, t0, beat * 2, 0.22, root, root, 1.2, 0, 0.02)
		_add_tone(b, t0 + beat * 2.5, beat * 1.5, 0.18, root, root, 1.5, 0, 0.02)
		for k in 4:
			var tb := t0 + k * beat
			if k % 2 == 0:
				_add_tone(b, tb, 0.25, 0.4, 110.0, 42.0, 14.0)
			else:
				_add_noise(b, tb, 0.18, 0.12, 18.0, 0.35)
			_add_noise(b, tb + beat * 0.5, 0.05, 0.05, 60.0, 1.0, true)
	return b


## 战斗音乐：紧张的贝斯 + 鼓点
func _music_combat() -> PackedFloat32Array:
	var bpm := 118.0
	var beat := 60.0 / bpm
	var bars := 4
	var b := _buf(beat * 4 * bars)
	var bass := [0, 0, 12, 0, 3, 0, 10, 7]
	var roots := [-24, -24, -27, -22]
	for bar in bars:
		var t0 := bar * 4 * beat
		for k in 8:
			var tb := t0 + k * beat * 0.5
			var f := _note(roots[bar] + bass[k] - 12)
			_add_tone(b, tb, beat * 0.45, 0.2, f, f, 7.0, 3, 0.004)
			_add_tone(b, tb, beat * 0.45, 0.14, f * 0.5, f * 0.5, 6.0, 0, 0.004)
			_add_noise(b, tb, 0.04, 0.06 if k % 2 == 0 else 0.035, 70.0, 1.0, true)
		for k2 in 4:
			var tk := t0 + k2 * beat
			if k2 == 0 or k2 == 2 or (k2 == 3 and bar % 2 == 1):
				_add_tone(b, tk, 0.22, 0.55, 140.0, 40.0, 16.0)
			if k2 == 1 or k2 == 3:
				_add_noise(b, tk, 0.2, 0.3, 16.0, 0.5)
				_add_tone(b, tk, 0.1, 0.15, 220.0, 160.0, 25.0, 2)
		if bar % 2 == 1:
			var stab := _note(roots[bar] + 12)
			_add_tone(b, t0 + beat * 3.5, beat * 0.4, 0.08, stab, stab, 8.0, 1)
	return b


## 僵尸潮音乐：更快、更燃
func _music_wave() -> PackedFloat32Array:
	var bpm := 150.0
	var beat := 60.0 / bpm
	var bars := 4
	var b := _buf(beat * 4 * bars)
	var bass := [0, 12, 0, 10, 0, 7, 0, 12]
	var roots := [-24, -24, -21, -26]
	for bar in bars:
		var t0 := bar * 4 * beat
		for k in 8:
			var tb := t0 + k * beat * 0.5
			var f := _note(roots[bar] + bass[k] - 12)
			_add_tone(b, tb, beat * 0.42, 0.22, f, f, 8.0, 3, 0.003)
			_add_tone(b, tb, beat * 0.42, 0.14, f * 0.5, f * 0.5, 6.0, 1, 0.003)
			_add_noise(b, tb + beat * 0.25, 0.03, 0.05, 80.0, 1.0, true)
		for k2 in 4:
			var tk := t0 + k2 * beat
			_add_tone(b, tk, 0.2, 0.6, 150.0, 40.0, 18.0)
			if k2 % 2 == 1:
				_add_noise(b, tk, 0.18, 0.35, 18.0, 0.55)
		var lead := [12, 15, 19, 17]
		var lf := _note(roots[bar] + lead[bar] + 12)
		_add_tone(b, t0, beat * 1.5, 0.07, lf, lf, 2.0, 1, 0.01)
		_add_tone(b, t0 + beat * 2, beat * 1.5, 0.07, lf * 0.89, lf * 0.89, 2.0, 1, 0.01)
	return b
