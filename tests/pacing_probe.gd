extends SceneTree
## 帧节奏探针：实时（不固定帧率）跑一段，记录每个渲染帧主角在画面上的位置变化。

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	print("refresh=", DisplayServer.screen_get_refresh_rate(), " physics=", Engine.physics_ticks_per_second)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var p = main.player
	main.place(Vector2(100, 0), Vector2(260, 0))
	p.input = load("res://scripts/player/scripted_input.gd").new([{"frames": 600, "move": Vector2(1, 0)}])
	var last := Vector2.ZERO
	var deltas := []
	for i in 150:
		await process_frame
		var sp: Vector2 = p.get_global_transform_with_canvas().origin
		var wp: Vector2 = p.global_position
		if i > 60:
			deltas.append("%.1f/%.1f" % [sp.x - last.x, wp.x])
		last = sp
	print("screen dx / world x per frame: ", " ".join(deltas.slice(0, 50)))
	quit(0)
