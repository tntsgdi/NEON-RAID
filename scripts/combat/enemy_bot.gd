class_name EnemyBot
extends CharacterBody2D
## 联合体安保机器人（M2）。三种型号，shielded 可以叠加在任何型号上：
##   gunner  轻型安保机：0.5 秒瞄准线（最后 0.12 秒锁定）→ 一发慢速红弹
##   burst   三连发机：0.6 秒瞄准 → 扇形三发
##   rusher  冲锋机：0.4 秒蓄力（身体压低、目镜闪红）→ 直线冲撞；冲刺能穿过去，
##           冲锋时被正面砍中 = 招架，长硬直 + 神经超频
## 被打：硬直 + 击退；上挑或重击会被打上天，可以空中连击；打空血量爆碎。
## 盾兵：正面能量盾，子弹从正面打会被弹开；刀砍 3 下破盾；从背后或头上打直接伤本体。
## 被夺（take_control）后变成青色、由玩家操作：K 主武器（枪手精准单发 / 三连发扇形 / 冲锋机冲撞）、
## J 近战撞击、L 小冲刺、空格跳；盾照样挡正面子弹。意识离开时断电报废。

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
var _spawn_pop := 0.25
## 出场时间：刚刷出来的 0.7 秒里不会发现玩家、不会攻击
var _grace := 0.7
var elite := false
var _hit_player := false
## 受击后仰（弹簧）
var _recoil := 0.0
var _recoil_v := 0.0

## 被夺之后
var controlled := false
var input: PlayerInput
var lock_target: Node2D
var _weapon_cd := 0.0
var _bash_cd := 0.0
var _iframes := 0.0
var _hop_t := 0.0
var _ram_t := 0.0
var _ram_hit := {}
var _gun_hot := 0.0
var rig: EnemyRig
var hurtboxes: Hurtboxes

## ---- 附身强化（被夺时）：灌注 R-0 的机动 + 专属异体
## 贴着的墙（1 右 / -1 左 / 0 不在墙上）
var wall := 0
var _air_dash := true
## 枪手：电磁长矛蓄力（秒），< 0 = 没在蓄
var _rail_charge := -1.0
## 冲锋机：连撞剩余段数、下一段已预约
var _chain := 0
var _chain_queue := false
## 盾兵：盾掷出去了
var _shield_out := false
## 异体生长进度 0..1（夺壳瞬间从 0 长到 1，约 0.3 秒）
var mut_k := 0.0
const CLIMB := 150.0
const CLIMB_RUN := 240.0
const JUMP_V := 520.0
const RAIL_MAX := 0.6
## 被踩趴的剩余时间
var _down := 0.0


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
	add_to_group("possessable")
	_home = global_position
	if kind == "rusher":
		hp = 3
	if fx_parent == null:
		fx_parent = get_parent()
	rig = EnemyRig.new()
	rig.kind = kind
	rig.armored = shielded
	rig.light_mask = Neon.ACTOR_LIGHT_MASK
	add_child(rig)
	hurtboxes = Hurtboxes.new()
	add_child(hurtboxes)
	light_mask = Neon.ACTOR_LIGHT_MASK
	Neon.add_light(self, Neon.RED, 0.3, 1.0, Vector2(0, -22))


func alive() -> bool:
	return state != State.DEAD


func hurt_rect() -> Rect2:
	return Rect2(global_position + Vector2(-SIZE.x * 0.5, -SIZE.y), SIZE)


func center() -> Vector2:
	return global_position + Vector2(0, -SIZE.y * 0.55)


func gun_pos() -> Vector2:
	if rig != null and rig.muzzle_world != Vector2.ZERO:
		return rig.muzzle_world
	return global_position + Vector2(facing * 10, -27)


func has_shield() -> bool:
	return shielded and shield_hp > 0 and not _shield_out


## 回旋的晶化盾飞回手里
func catch_shield() -> void:
	_shield_out = false
	_shield_flash = 0.1
	Audio.play("shield_block", -6.0, 1.4)


## 瞄准（锁定框收紧）时长：学《碳酸危机》，留够时间让玩家冲过去打断
func aim_time() -> float:
	return 0.9 if kind == "burst" else 0.8


## 被踩头：仰面倒地 t 秒（期间不能攻击），之后站起来
func knock_down(t: float) -> void:
	if not alive() or controlled:
		return
	state = State.STAGGER
	_t = t
	_down = t
	velocity.x = 0.0


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
	if rig != null:
		rig.hit(dir.x, power, state == State.AIR)
	if hp <= 0:
		_die(dir)
	return 1


func _parried(dir: Vector2) -> void:
	state = State.STAGGER
	_t = 1.0
	velocity = Vector2(signf(dir.x) * 260.0, -160.0)
	_flash = 0.12
	if rig != null:
		rig.hit(dir.x, 2, false)
	Fx.sparks(fx_parent, center(), dir, 16, Neon.WHITE_HOT)
	Audio.play("deflect", -2.0, 0.85)
	get_tree().call_group("game", "shockwave", center())
	var t := _tgt()
	if t != null and t.has_method("parried"):
		t.parried()


func _die(dir: Vector2) -> void:
	state = State.DEAD
	if not is_inside_tree():
		queue_free()
		return
	remove_from_group("hittable")
	remove_from_group("enemy")
	remove_from_group("possessable")
	remove_from_group("controlled")
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
	if controlled:
		_controlled_physics(delta)
		queue_redraw()
		return
	_flash = maxf(_flash - delta, 0.0)
	_shield_flash = maxf(_shield_flash - delta, 0.0)
	_spawn_pop = maxf(_spawn_pop - delta, 0.0)
	_grace = maxf(_grace - delta, 0.0)
	_down = maxf(_down - delta, 0.0)
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
	_crowd(delta)
	_update_rig(delta)
	queue_redraw()


## 轻度推挤：两台地面敌人重叠时各自往外让一点（最多 50 像素/秒），不会叠成一坨
func _crowd(delta: float) -> void:
	var r1 := hurt_rect()
	for o in get_tree().get_nodes_in_group("enemy"):
		if o == self or not (o is EnemyBot) or not o.alive():
			continue
		var r2: Rect2 = o.hurt_rect()
		if not r1.intersects(r2):
			continue
		var overlap := minf(r1.end.x, r2.end.x) - maxf(r1.position.x, r2.position.x)
		var dx: float = global_position.x - o.global_position.x
		var sgn := signf(dx) if absf(dx) > 0.01 else (1.0 if get_instance_id() > o.get_instance_id() else -1.0)
		var push := sgn * minf(overlap * 0.5, 50.0 * delta)
		if not test_move(global_transform, Vector2(push, 0)):
			global_position.x += push


func _patrol(delta: float) -> void:
	if _sees_player():
		facing = 1 if _tgt().global_position.x > global_position.x else -1
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


func _aim(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_t -= delta
	var t := _tgt()
	if _t > LOCK_TIME and t != null:
		facing = 1 if t.global_position.x > global_position.x else -1
		aim_dir = (t.global_position + Vector2(0, -24) - gun_pos()).normalized()
	if _t <= 0.0:
		if kind == "burst":
			for a in [-12.0, 0.0, 12.0]:
				Bullet.fire(fx_parent, gun_pos(), aim_dir.rotated(deg_to_rad(a)) * 300.0, Bullet.Team.ENEMY, 1, self)
			Audio.play("enemy_shot", -4.0, 0.85)
		else:
			Bullet.fire(fx_parent, gun_pos(), aim_dir * 260.0, Bullet.Team.ENEMY, 1, self)
			Audio.play("enemy_shot", -6.0)
		Fx.sparks(fx_parent, gun_pos(), aim_dir, 5, RED)
		rig.fire()
		state = State.COOLDOWN
		_t = 1.6 if kind == "burst" else 1.1


func _charge(delta: float) -> void:
	velocity.x = facing * 420.0
	_t -= delta
	var t := _tgt()
	if not _hit_player and t != null and hurt_rect().grow(2.0).intersects(t.hurt_rect()):
		_hit_player = true
		# 撞上的一刻玩家正面朝这边、正在出刀：算招架
		if t.has_method("parry_ready") and t.parry_ready(facing):
			_parried(Vector2(-facing, 0))
			return
		if t.has_method("melee_hit"):
			t.melee_hit(Vector2(facing, -0.3).normalized(), 1)
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


## 敌意目标：当前被玩家控制的那具机体（player 为 null 时这台敌人不主动攻击，测试里用来做靶子）
func _tgt() -> Node2D:
	if player == null:
		return null
	var t := get_tree().get_first_node_in_group("controlled")
	return t if t != self else null


func _sees_player() -> bool:
	var t := _tgt()
	if t == null or _grace > 0.0:
		return false
	var d := t.global_position - global_position
	var sight := Vector2(220, 60) if kind == "rusher" else SIGHT
	if absf(d.x) > sight.x or absf(d.y) > sight.y:
		return false
	var q := PhysicsRayQueryParameters2D.create(gun_pos(), t.global_position + Vector2(0, -24), 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


# ---------------------------------------------------------------- 被夺之后

func alive_for_possess() -> bool:
	return alive() and not controlled


func take_control(inp: PlayerInput, vel: Vector2) -> void:
	controlled = true
	input = inp
	velocity = vel
	_iframes = 0.25
	mut_k = 0.0
	wall = 0
	_rail_charge = -1.0
	_chain = 0
	# 异体生长：一圈青色碎晶炸开
	Fx.sparks(fx_parent, center(), Vector2.UP, 14, Color(1.0, 2.2, 2.4))
	Audio.play("mut_grow", -2.0)
	_flash = 0.0
	state = State.PATROL
	remove_from_group("enemy")
	remove_from_group("hittable")
	remove_from_group("possessable")
	add_to_group("controlled")


## 意识光流到达：目镜由暗到亮，身体一抖、往下一沉再站稳
func wake() -> void:
	rig.wake = 0.35
	rig._pelvis_v += 70.0
	rig._hit_v += 7.0 * facing


## 意识离开：断电报废
func release_control() -> void:
	controlled = false
	_die(Vector2(-facing, -0.5))


func invulnerable() -> bool:
	return _iframes > 0.0


func take_bullet(b: Node) -> bool:
	if not alive() or _iframes > 0.0:
		return false
	var dir: Vector2 = b.velocity.normalized()
	if has_shield() and dir.x * facing < -0.1:
		# 晶化盾：子弹原路弹回去（变成玩家方，打死射手）
		_shield_flash = 0.1
		Fx.sparks(fx_parent, center() + Vector2(facing * 12, 0), -dir, 8, Neon.CYAN_HOT)
		Audio.play("deflect", -6.0, 1.3)
		b.deflect(self)
		return false
	_controlled_hurt(dir, b.damage)
	return true


func melee_hit(dir: Vector2, dmg: int) -> void:
	if _iframes > 0.0:
		return
	_controlled_hurt(dir, dmg)


func _controlled_hurt(dir: Vector2, dmg: int) -> void:
	hp -= dmg
	_flash = 0.1
	rig.hit(dir.x, dmg, false)
	_iframes = 0.5
	velocity = Vector2(signf(dir.x) * 200.0, -160.0)
	Audio.play("hurt", -4.0)
	get_tree().call_group("game", "aberrate", 4.0)
	if hp <= 0:
		_die(dir)


func _controlled_physics(delta: float) -> void:
	input.poll(self)
	_flash = maxf(_flash - delta, 0.0)
	_shield_flash = maxf(_shield_flash - delta, 0.0)
	_iframes = maxf(_iframes - delta, 0.0)
	_weapon_cd = maxf(_weapon_cd - delta, 0.0)
	_bash_cd = maxf(_bash_cd - delta, 0.0)
	_hop_t = maxf(_hop_t - delta, 0.0)
	mut_k = minf(mut_k + delta / 0.3, 1.0)
	_recoil_v += (-_recoil * 220.0 - _recoil_v * 14.0) * delta
	_recoil += _recoil_v * delta
	var aim := _controlled_aim()
	aim_dir = aim
	_gun_hot = maxf(_gun_hot - delta, 0.0)
	if _ram_t > 0.0:
		if input.slash_pressed and _chain > 1:
			_chain_queue = true
		_ram(delta)
		move_and_slide()
		_update_rig(delta)
		return
	var dir := 0
	if input.move.x > 0.3:
		dir = 1
	elif input.move.x < -0.3:
		dir = -1
	if is_on_floor():
		_air_dash = true
	if wall != 0:
		_wall_physics(delta, dir)
	else:
		velocity.y = minf(velocity.y + GRAVITY * delta, 600.0)
		var top := (230.0 if input.run_held else 150.0) * (1.2 if kind == "rusher" else 1.0)
		if _hop_t <= 0.0:
			velocity.x = move_toward(velocity.x, dir * top, (1600.0 if dir != 0 else 1800.0) * delta)
		if dir != 0:
			facing = dir
		if input.jump_pressed and is_on_floor():
			velocity.y = -JUMP_V
			Fx.dust(fx_parent, global_position, 0.0, 5)
		# 灌注的机动：朝墙推就走上墙（地面撞墙、空中贴墙都行）
		if dir != 0 and is_on_wall() and test_move(global_transform, Vector2(dir * 2, 0)):
			wall = dir
			facing = dir
			velocity = Vector2(dir * 30.0, minf(velocity.y, 0.0))
			Audio.play("land", -12.0, 1.4)
	# L 冲刺（空中一次）：带残影
	if input.dash_pressed and _hop_t <= 0.0 and (is_on_floor() or wall != 0 or _air_dash):
		if not is_on_floor() and wall == 0:
			_air_dash = false
		if wall != 0:
			facing = -wall
			wall = 0
		_hop_t = 0.16
		velocity = Vector2(facing * 560.0, 0.0 if not is_on_floor() else velocity.y)
		Fx.dust(fx_parent, global_position, -facing, 6)
		Audio.play("dash", -6.0, 1.1)
	if _hop_t > 0.0 and wall == 0:
		velocity.y = minf(velocity.y, 40.0)
		if int(_hop_t * 100.0) % 3 == 0:
			Fx.streak(fx_parent, center(), float(facing), 26.0)
	_abilities(aim, delta)
	move_and_slide()
	_update_rig(delta)


## 墙面行走（和 R-0 同一套规则）：朝墙 / W 往上走，S 往下，不按就扒住；空格蹬墙跳；按离墙方向松开；到顶自动翻上去
func _wall_physics(delta: float, dir: int) -> void:
	var up := input.move.y < -0.3 or (dir == wall and input.move.y <= 0.3)
	var down := input.move.y > 0.3
	var spd := CLIMB_RUN if input.run_held else CLIMB
	var want := -spd if up else (spd if down else 0.0)
	velocity.y = move_toward(velocity.y, want, 1800.0 * delta)
	velocity.x = wall * 30.0
	facing = wall
	if input.jump_pressed:
		velocity = Vector2(-wall * 280.0, -JUMP_V * 0.9)
		facing = -wall
		wall = 0
		Fx.dust(fx_parent, global_position + Vector2(facing * -6, -8), float(facing), 4)
		Audio.play("walljump", -8.0, 1.2)
		return
	if dir == -wall or (down and is_on_floor()):
		wall = 0
		return
	# 走到墙顶：前面没有墙了，翻上去
	if not test_move(global_transform, Vector2(wall * 3, 0)):
		if velocity.y < 0.0:
			velocity = Vector2(wall * 170.0, -230.0)
		wall = 0


## 专属异体能力（K 主武器 / J 副手）
func _abilities(aim: Vector2, delta: float) -> void:
	# K
	match kind:
		"gunner":
			# 电磁长矛：按住蓄力，松开贯穿；轻点就是普通一枪
			if input.shoot_pressed and _weapon_cd <= 0.0:
				_rail_charge = 0.0
				Audio.play("rail_charge", -6.0)
			if _rail_charge >= 0.0:
				if input.shoot_held:
					var before := _rail_charge
					_rail_charge = minf(_rail_charge + delta, RAIL_MAX)
					if before < RAIL_MAX and _rail_charge >= RAIL_MAX:
						Audio.play("ui_ready", -4.0, 0.8)
					if int(_rail_charge * 30.0) % 3 == 0 and _rail_charge > 0.15:
						Fx.sparks(fx_parent, gun_pos(), aim, 1, Color(1.0, 2.2, 2.4))
				else:
					if _rail_charge < 0.15:
						_fire(aim)
					else:
						_rail(aim, 2 if _rail_charge < RAIL_MAX else 4)
					_rail_charge = -1.0
		"burst":
			if input.shoot_pressed and _weapon_cd <= 0.0:
				_swarm(aim)
		"rusher":
			if input.shoot_pressed and _weapon_cd <= 0.0:
				_start_chain(1)
				_weapon_cd = 0.8
	# J
	if input.slash_pressed and _bash_cd <= 0.0:
		if shielded and has_shield():
			_throw_shield(aim)
		elif kind == "rusher":
			_start_chain(3)
			_bash_cd = 0.9
		else:
			_bash()


## 电磁长矛：一条直线贯穿所有敌人（盾也挡不住），直到撞墙
func _rail(aim: Vector2, power: int) -> void:
	if absf(aim.x) > 0.2:
		facing = 1 if aim.x > 0.0 else -1
	var from := gun_pos()
	var to := from + aim * 480.0
	var q := PhysicsRayQueryParameters2D.create(from, to, 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		to = hit.position
	for n in get_tree().get_nodes_in_group("hittable"):
		if n == self or (n.has_method("alive") and not n.alive()):
			continue
		if Bullet._segment_hits(from, to, n.hurt_rect().grow(3.0)):
			n.take_hit(aim, power, "rail")
	RailFx.spawn(fx_parent, from, to, power)
	Audio.play("rail_fire", 0.0)
	get_tree().call_group("game", "impact", 3.0 + power, -aim)
	TimeFx.hitstop(0.04)
	rig.fire()
	_recoil_v -= facing * 14.0
	_weapon_cd = 0.45
	_gun_hot = 0.8


## 蜂群追踪弹：6 发扇形射出，各自找一个敌人
func _swarm(aim: Vector2) -> void:
	if absf(aim.x) > 0.2:
		facing = 1 if aim.x > 0.0 else -1
	var targets := []
	for n in get_tree().get_nodes_in_group("hittable"):
		if n != self and (not n.has_method("alive") or n.alive()) and n.global_position.distance_to(global_position) < 420.0:
			targets.append(n)
	targets.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	for i in 6:
		var a := deg_to_rad(-50.0 + i * 20.0)
		var b := Bullet.fire(fx_parent, gun_pos() + Vector2(-facing * 4, -6), aim.rotated(a) * 360.0, Bullet.Team.PLAYER, 1, self)
		if not targets.is_empty():
			b.homing = targets[i % targets.size()]
	Fx.sparks(fx_parent, gun_pos(), aim, 6, Neon.CYAN_HOT)
	Audio.play("swarm", -2.0)
	rig.fire()
	_weapon_cd = 0.9
	_gun_hot = 0.8


## 冲锋机连撞：segments 段，每段 0.3 秒；撞墙自动反弹算一段；段中按 J 预约下一段（朝当前方向）
func _start_chain(segments: int) -> void:
	_chain = segments
	_chain_queue = false
	_ram_t = 0.3
	_ram_hit.clear()
	Audio.play("dash", -4.0, 0.8)
	get_tree().call_group("game", "impact", 2.0, Vector2(facing, 0))


## 晶化盾掷出去回旋
func _throw_shield(aim: Vector2) -> void:
	_shield_out = true
	_bash_cd = 0.4
	var d := ShieldDisc.new()
	d.owner_bot = self
	d.dir = Vector2(facing, 0) if absf(aim.x) < 0.3 else Vector2(signf(aim.x), clampf(aim.y, -0.5, 0.5)).normalized()
	get_parent().add_child(d)
	d.global_position = center() + Vector2(facing * 10, 0)


func _update_rig(delta: float) -> void:
	var mode := "idle"
	# 墙面行走：骨架转 90°，脚踩墙
	rig.extra_rot = lerp_angle(rig.extra_rot, -PI * 0.5 * wall if wall != 0 else 0.0, 1.0 - exp(-14.0 * delta))
	rig.mut_k = mut_k if controlled else 0.0
	rig.charge_k = clampf(_rail_charge / RAIL_MAX, 0.0, 1.0) if _rail_charge >= 0.0 else 0.0
	if controlled:
		if _ram_t > 0.0:
			mode = "charge"
		elif wall != 0:
			mode = "walk" if absf(velocity.y) > 5.0 else "idle"
		elif not is_on_floor():
			mode = "air"
		elif _hop_t > 0.0:
			mode = "hop"
		elif absf(velocity.x) > 5.0:
			mode = "walk"
	else:
		match state:
			State.PATROL:
				mode = "walk" if absf(velocity.x) > 5.0 else "idle"
			State.AIM:
				mode = "aim"
			State.STAGGER:
				mode = "down" if _down > 0.0 else "stagger"
			State.AIR:
				mode = "air"
			State.WINDUP:
				mode = "windup"
			State.CHARGE:
				mode = "charge"
	var s := (1.0 + _spawn_pop * 2.0) * (1.2 if elite else 1.0)
	var t: float = rig.turn
	rig.scale = Vector2((signf(t) if t != 0.0 else float(facing)) * maxf(absf(t), 0.08) * s, s)
	rig.controlled = controlled
	rig.flash = _flash > 0.0 or (controlled and _iframes > 0.0 and int(_iframes * 20.0) % 2 == 0)
	var a := aim_dir if (state == State.AIM or controlled) else Vector2(facing, 0.3).normalized()
	rig.update({
		"state": mode,
		"facing": facing,
		"vel": Vector2(absf(velocity.y) * facing, 0.0) if wall != 0 else velocity,
		"aim": a,
		"aim_k": clampf(1.0 - _t / aim_time(), 0.0, 1.0) if state == State.AIM else 0.0,
		"weapon_hot": _gun_hot > 0.0 or (controlled and input != null and not input.aim_keys),
	}, delta)
	var xf := rig.get_global_transform()
	for k in rig.parts_local:
		hurtboxes.set_part(k, xf * rig.parts_local[k])


func _controlled_aim() -> Vector2:
	if input.aim_keys or input.aim.length() < 0.1:
		if is_instance_valid(lock_target):
			return (lock_target.global_position + Vector2(0, -18) - gun_pos()).normalized()
		return Vector2(facing, 0)
	var a := input.aim.normalized()
	if is_instance_valid(lock_target):
		var to: Vector2 = lock_target.global_position + Vector2(0, -18) - gun_pos()
		if absf(a.angle_to(to)) <= deg_to_rad(15.0):
			return to.normalized()
	return a


func _fire(aim: Vector2) -> void:
	if absf(aim.x) > 0.2:
		facing = 1 if aim.x > 0.0 else -1
	match kind:
		"burst":
			for a in [-10.0, 0.0, 10.0]:
				Bullet.fire(fx_parent, gun_pos(), aim.rotated(deg_to_rad(a)) * 480.0, Bullet.Team.PLAYER, 1, self)
			_weapon_cd = 0.6
			Audio.play("enemy_shot", -5.0, 1.1)
		_:
			Bullet.fire(fx_parent, gun_pos(), aim * 560.0, Bullet.Team.PLAYER, 2, self)
			_weapon_cd = 0.35
			Audio.play("shot", -4.0, 0.8)
	Fx.sparks(fx_parent, gun_pos(), aim, 5, Neon.CYAN_HOT)
	rig.fire()
	_gun_hot = 0.8


## 冲锋机被夺后的冲撞：一路撞过去，撞到的敌人各吃 2 点；连撞时撞墙反弹继续撞
func _ram(delta: float) -> void:
	_ram_t -= delta
	velocity = Vector2(facing * 560.0, minf(velocity.y + GRAVITY * delta, 600.0))
	for n in get_tree().get_nodes_in_group("hittable"):
		if _ram_hit.has(n) or (n.has_method("alive") and not n.alive()):
			continue
		if hurt_rect().grow(4.0).intersects(n.hurt_rect()):
			_ram_hit[n] = true
			n.take_hit(Vector2(facing, -0.3).normalized(), 2, "slash")
			Fx.sparks(fx_parent, n.hurt_rect().get_center(), Vector2(facing, 0), 10, Neon.WHITE_HOT)
			Audio.play("hit_heavy", -3.0)
			get_tree().call_group("game", "shockwave", n.hurt_rect().get_center())
			TimeFx.hitstop(0.03)
	var bonk := is_on_wall()
	if bonk or _ram_t <= 0.0:
		if _chain > 1 and (bonk or _chain_queue):
			_chain -= 1
			_chain_queue = false
			if bonk:
				facing = -facing
				Fx.sparks(fx_parent, center() + Vector2(-facing * 8, 0), Vector2(facing, 0), 12, Color(1.0, 2.2, 2.4))
				Audio.play("shield_block", -4.0, 0.9)
				get_tree().call_group("game", "impact", 4.0, Vector2(facing, 0))
			elif absf(input.move.x) > 0.3:
				facing = 1 if input.move.x > 0.0 else -1
			_ram_t = 0.3
			_ram_hit.clear()
			Audio.play("dash", -5.0, 0.9)
		else:
			_ram_t = 0.0
			_chain = 0


## 近战撞击：身前一小块范围，伤害 1
func _bash() -> void:
	_bash_cd = 0.3
	_recoil_v -= facing * 8.0
	var c := center() + Vector2(facing * 16, 0)
	var hit := false
	for n in get_tree().get_nodes_in_group("hittable"):
		if n.has_method("alive") and not n.alive():
			continue
		var r: Rect2 = n.hurt_rect()
		var closest := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
		if closest.distance_to(c) <= 16.0:
			n.take_hit(Vector2(facing, 0), 1, "slash")
			Fx.sparks(fx_parent, closest, Vector2(facing, 0), 8, Neon.WHITE_HOT)
			hit = true
	Audio.play("hit" if hit else "swing_1", -3.0)


func _draw() -> void:
	var red_c := Color(0.3, 1.1, 1.25) if controlled else RED
	# （湿地面倒影改由场景的积水反射统一处理）
	# 身体由 EnemyRig 画（程序化动画骨架）
	# 瞄准线：越接近开火越亮越粗，锁定后变白
	if state == State.AIM:
		var gp := gun_pos() - global_position
		var k := 1.0 - _t / aim_time()
		var locked := _t <= LOCK_TIME
		var c := Color(1.3, 1.25, 1.25, 0.8) if locked else Color(1.2, 0.2, 0.25, 0.2 + 0.45 * k)
		var spreads := [-12.0, 0.0, 12.0] if kind == "burst" else [0.0]
		for a in spreads:
			draw_line(gp, gp + aim_dir.rotated(deg_to_rad(a)) * 320.0, Color(c, c.a * 0.5), 1.0)
		# 锁定框：在目标身上收紧（学《碳酸危机》），收紧前打断就不开枪
		var tg := _tgt()
		if tg != null:
			var r: Rect2 = tg.hurt_rect()
			AimLock.draw(self, Rect2(r.position - global_position, r.size), k)
	# 冲锋蓄力：地面上一道红色预警
	if state == State.WINDUP:
		var k := 1.0 - _t / 0.4
		draw_rect(Rect2(minf(0.0, facing * 200.0), -2, 200, 2), Color(2.0, 0.3, 0.35, 0.2 + 0.5 * k))
	# 能量盾
	if has_shield():
		# 塔盾（像素贴图）：完好 / 裂开 / 快碎三种状态；挨打时闪白
		var state_name: String = ["shield_break", "shield_crack", "shield"][clampi(shield_hp - 1, 0, 2)]
		var part := PixelPart.get_part("res://assets/sprites/trooper/" + state_name + ("_p" if controlled else ""))
		var mod := Color(3.0, 3.0, 3.0) if _shield_flash > 0.0 else Color.WHITE
		part.draw(self, Transform2D.IDENTITY, Vector2(facing * 10.0, -16.0), 0.0, facing < 0, mod)
		# 异体：盾沿长出一圈晶体碎片
		if controlled and mut_k > 0.0:
			var sh := PixelPart.get_part("res://assets/sprites/mut/shard")
			var e := 1.0 - pow(1.0 - mut_k, 3.0)
			for i in 4:
				var y := -30.0 + i * 9.0
				sh.draw(self, Transform2D.IDENTITY, Vector2(facing * (16.0 + 3.0 * e), y + 4.0 * (1.0 - e)), deg_to_rad(90.0 * facing), false)
