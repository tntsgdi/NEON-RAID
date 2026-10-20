extends SceneTree
## 挥刀卡顿探针：真实帧率下连续挥刀打训练机，记录每帧耗时（区分命中停顿和真正的掉帧）。
## 运行：tools/run_test.sh tests/slash_perf_probe.gd --disable-vsync

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.place(Vector2(352, 0))
	for i in 30:
		await process_frame
	var steps := [{"frames": 1, "move": Vector2(1, 0)}]
	for i in 9:
		steps.append({"frames": 1, "press": ["slash"]})
		steps.append({"frames": 14})
	var inp = load("res://scripts/player/scripted_input.gd").new(steps)
	main.controller.input = inp
	main.player.input = inp
	var last := Time.get_ticks_usec()
	var spikes := []
	var frames := 0
	var slow_frames := 0
	while not inp.done and frames < 2000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		frames += 1
		if ms > 12.0:
			spikes.append("%.1fms@%d(ts=%.2f)" % [ms, frames, Engine.time_scale])
		if Engine.time_scale < 0.5:
			slow_frames += 1
	print("frames=%d  real-time spikes(>12ms)=%s  frames in hitstop=%d" % [frames, str(spikes), slow_frames])
	quit(0)
