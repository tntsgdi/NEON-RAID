extends Node
## 注册输入动作。按键只在这里改；玩家逻辑只读 PlayerInput，不直接碰按键。

const KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE],
	"dash": [KEY_L],
	"run": [KEY_SHIFT],
	"slash_key": [KEY_J],
	"shoot_key": [KEY_K],
	"possess": [KEY_E, KEY_U],
	"slide": [KEY_C],
	"restart": [KEY_R],
	"tuning": [KEY_F1],
	"language": [KEY_F2],
	"render_mode": [KEY_F3],
	"switch_level": [KEY_F4],
	"settings": [KEY_ESCAPE],
}

## 手柄：A 跳、B 滑铲、X 挥刀、RB 冲刺、RT 射击（扳机在下面的 AXES 里）、Start 设置、Back 重来
const PAD := {
	"jump": [JOY_BUTTON_A],
	"slide": [JOY_BUTTON_B],
	"slash": [JOY_BUTTON_X],
	"possess": [JOY_BUTTON_Y],
	"dash": [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER],
	"settings": [JOY_BUTTON_START],
	"restart": [JOY_BUTTON_BACK],
}
## [动作, 轴, 方向]
const AXES := [
	["move_left", JOY_AXIS_LEFT_X, -1.0],
	["move_right", JOY_AXIS_LEFT_X, 1.0],
	["move_up", JOY_AXIS_LEFT_Y, -1.0],
	["move_down", JOY_AXIS_LEFT_Y, 1.0],
	["shoot", JOY_AXIS_TRIGGER_RIGHT, 1.0],
	["aim_left", JOY_AXIS_RIGHT_X, -1.0],
	["aim_right", JOY_AXIS_RIGHT_X, 1.0],
	["aim_up", JOY_AXIS_RIGHT_Y, -1.0],
	["aim_down", JOY_AXIS_RIGHT_Y, 1.0],
]

const MOUSE := {
	"slash": [MOUSE_BUTTON_RIGHT],
	"shoot": [MOUSE_BUTTON_LEFT],
}


func _ready() -> void:
	for action in KEYS:
		_ensure(action)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action in MOUSE:
		_ensure(action)
		for button in MOUSE[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	# J / K 和鼠标右键 / 左键是同一个动作
	for pair in [["slash", "slash_key"], ["shoot", "shoot_key"]]:
		for ev in InputMap.action_get_events(pair[1]):
			InputMap.action_add_event(pair[0], ev)
	for action in PAD:
		for button in PAD[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	for a in AXES:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0], 0.3)
		var ev := InputEventJoypadMotion.new()
		ev.axis = a[1]
		ev.axis_value = a[2]
		InputMap.action_add_event(a[0], ev)


func _ensure(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action, 0.3)
