extends Node
## 时间效果统一在这里管：命中停顿和神经超频慢动作同时存在时取最慢的那个。
## 自己累计"未缩放"的帧时间，不受 Engine.time_scale 影响；固定帧率的测试里也和实机一致。

const HITSTOP_SCALE := 0.03

var _clock := 0.0
var _hitstop_until := 0.0
var _slow_until := 0.0
var _slow_scale := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100


func hitstop(sec: float) -> void:
	_hitstop_until = maxf(_hitstop_until, _clock + sec)
	_apply()


func slowmo(sec: float, scale: float) -> void:
	_slow_until = maxf(_slow_until, _clock + sec)
	_slow_scale = scale
	_apply()


func slowmo_active() -> bool:
	return _clock < _slow_until


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
