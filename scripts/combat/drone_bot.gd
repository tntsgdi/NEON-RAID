class_name DroneBot
extends CharacterBody2D
## 侦察无人机（M3）。三种状态：
##   敌对（hostile）：在家附近悬停巡航，看见玩家 → 0.45 秒瞄准 → 三连发 → 冷却
##   失控（wild）：原地悬停、灯一闪一闪，不会攻击，专门给玩家夺来飞
##   被夺（controlled）：WASD 自由飞行（有惯性、悬停时轻轻浮动），K 连射（朝瞄准方向，向下更准），
##       J 撞击（短距离冲撞，伤害 1），L 冲刺；血量 3；不能爬墙、不能滑铲
## 敌对时颜色是红，失控时是灰白闪烁，被夺后是青。

signal died(bot: Node)

const SIZE := Vector2(27, 15)
## 画的时候整体放大，和主角机体的体量相称
const DRAW_SCALE := 1.5
const MAX_HP := 3
const SIGHT := 300.0
const RED := Color(1.25, 0.26, 0.32)
const CYAN := Color(0.3, 1.1, 1.25)
const WILD := Color(0.7, 0.75, 0.8)

var wild := false
var player: Node2D
var fx_parent: Node
var hp := 2
var facing := -1
var controlled := false
var input: PlayerInput
var lock_target: Node2D

var _home := Vector2.ZERO
var _t := 0.0
var _phase := 0.0
var _mode := "patrol"   # patrol / aim / cool
var _aim := Vector2.DOWN
var _burst_left := 0
var _flash := 0.0
var _iframes := 0.0
var _weapon_cd := 0.0
var _ram_t := 0.0
var _ram_hit := {}
var _dash_t := 0.0
var _dead := false
var hurtboxes: Hurtboxes
## ---- 附身强化：两条意识线缆
## 抓住的敌人、抓住的剩余时间
var grab: Node2D
var _grab_t := 0.0
## 甩出去的敌人（飞行中撞到别的敌人，两个都吃伤害）
var _flung: Node2D
var _fling_t := 0.0
var _fling_hit := {}
## 异体生长进度 0..1
var mut_k := 0.0
const GRAB_RANGE := 170.0
## 瞄准（锁定框收紧）时长
const AIM_TIME := 0.8


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := RectangleShape2D.new()
	shape.size = SIZE
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	add_to_group("hittable")
	add_to_group("possessable")
	hurtboxes = Hurtboxes.new()
	add_child(hurtboxes)
	if not wild:
		add_to_group("enemy")
	_home = global_position
	_phase = randf() * TAU
	if fx_parent == null:
		fx_parent = get_parent()
	light_mask = Neon.ACTOR_LIGHT_MASK
	Neon.add_light(self, Neon.RED if not wild else Neon.CYAN, 0.25, 0.8)


func alive() -> bool:
	return not _dead


func hurt_rect() -> Rect2:
	return Rect2(global_position - SIZE * 0.5 - Vector2(2, 2), SIZE + Vector2(4, 4))


func center() -> Vector2:
	return global_position


func gun_pos() -> Vector2:
	return global_position + Vector2(0, 7)


## 意识光流到达：机身往下一沉再稳住
func wake() -> void:
	velocity.y += 90.0
	_flash = 0.05


## 返回 0 = 没打到，1 = 打到
func take_hit(dir: Vector2, power: int, _kind := "slash") -> int:
	if _dead:
		return 0
	hp -= power
	_flash = 0.1
	velocity += dir * (180.0 + 60.0 * power)
	# 瞄准中被打：锁定被打断，过一会儿重新瞄
	if _mode == "aim" or _mode == "fire":
		_mode = "cool"
		_t = 0.7
	if hp <= 0:
		_die(dir)
	return 1


func _die(dir: Vector2) -> void:
	if _dead:
		return
	_dead = true
	if not is_inside_tree():
		queue_free()
		return
	remove_from_group("hittable")
	remove_from_group("enemy")
	remove_from_group("possessable")
	remove_from_group("controlled")
	var c := CYAN if controlled else RED
	FxPart.spawn(fx_parent, global_position, "rect", Vector2(12, 5), dir * 200.0 + Vector2(0, -120), Color(0.15, 0.08, 0.1), c)
	FxPart.spawn(fx_parent, global_position + Vector2(-6, -4), "rect", Vector2(6, 2), Vector2(-160, -180), c, c)
	FxPart.spawn(fx_parent, global_position + Vector2(6, -4), "rect", Vector2(6, 2), Vector2(160, -180), c, c)
	Fx.sparks(fx_parent, global_position, dir, 14, Color(2.6, 1.0, 0.7))
	Fx.flash(fx_parent, global_position, Color(2.8, 0.9, 0.6), 16.0)
	Audio.play("break", -4.0, 1.25)
	get_tree().call_group("game", "shockwave", global_position)
	died.emit(self)
	queue_free()


# ---------------------------------------------------------------- 敌对 / 失控

func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_iframes = maxf(_iframes - delta, 0.0)
	_phase += delta
	hurtboxes.set_part("body", hurt_rect())
	if controlled:
		_controlled_physics(delta)
	elif wild:
		# 失控：原地漂着，轻轻晃
		velocity = velocity.lerp((_home + Vector2(sin(_phase * 0.7) * 6.0, sin(_phase * 1.9) * 4.0) - global_position) * 3.0, 1.0 - exp(-4.0 * delta))
		move_and_slide()
	else:
		_hostile(delta)
	queue_redraw()


func _tgt() -> Node2D:
	if player == null:
		return null
	var t := get_tree().get_first_node_in_group("controlled")
	return t if t != self else null


func _hostile(delta: float) -> void:
	var t := _tgt()
	var want := _home + Vector2(sin(_phase * 0.6) * 60.0, sin(_phase * 2.0) * 5.0)
	match _mode:
		"patrol":
			if t != null and t.global_position.distance_to(global_position) < SIGHT and _clear(t):
				_mode = "aim"
				_t = AIM_TIME
				Audio.play("charge", -12.0, 1.3)
		"aim":
			want = global_position
			_t -= delta
			if t != null:
				_aim = (t.global_position + Vector2(0, -20) - gun_pos()).normalized()
				facing = 1 if _aim.x > 0.0 else -1
			if _t <= 0.0:
				_mode = "fire"
				_burst_left = 3
				_t = 0.0
		"fire":
			want = global_position
			_t -= delta
			if _t <= 0.0:
				Bullet.fire(fx_parent, gun_pos(), _aim * 280.0, Bullet.Team.ENEMY, 1, self)
				Audio.play("enemy_shot", -9.0, 1.3)
				_burst_left -= 1
				_t = 0.09
				if _burst_left <= 0:
					_mode = "cool"
					_t = 1.4
		"cool":
			_t -= delta
			if _t <= 0.0:
				_mode = "patrol"
	velocity = velocity.lerp((want - global_position) * 2.5, 1.0 - exp(-3.0 * delta))
	move_and_slide()


func _clear(t: Node2D) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, t.global_position + Vector2(0, -20), 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


# ---------------------------------------------------------------- 被夺

func take_control(inp: PlayerInput, vel: Vector2) -> void:
	controlled = true
	wild = false
	input = inp
	velocity = vel
	hp = MAX_HP
	_iframes = 0.25
	mut_k = 0.0
	Fx.sparks(fx_parent, global_position, Vector2.UP, 12, Color(1.0, 2.2, 2.4))
	Audio.play("charge", -6.0, 1.8)
	remove_from_group("enemy")
	remove_from_group("hittable")
	remove_from_group("possessable")
	add_to_group("controlled")


func release_control() -> void:
	controlled = false
	_die(Vector2(-facing, 0.5))


func invulnerable() -> bool:
	return _iframes > 0.0 or _dash_t > 0.0


func take_bullet(b: Node) -> bool:
	if invulnerable():
		return false
	_hurt(b.velocity.normalized(), b.damage)
	return true


func melee_hit(dir: Vector2, dmg: int) -> void:
	if invulnerable():
		return
	_hurt(dir, dmg)


func _hurt(dir: Vector2, dmg: int) -> void:
	hp -= dmg
	_flash = 0.1
	_iframes = 0.5
	velocity += dir * 220.0
	Audio.play("hurt", -4.0, 1.2)
	get_tree().call_group("game", "aberrate", 4.0)
	if hp <= 0:
		_die(dir)


func _controlled_physics(delta: float) -> void:
	input.poll(self)
	_weapon_cd = maxf(_weapon_cd - delta, 0.0)
	_dash_t = maxf(_dash_t - delta, 0.0)
	var top := 380.0 if input.run_held else 320.0
	if _ram_t > 0.0:
		_ram_t -= delta
		_ram_contacts()
	elif _dash_t <= 0.0:
		var m := input.move
		if m.length() > 0.1:
			velocity = velocity.move_toward(m.normalized() * top, 1400.0 * delta)
		else:
			# 松手：带惯性慢慢停下，并轻轻上下浮动
			velocity = velocity.move_toward(Vector2(0, sin(_phase * 3.0) * 12.0), 700.0 * delta)
	if absf(velocity.x) > 20.0:
		facing = 1 if velocity.x > 0.0 else -1
	var aim := _controlled_aim()
	if input.shoot_pressed and _weapon_cd <= 0.0:
		Bullet.fire(fx_parent, gun_pos(), aim * 700.0, Bullet.Team.PLAYER, 1, self)
		Fx.sparks(fx_parent, gun_pos(), aim, 4, Neon.CYAN_HOT)
		Audio.play("shot", -6.0, 1.3)
		_weapon_cd = 0.12
	mut_k = minf(mut_k + delta / 0.3, 1.0)
	# J：意识线缆——抓住附近的敌人拽过来；抓着的时候再按 J（或 0.6 秒后）甩出去
	if input.slash_pressed:
		if is_instance_valid(grab):
			_fling()
		else:
			_try_grab(aim)
	if is_instance_valid(grab):
		_hold_grab(delta)
	_update_fling(delta)
	if input.dash_pressed and _dash_t <= 0.0:
		var d := input.move.normalized() if input.move.length() > 0.2 else Vector2(facing, 0)
		velocity = d * 600.0
		_dash_t = 0.15
		Audio.play("dash", -6.0, 1.4)
	_aim = aim
	move_and_slide()


func _try_grab(aim: Vector2) -> void:
	var best: Node2D = null
	var bd := GRAB_RANGE
	for n in get_tree().get_nodes_in_group("hittable"):
		if n == self or (n.has_method("alive") and not n.alive()):
			continue
		# 重装机太重：只有瘫痪时才拽得动
		if n is HeavyBot and n.state != HeavyBot.State.STUNNED:
			continue
		var to: Vector2 = n.hurt_rect().get_center() - global_position
		if to.length() < bd and (aim.length() < 0.1 or absf(aim.angle_to(to)) < deg_to_rad(70.0)):
			bd = to.length()
			best = n
	if best == null:
		Audio.play("swing_1", -8.0, 1.6)
		return
	grab = best
	_grab_t = 0.6
	if grab is EnemyBot:
		grab.state = EnemyBot.State.STAGGER
		grab._t = 1.0
	Audio.play("possess", -8.0, 1.6)
	Fx.sparks(fx_parent, grab.hurt_rect().get_center(), (global_position - grab.global_position).normalized(), 8, Color(1.0, 2.2, 2.4))


## 抓着：把敌人拽到身前下方，跟着侦察机走
func _hold_grab(delta: float) -> void:
	if grab.has_method("alive") and not grab.alive():
		grab = null
		return
	_grab_t -= delta
	var want := global_position + Vector2(facing * 14.0, 22.0)
	grab.global_position = grab.global_position.lerp(want, 1.0 - exp(-14.0 * delta))
	if "velocity" in grab:
		grab.velocity = Vector2.ZERO
	if grab is EnemyBot:
		grab._t = maxf(grab._t, 0.3)
	if _grab_t <= 0.0:
		_fling()


## 甩出去：朝移动方向（没按方向就朝面朝方向）高速甩飞，自己先吃 1 点
func _fling() -> void:
	var d := input.move.normalized() if input.move.length() > 0.2 else Vector2(facing, 0.15).normalized()
	var n := grab
	grab = null
	if not is_instance_valid(n):
		return
	n.take_hit(d, 1, "slash")
	if is_instance_valid(n) and "velocity" in n:
		n.velocity = d * 640.0 + Vector2(0, -60)
		if n is EnemyBot and n.alive():
			n.state = EnemyBot.State.AIR
	_flung = n
	_fling_t = 0.7
	_fling_hit.clear()
	Audio.play("dash", -4.0, 0.9)
	get_tree().call_group("game", "impact", 3.0, d)


func _update_fling(delta: float) -> void:
	if not is_instance_valid(_flung):
		return
	_fling_t -= delta
	if _fling_t <= 0.0:
		_flung = null
		return
	var r: Rect2 = _flung.hurt_rect()
	for n in get_tree().get_nodes_in_group("hittable"):
		if n == _flung or n == self or _fling_hit.has(n) or (n.has_method("alive") and not n.alive()):
			continue
		if r.grow(2.0).intersects(n.hurt_rect()):
			_fling_hit[n] = true
			var d: Vector2 = (n.hurt_rect().get_center() - r.get_center()).normalized()
			n.take_hit(d, 2, "slash")
			if is_instance_valid(_flung) and _flung.has_method("take_hit"):
				_flung.take_hit(-d, 2, "slash")
			Fx.sparks(fx_parent, n.hurt_rect().get_center(), d, 14, Neon.WHITE_HOT)
			Audio.play("hit_heavy", -2.0, 0.9)
			get_tree().call_group("game", "shockwave", n.hurt_rect().get_center())
			TimeFx.hitstop(0.05)
			if not is_instance_valid(_flung):
				return


func _controlled_aim() -> Vector2:
	if input.aim_keys or input.aim.length() < 0.1:
		if is_instance_valid(lock_target):
			return (lock_target.global_position + Vector2(0, -18) - gun_pos()).normalized()
		return Vector2(facing * 0.7, 0.7).normalized()  # 纯键盘、没目标：朝前下方打
	var a := input.aim.normalized()
	if is_instance_valid(lock_target):
		var to: Vector2 = lock_target.global_position + Vector2(0, -18) - gun_pos()
		if absf(a.angle_to(to)) <= deg_to_rad(15.0):
			return to.normalized()
	return a


func _ram_contacts() -> void:
	for n in get_tree().get_nodes_in_group("hittable"):
		if _ram_hit.has(n) or (n.has_method("alive") and not n.alive()):
			continue
		if hurt_rect().grow(4.0).intersects(n.hurt_rect()):
			_ram_hit[n] = true
			n.take_hit(velocity.normalized(), 1, "slash")
			Fx.sparks(fx_parent, n.hurt_rect().get_center(), velocity.normalized(), 8, Neon.WHITE_HOT)
			Audio.play("hit", -3.0)


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var col := CYAN if controlled else (RED if not wild else WILD)
	if wild and int(_phase * 6.0) % 3 == 0:
		col = Color(1.6, 1.7, 1.8)  # 失控：一闪一闪
	var white := _flash > 0.0 or (controlled and _iframes > 0.0 and int(_iframes * 20.0) % 2 == 0)
	# 像素贴图：机身随速度倾斜、上下轻轻浮动；旋翼 4 帧；红 = 敌对，青 = 被夺，白 = 失控（可夺）
	var tilt := clampf(velocity.x / 900.0, -0.35, 0.35) * float(facing)
	var bob := Vector2(0, round(sin(_phase * 3.0)))
	var sfx := "_p" if controlled else ("_w" if wild and int(_phase * 6.0) % 3 != 0 else "")
	var mod := Color(3.0, 3.0, 3.0) if white else Color.WHITE
	var flip := facing < 0
	var dir := "res://assets/sprites/drone/"
	var frame := int(_phase * 30.0) % 4
	for x in [-7.0, 7.0]:
		PixelPart.get_part(dir + "rotor%d" % frame).draw(self, Transform2D.IDENTITY, bob + Vector2(x, -6).rotated(tilt * float(facing)), 0.0, flip, mod)
	PixelPart.get_part(dir + "hull" + sfx).draw(self, Transform2D.IDENTITY, bob, tilt, flip, mod)
	PixelPart.get_part(dir + "pod" + sfx).draw(self, Transform2D.IDENTITY, bob + Vector2(0, 5).rotated(tilt * float(facing)), tilt, flip, mod)
	# 异体：两条意识线缆（被夺时长出来；平时垂着轻轻摆，抓人时绷直连到敌人身上）
	if controlled and mut_k > 0.0:
		for side in [-1.0, 1.0]:
			var root := bob + Vector2(side * 6.0, 4.0)
			var tip: Vector2
			if is_instance_valid(grab):
				tip = grab.hurt_rect().get_center() - global_position + Vector2(side * 3.0, 0)
			else:
				tip = root + Vector2(side * 4.0 + sin(_phase * 4.0 + side) * 2.0, 10.0 * mut_k)
			var n := 8
			for i in n:
				var t := float(i) / n
				var p0 := root.lerp(tip, t) + Vector2(0, sin(t * PI) * (3.0 if not is_instance_valid(grab) else 0.0))
				var p1 := root.lerp(tip, float(i + 1) / n) + Vector2(0, sin(float(i + 1) / n * PI) * (3.0 if not is_instance_valid(grab) else 0.0))
				PixelFx.line(self, p0, p1, PixelFx.CYAN[2] if i % 2 == 0 else PixelFx.CYAN[1], 1)
			PixelPart.get_part("res://assets/sprites/mut/claw").draw(self, Transform2D.IDENTITY, tip, (tip - root).angle(), false)
	if not controlled and _mode == "aim":
		var k := 1.0 - _t / AIM_TIME
		draw_line(gun_pos() - global_position, gun_pos() - global_position + _aim * 260.0, Color(1.2, 0.2, 0.25, 0.1 + 0.25 * k), 1.0)
		var tg := _tgt()
		if tg != null:
			var r: Rect2 = tg.hurt_rect()
			AimLock.draw(self, Rect2(r.position - global_position, r.size), k)
