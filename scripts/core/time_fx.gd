extends Node
## 时间效果统一在这里管：命中停顿和神经超频慢动作同时存在时取最慢的那个。
## 自己累计"未缩放"的帧时间，不受 Engine.time_scale 影响；固定帧率的测试里也和实机一致。

const HITSTOP_SCALE := 0.03

var _clock := 0.0
var _hitstop_until := 0.0
var _slow_until := 0.0
var _slow_scale := 1.0
## 慢动作的来源："possess" = 夺壳光流（不算神经超频，不触发超频的提示、色差和染色）
var _slow_tag := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100


func hitstop(sec: float) -> void:
	_hitstop_until = maxf(_hitstop_until, _clock + sec)
	_apply()


func slowmo(sec: float, scale: float, tag := "") -> void:
	if tag != "" and _clock < _slow_until and (_slow_tag == "" or (tag == "kill" and _slow_tag == "possess")):
		return  # 超频慢动作期间夺壳 / 终结：不打断超频；终结一击也不打断夺壳光流
	_slow_until = maxf(_slow_until, _clock + sec)
	_slow_scale = scale
	_slow_tag = tag
	_apply()


func slowmo_active() -> bool:
	return _clock < _slow_until and _slow_tag == ""


func reset() -> void:
	_hitstop_until = 0.0
	_slow_until = 0.0
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	_clock += delta / maxf(Engine.time_scale, 0.0001)
	_apply()


func _apply() -> void:
	var s := 1.0
	if _clock < _slow_until:
		s = _slow_scale
	if _clock < _hitstop_until:
		s = minf(s, HITSTOP_SCALE)
	Engine.time_scale = s
