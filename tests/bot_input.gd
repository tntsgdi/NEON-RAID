extends PlayerInput
## 通关机器人（反应式）：只看地形格子和附近的机体，像玩家一样按键，不读关卡脚本。
##   基础机体：一直往右跑；前面有窄沟就跳、头顶低就滑铲、高墙直接走上去；附近有敌人就砍，够不着就开枪；
##       前面是宽沟 → 走到意识中继旁，夺对面的侦察机；前面是警示墙 → 夺最近的重装机
##   重装机：往右走；贴到警示墙就冲撞，脚下有警示地板就砸地；敌人近了砸地 / 冲撞；遇到安保门 → 夺安保机
##   安保机：往右走，碰到台阶就跳；有敌人就开枪；遇到宽沟 → 去中继夺侦察机
##   侦察机：飞过沟，落到对岸地面上空继续往右飞，沿路开枪
##   光球：飞向最近的可夺机体
## 到了出口还有敌人（要求清场的区域）：转身去找剩下的敌人。

const CELL := 16.0

var region: Node
var controller: Node
var _t := 0.0
var _slash_cd := 0.0
var _shoot_cd := 0.0
var _possess_cd := 0.0
var _jump_cd := 0.0
var _act_cd := 0.0
var _stuck_t := 0.0
var _last_x := 0.0
var log: Array = []
## 到了出口还有敌人：锁定"清场"模式，直到敌人清光
var _hunt := false


func _init(r: Node, c: Node) -> void:
	region = r
	controller = c


func poll(body: Node2D) -> void:
	var dt := body.get_physics_process_delta_time()
	_t += dt
	_slash_cd = maxf(_slash_cd - dt, 0.0)
	_shoot_cd = maxf(_shoot_cd - dt, 0.0)
	_possess_cd = maxf(_possess_cd - dt, 0.0)
	_jump_cd = maxf(_jump_cd - dt, 0.0)
	_act_cd = maxf(_act_cd - dt, 0.0)
	jump_pressed = false
	dash_pressed = false
	slide_pressed = false
	slash_pressed = false
	shoot_pressed = false
	possess_pressed = false
	jump_held = false
	slide_held = false
	run_held = true
	aim_keys = false
	move = Vector2.ZERO
	# 卡住检测：3 秒没往前走就跳一下 / 换个方向试试
	if absf(body.global_position.x - _last_x) > 24.0:
		_last_x = body.global_position.x
		_stuck_t = 0.0
	else:
		_stuck_t += dt
	var goal_dir := _goal_dir(body)
	if not (body is Wisp) and _route_needs(body, goal_dir if goal_dir != 0 else 1):
		return
	if body is Wisp:
		_wisp(body)
	elif body is DroneBot:
		_drone(body, goal_dir)
	elif body is HeavyBot:
		_heavy(body, goal_dir)
	elif body is EnemyBot:
		_gunner(body, goal_dir)
	else:
		_strider(body, goal_dir)


## 往哪边走：默认往出口；到了出口还有敌人就去找最近的敌人
func _goal_dir(body: Node2D) -> int:
	var fx: float = region.finish_x + 24.0
	if body.global_position.x >= region.finish_x - 8.0 and region.data.get("require_clear", false) and region.enemies_left() > 0:
		_hunt = true
	if _hunt:
		if region.enemies_left() == 0:
			_hunt = false
		else:
			var e: Node2D = null
			var bd := 99999.0
			for c in region.required_enemies():
				var d: float = c.global_position.distance_to(body.global_position)
				if d < bd:
					bd = d
					e = c
			if e != null:
				var dx: float = e.global_position.x - body.global_position.x
				if absf(dx) < 20.0:
					return 0
				return 1 if dx > 0.0 else -1
	return 1 if body.global_position.x < fx else -1


func _feet(body: Node2D) -> Vector2:
	return body.global_position + Vector2(0, -2)


## 前方 n 格、离脚底 rows 格高的地方是不是实心
func _solid(body: Node2D, dir: int, cells: float, rows: float) -> bool:
	return region.solid_at(_feet(body) + Vector2(dir * cells * CELL, -rows * CELL))


## 前方第 cells 格脚下有没有地（往下找 depth 格）
func _ground_ahead(body: Node2D, dir: int, cells: float, depth := 6) -> bool:
	for d in depth:
		if region.solid_at(_feet(body) + Vector2(dir * cells * CELL, (d + 0.5) * CELL)):
			return true
	return false


## 前方 12 格内第一道沟：[离脚几格开始, 多宽（格）]；没有沟 = [99, 0]
func _gap_info(body: Node2D, dir: int) -> Array:
	for i in range(1, 13):
		if not _ground_ahead(body, dir, float(i), 14):
			var w := 0
			for j in range(i, i + 60):
				if _ground_ahead(body, dir, float(j), 14):
					break
				w += 1
			return [i, w]
	return [99, 0]


## 紧挨着的沟宽（格）：沟从 1–2 格内开始才算
func _gap_width(body: Node2D, dir: int) -> int:
	var g := _gap_info(body, dir)
	return g[1] if g[0] <= 2 else 0


func _char_ahead(body: Node2D, dir: int, cells: float, rows: float) -> String:
	return region.char_at(_feet(body) + Vector2(dir * cells * CELL, -rows * CELL))


func _nearest_enemy(body: Node2D, within: float) -> Node2D:
	var best: Node2D = null
	var bd := within
	for e in body.get_tree().get_nodes_in_group("enemy"):
		if not e.alive() or e == body:
			continue
		var d: float = e.global_position.distance_to(body.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _nearest_possessable(body: Node2D, cls: String, within: float) -> Node2D:
	var best: Node2D = null
	var bd := within
	for n in body.get_tree().get_nodes_in_group("possessable"):
		if n == body or not n.alive():
			continue
		if cls != "" and not n.get_script().resource_path.contains(cls):
			continue
		var d: float = n.global_position.distance_to(body.global_position)
		if d < bd:
			bd = d
			best = n
	return best


func _try_possess(body: Node2D, target: Node2D) -> bool:
	if target == null or _possess_cd > 0.0 or controller.cooldown > 0.0:
		return false
	aim = (target.center() - (body.global_position + Vector2(0, -18))).normalized()
	if target.center().distance_to(body.global_position + Vector2(0, -18)) > controller.reach():
		return false
	possess_pressed = true
	_possess_cd = 0.5
	log.append("possess %s at %.0f" % [target.get_script().resource_path.get_file(), body.global_position.x])
	return true


func _relay_near(body: Node2D, within: float) -> Node2D:
	for r in body.get_tree().get_nodes_in_group("relay"):
		if absf(r.global_position.x - body.global_position.x) < within:
			return r
	return null


## 宽沟：去中继旁边，夺沟对面（或沟上空）的侦察机
func _cross_wide_gap(body: Node2D, dir: int) -> bool:
	var relay := _relay_near(body, 260.0)
	if relay == null:
		return false
	var dx: float = relay.global_position.x - body.global_position.x
	if absf(dx) > 20.0:
		move = Vector2(signf(dx), 0)
		run_held = absf(dx) > 60.0
		return true
	var d := _nearest_possessable(body, "drone_bot", 700.0)
	if d != null and d.global_position.x > body.global_position.x + 60.0:
		_try_possess(body, d)
	return true


## 路上的"锁"：警示墙要重装机、安保门要安保机——当前机体不对就换壳（敌对精英重装机先打瘫）
func _route_needs(body: Node2D, dir: int) -> bool:
	var need := ""
	for i in range(1, 12):
		var ch := _char_ahead(body, dir, float(i), 1.0)
		if (ch == "W" or ch == "D") and _solid(body, dir, float(i), 1.0):
			need = ch
			break
	if need == "W" and not (body is HeavyBot):
		var h := _nearest_possessable(body, "heavy_bot", 600.0)
		if h != null:
			move = Vector2(signf(h.global_position.x - body.global_position.x), 0) if h.center().distance_to(body.global_position) > controller.reach() - 20.0 else Vector2.ZERO
			_try_possess(body, h)
			return true
		for e in body.get_tree().get_nodes_in_group("enemy"):
			if e is HeavyBot and e.alive() and e.global_position.distance_to(body.global_position) < 500.0:
				# 精英重装机：打它，打瘫了再夺
				move = Vector2(signf(e.global_position.x - body.global_position.x), 0)
				if _shoot_cd <= 0.0:
					aim = (e.center() - body.global_position + Vector2(0, 18)).normalized()
					shoot_pressed = true
					_shoot_cd = 0.2
				if e.global_position.distance_to(body.global_position) < 110.0 and _slash_cd <= 0.0:
					slash_pressed = true
					_slash_cd = 0.18
				return true
	if need == "D" and not (body is EnemyBot):
		var g := _nearest_possessable(body, "enemy_bot", 600.0)
		if g != null:
			var far: bool = g.center().distance_to(body.global_position) > controller.reach() - 20.0
			if body is DroneBot:
				move = (g.global_position + Vector2(0, -40) - body.global_position).normalized() if far else Vector2.ZERO
			else:
				move = Vector2(signf(g.global_position.x - body.global_position.x), 0) if far else Vector2.ZERO
			_try_possess(body, g)
			return true
	return false


func _fight_melee(body: Node2D) -> bool:
	var e := _nearest_enemy(body, 110.0)
	if e != null and _slash_cd <= 0.0:
		slash_pressed = true
		_slash_cd = 0.16
		return true
	var far := _nearest_enemy(body, 320.0)
	if far != null and _shoot_cd <= 0.0 and absf(far.global_position.y - body.global_position.y) > 40.0:
		aim = (far.center() - body.global_position + Vector2(0, 18)).normalized()
		shoot_pressed = true
		_shoot_cd = 0.25
	return false


func _strider(body: Node2D, dir: int) -> void:
	move = Vector2(dir, 0)
	_fight_melee(body)
	if dir == 0:
		# 敌人就在头顶（平台上）：跳起来砍 / 往上开枪
		if body.is_on_floor() and _jump_cd <= 0.0:
			jump_pressed = true
			jump_held = true
			_jump_cd = 0.8
		jump_held = jump_held or body.velocity.y < 0.0
		return
	# 警示墙 → 夺重装机
	for i in range(1, 14):
		if _char_ahead(body, dir, float(i), 1.0) == "W" and _solid(body, dir, float(i), 1.0):
			var h := _nearest_possessable(body, "heavy_bot", 400.0)
			if h != null:
				move = Vector2(signf(h.global_position.x - body.global_position.x), 0) if absf(h.global_position.x - body.global_position.x) > 120.0 else Vector2.ZERO
				_try_possess(body, h)
				return
	# 安保门 → 夺安保机
	for i in range(1, 10):
		if _char_ahead(body, dir, float(i), 1.0) == "D" and _solid(body, dir, float(i), 1.0):
			var g := _nearest_possessable(body, "enemy_bot", 300.0)
			if g != null:
				_try_possess(body, g)
			return
	var gi := _gap_info(body, dir)
	if gi[1] > 8 and _cross_wide_gap(body, dir):
		return
	var gap := _gap_width(body, dir)
	if body.is_on_floor():
		# 窄沟：到沟边起跳
		if gap > 0 and _jump_cd <= 0.0:
			jump_pressed = true
			jump_held = true
			_jump_cd = 0.3
		# 低矮通道：脚上方 1 格空、2 格实 → 滑铲
		elif not _solid(body, dir, 1.5, 0.5) and _solid(body, dir, 1.5, 2.5) and _jump_cd <= 0.0:
			slide_pressed = true
			slide_held = true
			_jump_cd = 0.4
	else:
		jump_held = body.velocity.y < 0.0
	if body.state == 3:  # 滑铲中：一直按住滑过通道
		slide_held = _solid(body, dir, 0.5, 2.5) or _solid(body, dir, 1.5, 2.5)
	if _stuck_t > 2.5 and body.is_on_floor() and _jump_cd <= 0.0:
		jump_pressed = true
		jump_held = true
		_jump_cd = 0.6


func _heavy(body: Node2D, dir: int) -> void:
	move = Vector2(dir, 0)
	# 安保门 → 夺安保机（门口附近找）
	for i in range(1, 12):
		if _char_ahead(body, dir, float(i), 1.0) == "D" and _solid(body, dir, float(i), 1.0):
			var g := _nearest_possessable(body, "enemy_bot", 260.0)
			if g != null:
				_try_possess(body, g)
			else:
				move = Vector2.ZERO
			return
	if _act_cd > 0.0:
		return
	# 警示墙在前面 2 格内 → 冲撞
	for i in range(1, 3):
		if _char_ahead(body, dir, float(i), 1.0) == "W" and _solid(body, dir, float(i), 1.0):
			slash_pressed = true
			_act_cd = 0.9
			return
	# 脚下有警示地板 → 砸地
	for i in range(-1, 2):
		if _char_ahead(body, dir, float(i), -0.5) == "F" and _solid(body, dir, float(i), -0.5):
			move = Vector2.ZERO
			shoot_pressed = true
			_act_cd = 1.3
			return
	var e := _nearest_enemy(body, 90.0)
	if e != null:
		shoot_pressed = true
		_act_cd = 1.3
		return
	var e2 := _nearest_enemy(body, 160.0)
	if e2 != null and signf(e2.global_position.x - body.global_position.x) == dir and absf(e2.global_position.y - body.global_position.y) < 30.0:
		slash_pressed = true
		_act_cd = 0.9
		return
	if body.is_on_floor() and (_solid(body, dir, 1.0, 1.0) or _stuck_t > 2.0):
		jump_pressed = true


func _gunner(body: Node2D, dir: int) -> void:
	move = Vector2(dir, 0)
	var e := _nearest_enemy(body, 300.0)
	if e != null and _shoot_cd <= 0.0:
		aim = (e.center() - body.gun_pos()).normalized()
		shoot_pressed = true
		_shoot_cd = 0.3
	if _nearest_enemy(body, 40.0) != null and _slash_cd <= 0.0:
		slash_pressed = true
		_slash_cd = 0.4
	var gi := _gap_info(body, dir)
	if gi[1] > 6 and _cross_wide_gap(body, dir):
		return
	var gap := _gap_width(body, dir)
	if body.is_on_floor() and _jump_cd <= 0.0 and (_solid(body, dir, 1.0, 1.0) or _solid(body, dir, 1.0, 0.5) or gap > 0 or _stuck_t > 1.5):
		jump_pressed = true
		jump_held = true
		_jump_cd = 0.35


func _drone(body: Node2D, dir: int) -> void:
	# 目标高度：前方地面上方 4 格；沟上空保持当前高度往前飞
	var want_y: float = body.global_position.y
	for i in range(0, 16):
		var p := Vector2(body.global_position.x + dir * 2.0 * CELL, body.global_position.y - 6.0 * CELL + i * CELL)
		if region.solid_at(p):
			want_y = p.y - 4.0 * CELL
			break
	var v := Vector2(dir, clampf((want_y - body.global_position.y) / 40.0, -1.0, 1.0))
	if region.solid_at(body.global_position + Vector2(dir * 1.5 * CELL, 0)):
		v = Vector2(0, -1)
	move = v
	var e := _nearest_enemy(body, 260.0)
	if e != null and _shoot_cd <= 0.0:
		aim = (e.center() - body.gun_pos()).normalized()
		shoot_pressed = true
		_shoot_cd = 0.15


func _wisp(body: Node2D) -> void:
	var n := _nearest_possessable(body, "", 400.0)
	if n != null:
		move = (n.center() - body.global_position).normalized()
		_try_possess(body, n)
