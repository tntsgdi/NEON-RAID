class_name ScriptedInput
extends PlayerInput
## 测试用：按物理帧回放一段输入。
## 每段：{frames 或 until(Callable(body)->bool) + max, move, hold:[...], press:[...], aim, walk, keys}
## 默认按住跑步键（walk: true 表示走路）；默认用给定的 aim 瞄准（keys: true 表示纯键盘瞄准）
## press 只在该段第一帧触发；按下的键在那一帧也算按住。

var steps: Array
var done := false
var _step := 0
var _frame := 0


func _init(script_steps: Array) -> void:
	steps = script_steps


func poll(body: Node2D) -> void:
	jump_pressed = false
	dash_pressed = false
	slide_pressed = false
	slash_pressed = false
	shoot_pressed = false
	possess_pressed = false
	while _step < steps.size():
		var cur: Dictionary = steps[_step]
		var finished := false
		if cur.has("until"):
			finished = _frame > 0 and (cur.until.call(body) or _frame >= int(cur.get("max", 600)))
		else:
			finished = _frame >= int(cur.get("frames", 1))
		if not finished:
			break
		_step += 1
		_frame = 0
	if _step >= steps.size():
		done = true
		move = Vector2.ZERO
		jump_held = false
		slide_held = false
		return
	var s: Dictionary = steps[_step]
	move = s.get("move", Vector2.ZERO)
	aim = s.get("aim", aim)
	aim_keys = s.get("keys", false)
	run_held = not s.get("walk", false)
	var hold: Array = s.get("hold", [])
	jump_held = "jump" in hold
	slide_held = "slide" in hold
	if _frame == 0:
		var press: Array = s.get("press", [])
		jump_pressed = "jump" in press
		dash_pressed = "dash" in press
		slide_pressed = "slide" in press
		slash_pressed = "slash" in press
		shoot_pressed = "shoot" in press
		possess_pressed = "possess" in press
		jump_held = jump_held or jump_pressed
		slide_held = slide_held or slide_pressed
	_frame += 1
