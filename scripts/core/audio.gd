extends Node
## 程序合成的占位音效（灰盒阶段用，M7 换正式音效）。启动时一次合成好，之后只播放。

const RATE := 22050

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams = {
		"swing": _wav(_swing(0.14, 1.0, 11)),
		"swing_heavy": _wav(_swing(0.22, 1.4, 12)),
		"hit": _wav(_hit(0.14, 1.0, 21)),
		"hit_heavy": _wav(_hit(0.24, 1.6, 22)),
		"break": _wav(_break(0.45)),
		"dash": _wav(_whoosh(0.2, 0.15, 0.6, 31)),
		"jump": _wav(_blip(0.09, 260.0, 520.0, 0.35)),
		"walljump": _wav(_blip(0.1, 200.0, 620.0, 0.45)),
		"land": _wav(_thump(0.12, 0.7)),
		"step": _wav(_thump(0.04, 0.25)),
		"slide": _wav(_whoosh(0.3, 0.05, 0.25, 41)),
	}


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## 挥刀破空：带通噪声，频率从高往低扫
func _swing(dur: float, gain: float, seed_value: int) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		var k := lerpf(0.6, 0.06, t)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * k
		lp2 += (lp - lp2) * k
		var env := minf(t * 10.0, 1.0) * pow(1.0 - t, 1.6)
		out[i] = tanh((lp - lp2) * env * 3.0 * gain) * 0.8
	return out


## 金属命中：尖锐的咔 + 下沉的重击 + 碎响
func _hit(dur: float, gain: float, seed_value: int) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var phase := 0.0
	var ring := 0.0
	var lp := 0.0
	for i in n:
		var s := float(i) / RATE
		var t := float(i) / n
		phase += TAU * lerpf(190.0, 45.0, t) / RATE
		ring += TAU * 1250.0 / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		var click := rng.randf_range(-1.0, 1.0) * exp(-s * 300.0)
		var body := sin(phase) * exp(-s * 18.0)
		var crunch := lp * exp(-s * 35.0)
		var metal := sin(ring) * exp(-s * 30.0) * 0.25
		out[i] = tanh((click * 0.9 + body * 1.1 + crunch * 0.8 + metal) * 1.4 * gain) * 0.9
	return out


## 打碎：碎裂噪声 + 两个衰减的金属泛音
func _break(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	var lp := 0.0
	for i in n:
		var s := float(i) / RATE
		var t := float(i) / n
		p1 += TAU * 880.0 / RATE
		p2 += TAU * 1390.0 / RATE
		p3 += TAU * lerpf(120.0, 35.0, t) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.5
		var grit := lp * exp(-s * 9.0) * (0.6 + 0.4 * sin(s * 190.0))
		var metal := (sin(p1) + sin(p2) * 0.7) * exp(-s * 12.0) * 0.3
		var boom := sin(p3) * exp(-s * 10.0)
		out[i] = tanh((grit + metal + boom) * 1.6) * 0.9
	return out


## 风声：噪声，强度先升后降
func _whoosh(dur: float, k_lo: float, gain: float, seed_value: int) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		lp += (rng.randf_range(-1.0, 1.0) - lp) * lerpf(k_lo, 0.4, sin(t * PI))
		out[i] = lp * sin(t * PI) * gain * 2.0
	return out


## 短促的弹跳音
func _blip(dur: float, f0: float, f1: float, gain: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(f0, f1, t) / RATE
		out[i] = (sin(phase) * 0.7 + signf(sin(phase)) * 0.15) * pow(1.0 - t, 2.0) * gain
	return out


## 落地闷响
func _thump(dur: float, gain: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(110.0, 40.0, t) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.2
		out[i] = (sin(phase) + lp * 0.8) * pow(1.0 - t, 3.0) * gain
	return out
