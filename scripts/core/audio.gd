extends Node
## 音效播放。素材来自 Sonniss GDC 音效库（tools/build_sfx.py 切好放在 assets/sfx/）。
## play("hit") 会在 hit_1、hit_2 这类同名变体里随机挑一个，避免重复感。

const NAMES := [
	"swing_1", "swing_2", "swing_3", "swing_heavy",
	"hit_1", "hit_2", "hit_heavy", "break",
	"dash", "walljump", "land", "slide",
	"shot", "enemy_shot", "deflect", "overclock", "hurt", "charge", "shield_block",
	"sprint", "possess",
	"ui_tick", "ui_open", "ui_card", "ui_ready",
	"mut_grow", "rail_charge", "rail_fire", "swarm", "grapple",
]

var _streams := {}
var _groups := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in 24:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)
	for n in NAMES:
		var s: AudioStream = load("res://assets/sfx/%s.wav" % n)
		_streams[n] = s
		var base: String = n.rstrip("0123456789").trim_suffix("_")
		if base != n:
			if not _groups.has(base):
				_groups[base] = []
			_groups[base].append(n)


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var key := sound
	if not _streams.has(key) and _groups.has(key):
		key = _groups[key].pick_random()
	if not _streams.has(key):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[key]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()
