extends Node
## 注册输入动作。按键只在这里改；玩家逻辑只读 PlayerInput，不直接碰按键。

const KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE, KEY_W],
	"dash": [KEY_SHIFT],
	"slide": [KEY_CTRL, KEY_S],
	"restart": [KEY_R],
	"tuning": [KEY_F1],
	"language": [KEY_F2],
}

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


func _ensure(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action, 0.3)
