extends SceneTree
## 机器人通关测试：通关机器人（tests/bot_input.gd）从起点打到出口，记录每个区域的游戏内用时、
## 死亡 / 掉坑次数，看能不能打通、用时是否落在 40–90 秒的目标里。
## 运行：Godot --headless --path . -s tests/bot_run.gd --fixed-fps 60 [-- --region 2] [-- --verbose]
## 不碰键鼠、不写存档（Progress / Settings 在测试里都不写）。

const LIMIT := 240.0
## 机器人是"完美玩家"（不犹豫、不读提示、路线最优），实际玩家首玩会慢不少。
## 设计目标是玩家每个区域 40–90 秒；机器人这边只用一个宽的参考区间提醒"明显太短 / 太长"。
const TARGET := Vector2(12.0, 60.0)

var main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var args := OS.get_cmdline_user_args()
	var only := -1
	if args.has("--region"):
		only = int(args[args.find("--region") + 1]) - 1
	var verbose := args.has("--verbose")
	var all_ok := true
	var report := []
	for i in 5:
		if only >= 0 and i != only:
			continue
		main.load_level("d13", i)
		await physics_frame
		var region = main.region
		var bot = load("res://tests/bot_input.gd").new(region, main.controller)
		main.controller.input = bot
		main.player.input = bot
		var deaths := 0
		var hp_last: int = main.player.hp
		var t := 0.0
		var cleared := false
		var last_x := -1.0
		var sample := 0.0
		while t < LIMIT:
			await physics_frame
			t += 1.0 / 120.0
			if main.region != region:
				cleared = true
				break
			if main.finished:
				cleared = true
				break
			# 被打坏 / 掉坑都会回检查点：用"位置突然往回跳"粗略计数
			var body = main._body()
			if body.global_position.x < last_x - 200.0:
				deaths += 1
			last_x = body.global_position.x
			if verbose:
				sample += 1.0 / 120.0
				if sample >= 2.0:
					sample = 0.0
					print("  t=%5.1f %-14s x=%6.0f y=%5.0f enemies=%d move=%s hunt=%s" % [t, body.get_script().resource_path.get_file(), body.global_position.x, body.global_position.y, region.enemies_left(), str(bot.move), str(bot._hunt)])
		var time: float = main.run_time if cleared else t
		var ok: bool = cleared
		var in_target := time >= TARGET.x and time <= TARGET.y
		report.append("区域 %03d：%s  用时 %5.1f 秒%s  回检查点 %d 次  进度 x=%.0f/%.0f  剩余敌人 %d" % [i + 1, "通关" if ok else "没打通", time, "" if in_target else "（机器人参考区间 12–60 秒）", deaths, main._body().global_position.x, region.finish_x, region.enemies_left()])
		if verbose:
			for l in bot.log:
				print("    ", l)
		all_ok = all_ok and ok
		main.controller.input = load("res://scripts/player/device_input.gd").new()
		main.player.input = main.controller.input
		main.load_level("range")
		await physics_frame
	for l in report:
		print(l)
	print("BOT %s" % ("PASS" if all_ok else "FAIL"))
	quit(0 if all_ok else 1)
