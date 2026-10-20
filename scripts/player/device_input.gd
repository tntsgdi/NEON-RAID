class_name DeviceInput
extends PlayerInput
## 键鼠 / 手柄输入。
##   走/跑：不按 Shift 走，按住 Shift 跑；轻点 Shift（0.15 秒内松开）= 冲刺；L 键冲刺；手柄左摇杆推到底 = 跑
##   瞄准：右摇杆推出去用右摇杆；最近 1.5 秒动过鼠标用鼠标；否则是纯键盘瞄准（由机体用锁定目标 / 面朝方向）

const TAP_TIME := 0.15
const MOUSE_IDLE := 1.5

## 自己累计的物理帧时间（不用墙上时钟：固定帧率的测试和慢动作里也准）
var _clock := 0.0
var _shift_down_at := -1.0
var _last_mouse_at := -100.0
var _last_mouse_pos := Vector2.ZERO
var _pad_aim := false


func poll(body: Node2D) -> void:
	_clock += body.get_physics_process_delta_time()
	var now := _clock
	move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	jump_pressed = Input.is_action_just_pressed("jump")
	jump_held = Input.is_action_pressed("jump")
	slide_pressed = Input.is_action_just_pressed("slide")
	slide_held = Input.is_action_pressed("slide")
	slash_pressed = Input.is_action_just_pressed("slash")
	shoot_pressed = Input.is_action_just_pressed("shoot")
	possess_pressed = Input.is_action_just_pressed("possess")
	# Shift：按住超过 0.15 秒算跑，轻点算冲刺（松手时触发）
	dash_pressed = Input.is_action_just_pressed("dash")
	if Input.is_action_just_pressed("run"):
		_shift_down_at = now
	if Input.is_action_just_released("run"):
		if _shift_down_at >= 0.0 and now - _shift_down_at < TAP_TIME:
			dash_pressed = true
		_shift_down_at = -1.0
	var shift_run := Input.is_action_pressed("run") and _shift_down_at >= 0.0 and now - _shift_down_at >= TAP_TIME
	var stick_run := Input.get_connected_joypads().size() > 0 and move.length() > 0.85 and _stick_used()
	run_held = shift_run or stick_run

	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > 0.35:
		aim = stick.normalized()
		aim_keys = false
		_pad_aim = true
		return
	var mp := body.get_global_mouse_position()
	if Input.get_last_mouse_velocity().length() > 1.0 or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_last_mouse_at = now
		_pad_aim = false
	if _pad_aim:
		return  # 用手柄时鼠标不动，就保持手柄最后的方向
	if now - _last_mouse_at < MOUSE_IDLE:
		var to_mouse := mp - (body.global_position + Player.CHEST)
		if to_mouse.length() > 4.0:
			aim = to_mouse.normalized()
		aim_keys = false
	else:
		aim_keys = true


func _stick_used() -> bool:
	return absf(Input.get_joy_axis(0, JOY_AXIS_LEFT_X)) > 0.2 or absf(Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)) > 0.2
