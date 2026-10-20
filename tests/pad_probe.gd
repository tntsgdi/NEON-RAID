extends SceneTree
## 手柄探针：用模拟的手柄事件（不是真手柄）检查右摇杆瞄准和 A 键起跳走的是 DeviceInput 这条路。

func _initialize() -> void:
	_run.call_deferred()

func _ev_axis(axis: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	Input.parse_input_event(e)

func _ev_button(b: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var p = main.player
	main.place(Vector2(300, 0))
	for i in 10:
		await physics_frame
	_ev_axis(JOY_AXIS_RIGHT_X, -1.0)
	_ev_axis(JOY_AXIS_RIGHT_Y, -1.0)
	for i in 3:
		await physics_frame
	print("aim after right stick up-left: ", p.aim.snapped(Vector2(0.01, 0.01)))
	_ev_button(JOY_BUTTON_A, true)
	for i in 3:
		await physics_frame
	print("vy after A: ", round(p.velocity.y), " state ", p.state)
	_ev_button(JOY_BUTTON_A, false)
	_ev_axis(JOY_AXIS_LEFT_X, 1.0)
	for i in 30:
		await physics_frame
	print("vx with left stick right: ", round(p.velocity.x))
	quit(0)
