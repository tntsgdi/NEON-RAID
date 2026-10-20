class_name DeviceInput
extends PlayerInput
## 键鼠 / 手柄输入。瞄准：右摇杆推出去就用右摇杆，否则胸口指向鼠标。


var _pad_aim := false


func poll(body: Node2D) -> void:
	move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	jump_pressed = Input.is_action_just_pressed("jump")
	jump_held = Input.is_action_pressed("jump")
	dash_pressed = Input.is_action_just_pressed("dash")
	slide_pressed = Input.is_action_just_pressed("slide")
	slide_held = Input.is_action_pressed("slide")
	slash_pressed = Input.is_action_just_pressed("slash")
	shoot_pressed = Input.is_action_just_pressed("shoot")
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > 0.35:
		aim = stick.normalized()
		_pad_aim = true
		return
	if _pad_aim and Input.get_last_mouse_velocity().length() < 1.0:
		return  # 用手柄时鼠标不动，就保持手柄最后的方向
	_pad_aim = false
	var to_mouse := body.get_global_mouse_position() - (body.global_position + Player.CHEST)
	if to_mouse.length() > 4.0:
		aim = to_mouse.normalized()
