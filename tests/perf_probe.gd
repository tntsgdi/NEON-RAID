extends SceneTree
## 性能探针：战斗训练场第 3 波（敌人最多、子弹/光源/雨/零件都在）时的帧时间。
## 运行：tools/run_test.sh tests/perf_probe.gd --disable-vsync

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.load_level("arena")
	var arena = main.arena
	arena.auto_waves = false
	for s in arena.WAVES[1] + arena.WAVES[2]:
		arena.spawn(s[0], s[2], s[3], s[1])
	main.place(Vector2(-100, 0))
	var times := []
	var last := Time.get_ticks_usec()
	for i in 600:
		await process_frame
		var now := Time.get_ticks_usec()
		if i > 60:
			times.append((now - last) / 1000.0)
		last = now
		if i % 90 == 0:
			for e in arena.enemies:
				if is_instance_valid(e) and e.alive() and randf() < 0.3:
					e.take_hit(Vector2(1, -0.2), 99, "slash")
	times.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	print("frames %d avg %.2f ms (%.0f fps) p95 %.2f ms max %.2f ms bullets %d" % [times.size(), avg, 1000.0 / avg, times[int(times.size() * 0.95)], times[-1], main.get_tree().get_nodes_in_group("enemy_bullets").size()])
	quit(0)
