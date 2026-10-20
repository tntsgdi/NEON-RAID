class_name DeviceInput
extends PlayerInput
## 键鼠输入。瞄准方向 = 胸口指向鼠标。


func poll(body: Node2D) -> void:
	move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	jump_pressed = Input.is_action_just_pressed("jump")
	jump_held = Input.is_action_pressed("jump")
	dash_pressed = Input.is_action_just_pressed("dash")
	slide_pressed = Input.is_action_just_pressed("slide")
	slide_held = Input.is_action_pressed("slide")
	slash_pressed = Input.is_action_just_pressed("slash")
	shoot_pressed = Input.is_action_just_pressed("shoot")
	var to_mouse := body.get_global_mouse_position() - (body.global_position + Player.CHEST)
	if to_mouse.length() > 4.0:
		aim = to_mouse.normalized()
