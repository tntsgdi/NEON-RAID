class_name EnemyBot
extends CharacterBody2D
## 联合体安保机器人（M2）。三种型号，shielded 可以叠加在任何型号上：
##   gunner  轻型安保机：0.5 秒瞄准线（最后 0.12 秒锁定）→ 一发慢速红弹
##   burst   三连发机：0.6 秒瞄准 → 扇形三发
##   rusher  冲锋机：0.4 秒蓄力（身体压低、目镜闪红）→ 直线冲撞；冲刺能穿过去，
##           冲锋时被正面砍中 = 招架，长硬直 + 神经超频
## 被打：硬直 + 击退；上挑或重击会被打上天，可以空中连击；打空血量爆碎。
## 盾兵：正面能量盾，子弹从正面打会被弹开；刀砍 3 下破盾；从背后或头上打直接伤本体。

signal died(bot: EnemyBot)

enum State { PATROL, AIM, COOLDOWN, STAGGER, AIR, WINDUP, CHARGE, DEAD }

const RED := Color(1.25, 0.26, 0.32)
const EYE := Neon.RED_HOT
const DARK := Color(0.2, 0.05, 0.08)
const METAL := Color(0.42, 0.38, 0.44)
const SIZE := Vector2(14, 34)
const GRAVITY := 1400.0
const WALK := 45.0
const SIGHT := Vector2(300, 150)
const LOCK_TIME := 0.12
const MAX_HP := 4
const SHIELD_HP := 3

var kind := "gunner"
var shielded := false
var patrol_range := 50.0
var player: Node2D
var fx_parent: Node

var state := State.PATROL
var hp := MAX_HP
var shield_hp := SHIELD_HP
var facing := -1
var aim_dir := Vector2.LEFT

var _home := Vector2.ZERO
var _t := 0.0
var _flash := 0.0
var _shield_flash := 0.0
var _walk_phase := 0.0
var _spawn_pop := 0.25
## 出场时间：刚刷出来的 0.7 秒里不会发现玩家、不会攻击
var _grace := 0.7
var elite := false
var _hit_player := false
## 受击后仰（弹簧）
var _recoil := 0.0
var _recoil_v := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 4.0
	var shape := RectangleShape2D.new()
	shape.size = SIZE
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = Vector2(0, -SIZE.y * 0.5)
	add_child(cs)
	add_to_group("hittable")
	add_to_group("enemy")
	_home = global_position
	if kind == "rusher":
		hp = 3
	if fx_parent == null:
		fx_parent = get_parent()
	light_mask = Neon.ACTOR_LIGHT_MASK
	Neon.add_light(self, Neon.RED, 0.3, 1.0, Vector2(0, -22))


func alive() -> bool:
	return state != State.DEAD


func hurt_rect() -> Rect2:
	return Rect2(global_position + Vector2(-SIZE.x * 0.5, -SIZE.y), SIZE)


func center() -> Vector2:
	return global_position + Vector2(0, -SIZE.y * 0.55)


func gun_pos() -> Vector2:
	return global_position + Vector2(facing * 10, -27)


func has_shield() -> bool:
	return shielded and shield_hp > 0


func aim_time() -> float:
	return 0.6 if kind == "burst" else 0.5


## 返回 0 = 没打到，1 = 打到，2 = 被盾挡住（子弹会弹开）
func take_hit(dir: Vector2, power: int, hit_kind := "slash") -> int:
	if not alive():
		return 0
	var from_front := dir.x * facing < -0.1
	var from_above := dir.y > 0.5
	# 冲锋中被正面砍中：招架
	if state == State.CHARGE and hit_kind == "slash" and from_front:
		_parried(dir)
		return 1
	if has_shield() and from_front and not from_above:
		if hit_kind == "bullet":
			_shield_flash = 0.08
			return 2
		shield_hp -= power
		_shield_flash = 0.12
		velocity.x = signf(dir.x) * 90.0
		if shield_hp <= 0:
			Fx.debris(fx_parent, center() + Vector2(facing * 10, 0), dir, 10, RED)
			Fx.sparks(fx_parent, center() + Vector2(facing * 10, 0), dir, 12, Color(1, 0.6, 0.6))
			Audio.play("break", -6.0, 1.3)
		else:
			Audio.play("shield_block", -4.0)
		return 1
	hp -= power
	_flash = 0.1
	var sx := signf(dir.x) if absf(dir.x) > 0.1 else float(-facing)
	_recoil_v += sx * (7.0 + 4.0 * power)
	velocity.x = sx * (150.0 + 80.0 * power)
	if dir.y < -0.5:
		velocity.y = -360.0  # 上挑：打上天
		state = State.AIR
	elif state == State.AIR or (power >= 2 and hit_kind == "slash" and dir.y <= 0.1):
		velocity.y = minf(velocity.y, -240.0)  # 空中连击 / 重击：保持浮空
		state = State.AIR
	else:
		state = State.STAGGER
		_t = 0.35
	if hp <= 0:
		_die(dir)
	return 1


func _parried(dir: Vector2) -> void:
	state = State.STAGGER
	_t = 1.0
	velocity = Vector2(signf(dir.x) * 260.0, -160.0)
	_flash = 0.12
	Fx.sparks(fx_parent, center(), dir, 16, Neon.WHITE_HOT)
	Audio.play("deflect", -2.0, 0.85)
	get_tree().call_group("game", "shockwave", center())
	if is_instance_valid(player) and player.has_method("parried"):
		player.parried()


func _die(dir: Vector2) -> void:
	state = State.DEAD
	remove_from_group("hittable")
	remove_from_group("enemy")
	# 碎成零件：头、躯干、两条腿、武器各自带着冲量飞出去、落地弹跳
	var base := global_position
	var push := Vector2(signf(dir.x) if absf(dir.x) > 0.1 else -facing, -0.6).normalized()
	FxPart.spawn(fx_parent, base + Vector2(0, -34), "rect", Vector2(10, 8), push * 260.0 + Vector2(0, -160), DARK, RED)
	FxPart.spawn(fx_parent, base + Vector2(0, -21), "rect", Vector2(15, 17), push * 160.0, DARK, RED)
	FxPart.spawn(fx_parent, base + Vector2(-3, -7), "rect", Vector2(3, 12), push * 120.0 + Vector2(-60, -80), RED, RED)
	FxPart.spawn(fx_parent, base + Vector2(3, -7), "rect", Vector2(3, 12), push * 140.0 + Vector2(60, -90), RED, RED)
	if kind != "rusher":
		FxPart.spawn(fx_parent, base + Vector2(facing * 10, -24), "rect", Vector2(10, 3), push * 300.0 + Vector2(0, -120), METAL, METAL)
	Fx.debris(fx_parent, center(), dir, 12, RED)
	Fx.sparks(fx_parent, center(), dir, 18, Color(2.6, 1.0, 0.7))
	Fx.flash(fx_parent, center(), Color(2.8, 0.9, 0.6), 22.0)
	Audio.play("break", -2.0)
	get_tree().call_group("game", "shockwave", center())
	died.emit(self)
	queue_free()


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_shield_flash = maxf(_shield_flash - delta, 0.0)
	_spawn_pop = maxf(_spawn_pop - delta, 0.0)
	_grace = maxf(_grace - delta, 0.0)
	_recoil_v += (-_recoil * 220.0 - _recoil_v * 14.0) * delta
	_recoil += _recoil_v * delta
	velocity.y = minf(velocity.y + GRAVITY * delta, 600.0)
	match state:
		State.PATROL:
			_patrol(delta)
		State.AIM:
			_aim(delta)
		State.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			_t -= delta
			if _t <= 0.0:
				state = State.CHARGE
				_t = 0.55
				_hit_player = false
				Audio.play("dash", -6.0, 0.8)
		State.CHARGE:
			_charge(delta)
		State.COOLDOWN:
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
			_t -= delta
			if _t <= 0.0:
				state = State.PATROL
		State.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			_t -= delta
			if _t <= 0.0 and is_on_floor():
				state = State.COOLDOWN
				_t = 0.4
		State.AIR:
			velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
			if is_on_floor() and velocity.y >= 0.0:
				state = State.STAGGER
				_t = 0.25
	move_and_slide()
	queue_redraw()


func _patrol(delta: float) -> void:
	if _sees_player():
		facing = 1 if player.global_position.x > global_position.x else -1
		if kind == "rusher":
			state = State.WINDUP
			_t = 0.4
		else:
			state = State.AIM
			_t = aim_time()
		Audio.play("charge", -10.0)
		return
	if global_position.x > _home.x + patrol_range:
		facing = -1
	elif global_position.x < _home.x - patrol_range:
		facing = 1
	elif is_on_wall():
		facing = -facing
	velocity.x = facing * WALK
	_walk_phase += delta * 9.0


func _aim(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_t -= delta
	if _t > LOCK_TIME and is_instance_valid(player):
		facing = 1 if player.global_position.x > global_position.x else -1
		aim_dir = (player.global_position + Player.CHEST - gun_pos()).normalized()
	if _t <= 0.0:
		if kind == "burst":
			for a in [-12.0, 0.0, 12.0]:
				Bullet.fire(fx_parent, gun_pos(), aim_dir.rotated(deg_to_rad(a)) * 300.0, Bullet.Team.ENEMY, 1, self)
			Audio.play("enemy_shot", -4.0, 0.85)
		else:
			Bullet.fire(fx_parent, gun_pos(), aim_dir * 260.0, Bullet.Team.ENEMY, 1, self)
			Audio.play("enemy_shot", -6.0)
		Fx.sparks(fx_parent, gun_pos(), aim_dir, 5, RED)
		state = State.COOLDOWN
		_t = 1.6 if kind == "burst" else 1.1


func _charge(delta: float) -> void:
	velocity.x = facing * 420.0
	_t -= delta
	_walk_phase += delta * 24.0
	if not _hit_player and is_instance_valid(player) and hurt_rect().grow(2.0).intersects(player.hurt_rect()):
		_hit_player = true
		# 撞上的一刻玩家正面朝这边、正在出刀：算招架
		if player.has_method("parry_ready") and player.parry_ready(facing):
			_parried(Vector2(-facing, 0))
			return
		if player.has_method("melee_hit"):
			player.melee_hit(Vector2(facing, -0.3).normalized(), 1)
	if _t <= 0.0 or is_on_wall():
		if is_on_wall():
			Fx.sparks(fx_parent, global_position + Vector2(facing * 8, -16), Vector2(-facing, 0), 8, RED)
			Audio.play("shield_block", -8.0, 0.7)
		state = State.COOLDOWN
		_t = 1.0


## 精英：血量多一半，身形大一圈
func make_elite() -> void:
	elite = true
	hp = int(ceil(hp * 1.5))


func _sees_player() -> bool:
	if not is_instance_valid(player) or _grace > 0.0:
		return false
	var d := player.global_position - global_position
	var sight := Vector2(220, 60) if kind == "rusher" else SIGHT
	if absf(d.x) > sight.x or absf(d.y) > sight.y:
		return false
	var q := PhysicsRayQueryParameters2D.create(gun_pos(), player.global_position + Player.CHEST, 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _draw() -> void:
	var white := _flash > 0.0
	var fill := Color.WHITE if white else DARK
	var s := (1.0 + _spawn_pop * 2.0) * (1.2 if elite else 1.0)
	# 瞄准时身体后仰，冲锋蓄力时压低前倾
	var lean := 0.0
	if state == State.AIM:
		lean = -0.1 * facing
	elif state == State.WINDUP:
		lean = 0.25 * facing
	elif state == State.CHARGE:
		lean = 0.35 * facing
	# 湿地面倒影：站在地上时，脚下一个翻转压扁的暗红剪影
	if is_on_floor():
		draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, -0.5))
		draw_rect(Rect2(-7, -30, 14, 30), Color(1.0, 0.2, 0.25, 0.12))
		draw_rect(Rect2(-1, -24, 5, 2), Color(1.6, 0.3, 0.35, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	# 腿：两节，走路时交替
	var step := sin(_walk_phase) * 3.0 if state in [State.PATROL, State.CHARGE] else 0.0
	for side in [-1, 1]:
		var hip := Vector2(side * 3, -13)
		var foot := Vector2(side * 3 + step * side, 0)
		var knee := (hip + foot) * 0.5 + Vector2(facing * 2.5, 0)
		draw_polyline(PackedVector2Array([hip, knee, foot]), RED.darkened(0.2 if side < 0 else 0.0), 2.5, true)
	draw_set_transform(Vector2(0, -13), lean + _recoil * 0.06, Vector2(s, s))
	# 躯干（梯形）与肩甲
	var body := PackedVector2Array([Vector2(-7, 0), Vector2(7, 0), Vector2(8, -17), Vector2(-8, -17)])
	draw_colored_polygon(body, fill)
	draw_polyline(body + PackedVector2Array([body[0]]), RED, 1.5, true)
	draw_rect(Rect2(-facing * 10 - 3, -18, 6, 5), METAL)
	# 头与目镜
	var head := Rect2(-5, -25, 10, 8)
	draw_rect(head, fill)
	draw_rect(head, RED, false, 1.5)
	var eye_on := state in [State.AIM, State.WINDUP, State.CHARGE] and int(_t * 20.0) % 2 == 0
	draw_rect(Rect2(0 if facing > 0 else -5, -23, 5, 2), Neon.WHITE_HOT if (white or eye_on) else EYE)
	# 武器
	var g := Vector2(facing * 8, -13)
	if kind == "rusher":
		# 冲锋机：前伸的撞角
		var horn := PackedVector2Array([Vector2(facing * 6, -14), Vector2(facing * 15, -9), Vector2(facing * 6, -5)])
		draw_colored_polygon(horn, METAL)
		draw_polyline(horn, RED, 1.0, true)
	else:
		var dir := aim_dir if state == State.AIM else Vector2(facing, 0.25).normalized()
		draw_line(g, g + dir * 10.0, METAL, 3.0, true)
		if kind == "burst":
			draw_line(g + Vector2(0, 3), g + Vector2(0, 3) + dir * 9.0, METAL, 2.0, true)
		# 开火前枪口越来越亮
		if state == State.AIM:
			var k := 1.0 - _t / aim_time()
			draw_circle(g + dir * 10.0, 1.0 + 2.5 * k, Color(2.5 + k, 0.4 + 1.6 * k, 0.4 + 1.6 * k, 0.4 + 0.6 * k))
	draw_set_transform(Vector2.ZERO)
	# 瞄准线：越接近开火越亮越粗，锁定后变白
	if state == State.AIM:
		var gp := gun_pos() - global_position
		var k := 1.0 - _t / aim_time()
		var locked := _t <= LOCK_TIME
		var c := Color(1.3, 1.25, 1.25, 0.8) if locked else Color(1.2, 0.2, 0.25, 0.2 + 0.45 * k)
		var spreads := [-12.0, 0.0, 12.0] if kind == "burst" else [0.0]
		for a in spreads:
			draw_line(gp, gp + aim_dir.rotated(deg_to_rad(a)) * 320.0, c, 1.0 + k * 1.5)
	# 冲锋蓄力：地面上一道红色预警
	if state == State.WINDUP:
		var k := 1.0 - _t / 0.4
		draw_rect(Rect2(minf(0.0, facing * 200.0), -2, 200, 2), Color(2.0, 0.3, 0.35, 0.2 + 0.5 * k))
	# 能量盾
	if has_shield():
		var sx := facing * 12.0
		var sc := Color(1, 0.85, 0.85, 0.9) if _shield_flash > 0.0 else Color(1, 0.25, 0.3, 0.35)
		var shield := PackedVector2Array([Vector2(sx - 2, -38), Vector2(sx + facing * 3, -30), Vector2(sx + facing * 3, -8), Vector2(sx - 2, -1), Vector2(sx - facing * 1, -20)])
		draw_colored_polygon(shield, sc)
		draw_polyline(shield + PackedVector2Array([shield[0]]), RED, 1.0, true)
		for i in shield_hp:
			draw_rect(Rect2(sx - 0.5, -32 + i * 7, 2, 4), Color.WHITE)
