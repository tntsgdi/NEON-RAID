extends Node
## 背景音乐（tools/make_music.py 合成）：探索层、战斗层、高潮层同长同步循环，按 intensity 交叉淡变。
##   intensity 0 → 只有探索层；0.5 → 战斗层进来；1 → 高潮层（主旋律、切音、嗵鼓）也叠上
## 神经超频慢动作时整体降调；重击时让位几百毫秒，让打击声冒出来。
## 第 1 关五个区域各有一套三层（r1_..r5_：调性、速度、鼓型都不同），play_set 切换时淡出再淡入。

const VOLUME_DB := -8.0

## 目标强度 0..1
var intensity := 0.0

var _cur := 0.0
var _layers: Array[AudioStreamPlayer] = []
var _pitch := 1.0
var _duck := 0.0
var _duck_rate := 40.0
var _sting: AudioStreamPlayer
var _stings := {}
## 当前这套配乐（"" = 训练场用的默认一套）
var current_set := ""
var _want_set := ""
## 换套时的淡出淡入（1 = 正常音量）
var _fade := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		add_child(p)
		_layers.append(p)
	_load_set("")
	_sting = AudioStreamPlayer.new()
	_sting.bus = &"Music"
	add_child(_sting)
	for n in ["wave", "clear"]:
		_stings[n] = load("res://assets/music/sting_%s.ogg" % n)
	_apply()


## 换一套配乐（"r1".."r5"，"" = 默认）：先 0.5 秒淡出，再从头淡入
func play_set(name: String) -> void:
	if name == _want_set:
		return
	_want_set = name
	if not _layers[0].playing:
		_load_set(name)


func _load_set(name: String) -> void:
	current_set = name
	_want_set = name
	# 002 检查站用的就是默认那套（D 小调 128），不另存一份
	var pre := "" if name == "" or name == "r2" else name + "_"
	var names := ["explore", "combat", "peak"]
	for i in 3:
		var s: AudioStreamOggVorbis = load("res://assets/music/%s%s.ogg" % [pre, names[i]])
		s.loop = true
		_layers[i].stream = s
	for p in _layers:
		p.play()


## 过渡短句（"wave" 波次开始、"clear" 清场）：叠在循环上播一次，循环暂时让位
func sting(name: String) -> void:
	if not _stings.has(name):
		return
	_sting.stream = _stings[name]
	_sting.volume_db = VOLUME_DB + 2.0
	_sting.play()
	duck(5.0, 1.5)


## 让位：音乐压低 db 分贝，然后在 sec 秒内恢复
func duck(db: float, sec: float) -> void:
	_duck = maxf(_duck, db)
	_duck_rate = db / maxf(sec, 0.01)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.0001)
	_cur = move_toward(_cur, intensity, real * (1.0 if intensity > _cur else 0.35))
	var want_pitch := 0.8 if TimeFx.slowmo_active() else 1.0
	_pitch = move_toward(_pitch, want_pitch, real * 2.0)
	_duck = move_toward(_duck, 0.0, real * _duck_rate)
	if _want_set != current_set:
		_fade = move_toward(_fade, 0.0, real * 2.0)
		if _fade <= 0.0:
			_load_set(_want_set)
	else:
		_fade = move_toward(_fade, 1.0, real * 1.2)
	_apply()


func _apply() -> void:
	var gains := [
		lerpf(0.8, 0.35, _cur),
		clampf(_cur * 2.0, 0.0, 1.0),
		clampf((_cur - 0.6) / 0.4, 0.0, 1.0),
	]
	for i in _layers.size():
		_layers[i].volume_db = VOLUME_DB - _duck + linear_to_db(maxf(gains[i] * _fade, 0.0001))
		_layers[i].pitch_scale = _pitch
