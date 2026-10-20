class_name EnemyBot
extends CharacterBody2D
## 轻型安保机（M2 第一种敌人）。shielded = 盾兵变体。
## 巡逻 → 看见玩家 → 0.5 秒红色瞄准线（最后 0.12 秒锁定方向，躲得开）→ 一发慢速红弹 → 冷却。
## 被打：硬直 + 击退；上挑或重击会被打上天，可以空中连击；4 血，打空爆碎。
## 盾兵：正面能量盾，子弹从正面打会被弹开；刀砍 3 下破盾；从背后或头上打直接伤本体。

signal died(bot: EnemyBot)

enum State { PATROL, AIM, COOLDOWN, STAGGER, AIR, DEAD }

const RED := Color(0.92, 0.2, 0.26)
const DARK := Color(0.2, 0.05, 0.08)
const SIZE := Vector2(14, 34)
const GRAVITY := 1400.0
const WALK := 45.0
const SIGHT := Vector2(300, 150)
const AIM_TIME := 0.5
const LOCK_TIME := 0.12
const COOLDOWN := 1.1
const BULLET_SPEED := 260.0
const MAX_HP := 4
const SHIELD_HP := 3

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
	if fx_parent == null:
		fx_parent = get_parent()


func alive() -> bool:
	return state != State.DEAD


func hurt_rect() -> Rect2:
	return Rect2(global_position + Vector2(-SIZE.x * 0.5, -SIZE.y), SIZE)


func center() -> Vector2:
	return global_position + Vector2(0, -SIZE.y * 0.55)


func gun_pos() -> Vector2:
	return global_position + Vector2(facing * 9, -21)


func has_shield() -> bool:
	return shielded and shield_hp > 0


## 返回 0 = 没打到，1 = 打到，2 = 被盾挡住（子弹会弹开）
func take_hit(dir: Vector2, power: int, kind := "slash") -> int:
	if not alive():
		return 0
	var from_front := dir.x * facing < -0.1
	var from_above := dir.y > 0.5
	if has_shield() and from_front and not from_above:
		if kind == "bullet":
			_shield_flash = 0.08
			return 2
		shield_hp -= power
		_shield_flash = 0.1
		velocity.x = signf(dir.x) * 90.0
		if shield_hp <= 0:
			Fx.debris(fx_parent, center() + Vector2(facing * 10, 0), dir, 10, RED)
			Fx.sparks(fx_parent, center() + Vector2(facing * 10, 0), dir, 12, Color(1, 0.6, 0.6))
			Audio.play("break", -6.0, 1.3)
		else:
			Audio.play("shield_block", -4.0)
		return 1
	hp -= power
	_flash = 0.08
	var sx := signf(dir.x) if absf(dir.x) > 0.1 else float(-facing)
	velocity.x = sx * (150.0 + 80.0 * power)
	if dir.y < -0.5:
		velocity.y = -360.0  # 上挑：打上天
		state = State.AIR
	elif state == State.AIR or (power >= 2 and kind == "slash" and dir.y <= 0.1):
		velocity.y = minf(velocity.y, -240.0)  # 空中连击 / 重击：保持浮空
		state = State.AIR
	else:
		state = State.STAGGER
		_t = 0.35
	if hp <= 0:
		_die(dir)
	return 1


func _die(dir: Vector2) -> void:
	state = State.DEAD
	remove_from_group("hittable")
	remove_from_group("enemy")
	Fx.debris(fx_parent, center(), dir, 20, RED)
	Fx.debris(fx_parent, center(), dir, 10, Color(0.3, 0.33, 0.4))
	Fx.sparks(fx_parent, center(), dir, 16, Color(1.0, 0.6, 0.5))
	Audio.play("break", -2.0)
	died.emit(self)
	queue_free()


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_shield_flash = maxf(_shield_flash - delta, 0.0)
	_spawn_pop = maxf(_spawn_pop - delta, 0.0)
	velocity.y = minf(velocity.y + GRAVITY * delta, 600.0)
	match state:
		State.PATROL:
			_patrol(delta)
		State.AIM:
			_aim(delta)
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
		state = State.AIM
		_t = AIM_TIME
		facing = 1 if player.global_position.x > global_position.x else -1
		Audio.play("charge", -16.0)
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
		Bullet.fire(fx_parent, gun_pos(), aim_dir * BULLET_SPEED, Bullet.Team.ENEMY, 1, self)
		Audio.play("enemy_shot", -8.0)
		Fx.sparks(fx_parent, gun_pos(), aim_dir, 4, RED)
		state = State.COOLDOWN
		_t = COOLDOWN


func _sees_player() -> bool:
	if not is_instance_valid(player):
		return false
	var d := player.global_position - global_position
	if absf(d.x) > SIGHT.x or absf(d.y) > SIGHT.y:
		return false
	var q := PhysicsRayQueryParameters2D.create(gun_pos(), player.global_position + Player.CHEST, 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _draw() -> void:
	var white := _flash > 0.0
	var fill := Color.WHITE if white else DARK
	var s := 1.0 + _spawn_pop * 2.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	# 腿
	var step := sin(_walk_phase) * 3.0 if state == State.PATROL else 0.0
	draw_rect(Rect2(-5 + step, -11, 3, 11), RED)
	draw_rect(Rect2(2 - step, -11, 3, 11), RED)
	# 身体与头
	var body := Rect2(-7, -30, 14, 19)
	draw_rect(body, fill)
	draw_rect(body, RED, false, 1.5)
	var head := Rect2(-5, -38, 10, 8)
	draw_rect(head, fill)
	draw_rect(head, RED, false, 1.5)
	draw_rect(Rect2(0 if facing > 0 else -5, -36, 5, 2), Color.WHITE if white else RED)
	# 枪
	var g := Vector2(facing * 6, -21)
	var dir := aim_dir if state == State.AIM else Vector2(facing, 0.25).normalized()
	draw_line(g, g + dir * 9.0, Color(0.55, 0.5, 0.55), 3.0)
	# 瞄准线：越接近开火越亮越粗，锁定后变白
	if state == State.AIM:
		var k := 1.0 - _t / AIM_TIME
		var locked := _t <= LOCK_TIME
		var c := Color(1, 1, 1, 0.9) if locked else Color(1, 0.2, 0.25, 0.25 + 0.5 * k)
		draw_line(g, g + dir * 320.0, c, 1.0 + k * 1.5)
	# 能量盾
	if has_shield():
		var sx := facing * 11.0
		var sc := Color(1, 0.85, 0.85, 0.9) if _shield_flash > 0.0 else Color(1, 0.25, 0.3, 0.35)
		draw_rect(Rect2(sx - 2, -38, 4, 36), sc)
		draw_rect(Rect2(sx - 2, -38, 4, 36), RED, false, 1.0)
		for i in shield_hp:
			draw_rect(Rect2(sx - 1, -34 + i * 6, 2, 4), Color.WHITE)
	draw_set_transform(Vector2.ZERO)
