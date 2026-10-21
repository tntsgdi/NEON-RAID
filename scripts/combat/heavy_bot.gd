class_name HeavyBot
extends CharacterBody2D
## 重装机（M4）。三种身份：
##   敌对精英（hostile）：巡逻；看见你 → 远了蓄力冲撞、近了举锤砸地（都有明显预警）。
##       刀、子弹、踩头都削它的"耐久"，但不会被打退、不会被踩趴（霸体）。
##       耐久打空 → 瘫痪 4 秒（目镜闪白 = 可以夺）；瘫痪中还被打会伤到本体；没夺就站起来，耐久回一半。
##   停放的空壳（parked）：跪坐、目镜暗着，随时可以夺（谜题区的钥匙）。
##   被夺（controlled）：J 冲撞（撞碎可破墙、撞飞敌人、直接破盾），K 砸地（冲击波掀翻周围、砸穿薄地板；
##       空中按 K 从高处砸下，范围更大）；跳得很矮、不能墙面行走、慢，但不会被打退。
##       意识离开时断电跪下，变回停放的空壳（可以再回来夺）。

signal died(bot: HeavyBot)

enum State { PATROL, WINDUP_RAM, RAM, WINDUP_SLAM, SLAM, RECOVER, STUNNED, PARKED, DEAD }

const SIZE := Vector2(34, 60)
const GRAVITY := 1600.0
const WALK := 32.0
const CONTROL_HP := 6
const MAX_HP := CONTROL_HP
const HOSTILE_HP := 12
const POISE := 8.0
const STUN_TIME := 4.0
const SIGHT := Vector2(280, 130)

var hostile := true
var player: Node2D
var fx_parent: Node
var patrol_range := 40.0
var facing := -1
var hp := HOSTILE_HP
var poise := POISE
var state := State.PATROL
var controlled := false
var input: PlayerInput
var lock_target: Node2D
var rig: HeavyRig
var hurtboxes: Hurtboxes

var _home := Vector2.ZERO
var _t := 0.0
var _flash := 0.0
var _iframes := 0.0
var _hit_once := false
var _slam_air := false
var _ram_hit := {}
var _grace := 0.6
## 被夺后的技能冷却：冲撞 0.8 秒、砸地 1.2 秒（不让重装机变成无限推土机）
var _ram_cd := 0.0
var _slam_cd := 0.0
const RAM_CD := 0.8
const SLAM_CD := 1.2


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 6.0
	var shape := RectangleShape2D.new()
	shape.size = SIZE
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = Vector2(0, -SIZE.y * 0.5)
	add_child(cs)
	_home = global_position
	if fx_parent == null:
		fx_parent = get_parent()
	rig = HeavyRig.new()
	rig.light_mask = Neon.ACTOR_LIGHT_MASK
	add_child(rig)
	hurtboxes = Hurtboxes.new()
	add_child(hurtboxes)
	light_mask = Neon.ACTOR_LIGHT_MASK
	if hostile:
		add_to_group("hittable")
		add_to_group("enemy")
		Neon.add_light(self, Neon.RED, 0.3, 1.2, Vector2(0, -26))
	else:
		_park()


func alive() -> bool:
	return state != State.DEAD


func hurt_rect() -> Rect2:
	return Rect2(global_position + Vector2(-SIZE.x * 0.5, -SIZE.y), SIZE)


func center() -> Vector2:
	return global_position + Vector2(0, -SIZE.y * 0.55)


func invulnerable() -> bool:
	return _iframes > 0.0


## 停放：跪坐、目镜暗着、可以夺
func _park() -> void:
	state = State.PARKED
	hostile = false
	velocity = Vector2.ZERO
	remove_from_group("hittable")
	remove_from_group("enemy")
	add_to_group("possessable")


# ---------------------------------------------------------------- 挨打（敌对时）

## 返回 0 = 没打到，1 = 打到
func take_hit(dir: Vector2, power: int, hit_kind := "slash") -> int:
	if not alive() or controlled or state == State.PARKED:
		return 0
	_flash = 0.08
	rig.hit(dir.x if absf(dir.x) > 0.1 else float(-facing), power)
	if state == State.STUNNED:
		hp -= power
		get_tree().call_group("game", "combo_hit", self, power, hp <= 0)
		if hp <= 0:
			_die(dir)
		return 1
	get_tree().call_group("game", "combo_hit", self, power, false)
	poise -= float(power) * (0.5 if hit_kind == "bullet" else 1.0)
	velocity.x += signf(dir.x) * 20.0  # 霸体：只晃一下
	if poise <= 0.0:
		_stun()
	return 1


func _stun() -> void:
	state = State.STUNNED
	_t = STUN_TIME
	velocity.x = 0.0
	add_to_group("possessable")
	Fx.sparks(fx_parent, center(), Vector2.UP, 18, Color(2.2, 2.3, 2.4))
	Fx.ring(fx_parent, center(), 30.0)
	Audio.play("break", -4.0, 0.7)
	get_tree().call_group("game", "shockwave", center())


## 冲撞中被正面招架：耐久大减
func _parried() -> void:
	poise -= POISE * 0.5
	state = State.RECOVER
	_t = 1.0
	velocity = Vector2(-facing * 120.0, -80.0)
	Fx.sparks(fx_parent, center(), Vector2(-facing, 0), 16, Neon.WHITE_HOT)
	Audio.play("deflect", -2.0, 0.7)
	get_tree().call_group("game", "shockwave", center())
	if poise <= 0.0:
		_stun()


func _die(dir: Vector2) -> void:
	state = State.DEAD
	remove_from_group("hittable")
	remove_from_group("enemy")
	remove_from_group("possessable")
	remove_from_group("controlled")
	var base := global_position
	var push := Vector2(signf(dir.x) if absf(dir.x) > 0.1 else -facing, -0.6).normalized()
	var col := Color(1.25, 0.26, 0.32) if not controlled else Color(0.3, 1.1, 1.25)
	var v := "_p" if controlled else ""
	FxPart.spawn_sprite(fx_parent, base + Vector2(0, -34), "heavy/torso" + v, push * 160.0 + Vector2(0, -120), Vector2(20, 16))
	FxPart.spawn_sprite(fx_parent, base + Vector2(-facing * 4, -54), "heavy/head" + v, push * 260.0 + Vector2(0, -240), Vector2(10, 9))
	FxPart.spawn_sprite(fx_parent, base + Vector2(-facing * 10, -34), "heavy/plate" + v, push * 240.0 + Vector2(0, -180), Vector2(12, 8))
	FxPart.spawn_sprite(fx_parent, base + Vector2(facing * 14, -30), "heavy/hammer" + v, push * 220.0 + Vector2(facing * 60, -160), Vector2(12, 8))
	FxPart.spawn_sprite(fx_parent, base + Vector2(-5, -14), "heavy/thigh" + v, push * 110.0 + Vector2(-70, -120), Vector2(6, 12))
	FxPart.spawn_sprite(fx_parent, base + Vector2(5, -6), "heavy/foot" + v, push * 120.0 + Vector2(70, -130), Vector2(8, 5))
	Fx.debris(fx_parent, center(), dir, 18, col)
	Fx.sparks(fx_parent, center(), dir, 24, Color(2.6, 1.0, 0.7))
	Fx.flash(fx_parent, center(), Color(2.8, 0.9, 0.6), 30.0)
	Audio.play("break", 0.0, 0.7)
	Audio.play("kill", -2.0, 0.75)
	get_tree().call_group("game", "shockwave", center())
	died.emit(self)
	queue_free()


# ---------------------------------------------------------------- 被夺

func take_control(inp: PlayerInput, vel: Vector2) -> void:
	controlled = true
	hostile = false
	rig.mut_k = 0.0
	Fx.sparks(fx_parent, center(), Vector2.UP, 18, Color(1.0, 2.2, 2.4))
	Audio.play("mut_grow", -2.0, 0.8)
	# 附身瞬间：一圈冲击环 + 轻震，像机体被"点燃"
	Fx.ring(fx_parent, center(), 28.0)
	get_tree().call_group("game", "impact", 3.5, Vector2.ZERO)
	input = inp
	velocity = Vector2(vel.x * 0.5, vel.y)
	hp = CONTROL_HP
	_iframes = 0.3
	state = State.PATROL
	remove_from_group("enemy")
	remove_from_group("hittable")
	remove_from_group("possessable")
	add_to_group("controlled")


## 意识离开：断电跪下，变回停放的空壳（谜题里可以回来再夺）
func release_control() -> void:
	controlled = false
	remove_from_group("controlled")
	_park()


func wake() -> void:
	rig.wake = 0.4
	rig._pelvis_v += 90.0
	rig._lean_v -= 60.0


func take_bullet(b: Node) -> bool:
	if not alive() or _iframes > 0.0:
		return false
	_controlled_hurt(b.velocity.normalized(), b.damage)
	return true


func melee_hit(dir: Vector2, dmg: int) -> void:
	if _iframes > 0.0:
		return
	_controlled_hurt(dir, dmg)


## 被夺时挨打：掉血，但不被打退
func _controlled_hurt(dir: Vector2, dmg: int) -> void:
	hp -= dmg
	_flash = 0.1
	_iframes = 0.4
	rig.hit(dir.x, dmg)
	Audio.play("hurt", -4.0, 0.8)
	get_tree().call_group("game", "aberrate", 4.0)
	if hp <= 0:
		_die(dir)


# ---------------------------------------------------------------- 每帧

func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_iframes = maxf(_iframes - delta, 0.0)
	_grace = maxf(_grace - delta, 0.0)
	_ram_cd = maxf(_ram_cd - delta, 0.0)
	_slam_cd = maxf(_slam_cd - delta, 0.0)
	velocity.y = minf(velocity.y + GRAVITY * delta, 900.0 if _slam_air else 650.0)
	if controlled:
		_controlled(delta)
	else:
		_ai(delta)
	var was_floor := is_on_floor()
	var vy := velocity.y
	move_and_slide()
	if not was_floor and is_on_floor() and vy > 250.0:
		Fx.dust(fx_parent, global_position, 0.0, 8)
		get_tree().call_group("game", "impact", 3.0, Vector2.DOWN)
	if _slam_air and is_on_floor():
		_slam_air = false
		# 附身强化：从天而降，范围和伤害翻倍
		_slam_impact(200.0, 6)
	_update_rig(delta)


func _ai(delta: float) -> void:
	match state:
		State.PARKED:
			velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
		State.PATROL:
			var t := _tgt()
			if t != null and _grace <= 0.0 and _sees(t):
				facing = 1 if t.global_position.x > global_position.x else -1
				if absf(t.global_position.x - global_position.x) < 70.0:
					state = State.WINDUP_SLAM
					_t = 0.6
				else:
					state = State.WINDUP_RAM
					_t = 0.65
				Audio.play("charge", -8.0, 0.7)
				return
			if global_position.x > _home.x + patrol_range:
				facing = -1
			elif global_position.x < _home.x - patrol_range:
				facing = 1
			elif is_on_wall():
				facing = -facing
			velocity.x = facing * WALK
		State.WINDUP_RAM:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			_t -= delta
			if _t <= 0.0:
				state = State.RAM
				_t = 0.7
				_hit_once = false
				_ram_hit.clear()
				Audio.play("dash", -4.0, 0.6)
		State.RAM:
			_ram_step(delta, 360.0)
			if _t <= 0.0 or is_on_wall():
				_ram_end()
		State.WINDUP_SLAM:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			_t -= delta
			if _t <= 0.0:
				state = State.SLAM
				_t = 0.5
				_slam_impact(80.0, 1)
		State.SLAM, State.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			_t -= delta
			if _t <= 0.0:
				state = State.PATROL
		State.STUNNED:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			_t -= delta
			if _t <= 0.0:
				# 没被夺：站起来，耐久回一半
				poise = POISE * 0.5
				remove_from_group("possessable")
				state = State.RECOVER
				_t = 0.5


func _controlled(delta: float) -> void:
	input.poll(self)
	match state:
		State.RAM:
			_ram_step(delta, 400.0)
			if _t <= 0.0 or is_on_wall():
				_ram_end()
			return
		State.WINDUP_SLAM:
			velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
			_t -= delta
			if _t <= 0.0:
				state = State.SLAM
				_t = 0.25
				_slam_impact(80.0, 2)
			return
		State.SLAM, State.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
			_t -= delta
			if _t <= 0.0:
				state = State.PATROL
			return
	var dir := 0
	if input.move.x > 0.3:
		dir = 1
	elif input.move.x < -0.3:
		dir = -1
	var top := 150.0 if input.run_held else 115.0
	velocity.x = move_toward(velocity.x, dir * top, (900.0 if dir != 0 else 1200.0) * delta)
	if dir != 0:
		facing = dir
	if input.jump_pressed and is_on_floor():
		# 附身强化：长出鸟腿，跳得很高（约 140 像素）；仍然不能墙面行走
		velocity.y = -680.0
		rig.jump_kick()
		Fx.dust(fx_parent, global_position, 0.0, 5)
	if input.slash_pressed and _ram_cd <= 0.0:
		_ram_cd = RAM_CD
		state = State.RAM
		_t = 0.35
		_ram_hit.clear()
		Audio.play("dash", -4.0, 0.6)
		get_tree().call_group("game", "impact", 2.0, Vector2(facing, 0))
	elif input.shoot_pressed and _slam_cd <= 0.0:
		_slam_cd = SLAM_CD
		if is_on_floor():
			state = State.WINDUP_SLAM
			_t = 0.22
			Audio.play("charge", -8.0, 0.6)
		elif not _slam_air:
			# 空中砸地：垂直砸下去，落地冲击范围更大
			_slam_air = true
			velocity = Vector2(0, 700.0)
			Audio.play("dash", -4.0, 0.5)


## 冲撞：一路往前，撞飞敌人（直接破盾）、撞碎可破墙；敌对时撞到玩家 = 1 点伤害（正面出刀可招架）
func _ram_step(delta: float, speed: float) -> void:
	velocity.x = facing * speed
	_t -= delta
	var front := hurt_rect().grow_individual(4.0 if facing < 0 else 0.0, 0.0, 4.0 if facing > 0 else 0.0, 0.0)
	front.position.x += facing * 6.0
	for b in get_tree().get_nodes_in_group("breakable"):
		if b.kind == "wall" and front.intersects(b.global_rect()):
			b.smash(Vector2(facing, -0.2))
			get_tree().call_group("game", "impact", 6.0, Vector2(facing, 0))
			TimeFx.hitstop(0.06)
	if controlled:
		for n in get_tree().get_nodes_in_group("hittable"):
			if _ram_hit.has(n) or (n.has_method("alive") and not n.alive()):
				continue
			if front.intersects(n.hurt_rect()):
				_ram_hit[n] = true
				if n.get("shield_hp") != null:
					n.shield_hp = 0
				n.take_hit(Vector2(facing, -0.4).normalized(), 2, "ram")
				Fx.sparks(fx_parent, n.hurt_rect().get_center(), Vector2(facing, 0), 12, Neon.WHITE_HOT)
				Audio.play("ram_hit", -1.0, 0.8)
				get_tree().call_group("game", "impact", 5.0, Vector2(facing, 0))
				TimeFx.hitstop(0.05)
	else:
		var t := _tgt()
		if not _hit_once and t != null and front.intersects(t.hurt_rect()):
			_hit_once = true
			if t.has_method("parry_ready") and t.parry_ready(facing):
				_parried()
				return
			if t.has_method("melee_hit"):
				t.melee_hit(Vector2(facing, -0.4).normalized(), 1)


func _ram_end() -> void:
	if is_on_wall():
		Fx.sparks(fx_parent, global_position + Vector2(facing * 14, -20), Vector2(-facing, 0), 12, Color(1.6, 1.4, 1.2))
		Audio.play("shield_block", -4.0, 0.6)
		get_tree().call_group("game", "impact", 5.0, Vector2(facing, 0))
	state = State.RECOVER
	_t = 0.25 if controlled else 1.0


## 砸地：冲击波（半径 radius）掀翻周围的敌人 / 伤到玩家，砸穿脚下附近的薄地板
func _slam_impact(radius: float, power: int) -> void:
	var at := global_position + Vector2(facing * 14.0, 0)
	Fx.dust(fx_parent, at, 0.0, 14)
	Fx.ring(fx_parent, at + Vector2(0, -4), radius)
	Fx.sparks(fx_parent, at, Vector2.UP, 14, Color(2.2, 1.6, 0.8))
	Audio.play("slam", 0.0 if controlled else -3.0)
	get_tree().call_group("game", "shockwave", at)
	get_tree().call_group("game", "impact", 8.0, Vector2.DOWN)
	TimeFx.hitstop(0.06)
	for b in get_tree().get_nodes_in_group("breakable"):
		if b.kind != "floor":
			continue
		var r: Rect2 = b.global_rect()
		if r.position.y >= global_position.y - 4.0 and r.position.y <= global_position.y + 30.0 and r.position.x - radius * 0.8 < global_position.x and r.end.x + radius * 0.8 > global_position.x:
			b.smash(Vector2.DOWN)
	if controlled:
		for n in get_tree().get_nodes_in_group("hittable"):
			if n.has_method("alive") and not n.alive():
				continue
			var c: Vector2 = n.hurt_rect().get_center()
			if c.distance_to(at) <= radius and absf(c.y - at.y) < 60.0:
				n.take_hit(Vector2(signf(c.x - at.x), -1.0).normalized(), power, "slam")
	else:
		var t := _tgt()
		if t != null and t.global_position.distance_to(at) <= radius and t.has_method("melee_hit"):
			if not ("state" in t and t is Player and t.state == Player.State.AIR):
				t.melee_hit(Vector2(signf(t.global_position.x - at.x), -0.6).normalized(), 1)


func _tgt() -> Node2D:
	if player == null:
		return null
	var t := get_tree().get_first_node_in_group("controlled")
	return t if t != self else null


func _sees(t: Node2D) -> bool:
	var d := t.global_position - global_position
	if absf(d.x) > SIGHT.x or absf(d.y) > SIGHT.y:
		return false
	var q := PhysicsRayQueryParameters2D.create(center(), t.global_position + Vector2(0, -18), 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _update_rig(delta: float) -> void:
	var mode := "idle"
	var k := 0.0
	match state:
		State.PATROL:
			if controlled and not is_on_floor():
				mode = "dive" if _slam_air else "air"
			else:
				mode = "walk" if absf(velocity.x) > 5.0 else "idle"
		State.WINDUP_RAM:
			mode = "windup_ram"
			k = 1.0 - _t / 0.65
		State.RAM:
			mode = "ram"
		State.WINDUP_SLAM:
			mode = "windup_slam"
			k = 1.0 - _t / (0.22 if controlled else 0.6)
		State.SLAM:
			mode = "slam"
		State.RECOVER:
			mode = "recover"
		State.STUNNED:
			mode = "stunned"
		State.PARKED:
			mode = "parked"
	if _slam_air:
		mode = "dive"
	rig.look = "controlled" if controlled else ("stunned" if state == State.STUNNED else ("parked" if state == State.PARKED else "hostile"))
	rig.flash = _flash > 0.0 or (controlled and _iframes > 0.0 and int(_iframes * 20.0) % 2 == 0)
	rig.update({"state": mode, "facing": facing, "vel": velocity, "k": clampf(k, 0.0, 1.0)}, delta)
	var t: float = rig.turn
	rig.scale = Vector2((signf(t) if t != 0.0 else float(facing)) * maxf(absf(t), 0.08), 1.0)
	if rig.footfall:
		Fx.dust(fx_parent, global_position + Vector2(facing * 6, 0), 0.0, 3)
		if controlled:
			get_tree().call_group("game", "impact", 1.2, Vector2.DOWN)
	var xf := rig.get_global_transform()
	for p in rig.parts_local:
		hurtboxes.set_part(p, xf * rig.parts_local[p])
	queue_redraw()


func _draw() -> void:
	# 冲撞预警：地面一道红线；砸地预警：脚下一圈
	if state == State.WINDUP_RAM:
		var k := 1.0 - _t / 0.65
		draw_rect(Rect2(minf(0.0, facing * 220.0), -2, 220, 2), Color(2.0, 0.3, 0.35, 0.2 + 0.6 * k))
	elif state == State.WINDUP_SLAM and not controlled:
		var k := 1.0 - _t / 0.6
		draw_arc(Vector2(facing * 14.0, -2), 80.0 * k, PI, TAU, 24, Color(2.0, 0.3, 0.35, 0.3 + 0.5 * k), 1.5)
	# 敌对时头顶的耐久条（瘫痪时变成倒计时）
	if hostile and state != State.DEAD:
		var w := 26.0
		var y := -SIZE.y - 10.0
		draw_rect(Rect2(-w * 0.5, y, w, 3), Color(0.1, 0.03, 0.05, 0.8))
		if state == State.STUNNED:
			draw_rect(Rect2(-w * 0.5, y, w * clampf(_t / STUN_TIME, 0.0, 1.0), 3), Color(2.0, 2.1, 2.2))
		else:
			draw_rect(Rect2(-w * 0.5, y, w * clampf(poise / POISE, 0.0, 1.0), 3), Color(1.8, 0.35, 0.4))
