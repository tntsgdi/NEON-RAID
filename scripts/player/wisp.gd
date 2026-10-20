class_name Wisp
extends CharacterBody2D
## 意识光球：被夺来的机体被打坏时弹出来。1.5 秒内可以飞向附近任意机体（按 E 投射，或直接碰到它）；
## 时间到还没投出去，就在检查点用基础机体重来。不会被打中。

signal expired

const LIFE := 1.5
## 过载弹出的光球：2.5 秒找壳，超时自动飞回本体
const BURNOUT_LIFE := 2.5
const SPEED := 420.0

var input: PlayerInput
var lock_target: Node2D
var life := LIFE
var facing := 1
## 过载弹出时设为本体：超时后自动飞回它（不回检查点）
var home: Node2D
var _homing := false
var _trail: Array = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CircleShape2D.new()
	shape.radius = 4.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	add_to_group("controlled")
	light_mask = Neon.ACTOR_LIGHT_MASK
	Neon.add_light(self, Neon.CYAN, 0.6, 1.2)


func alive() -> bool:
	return life > 0.0


func center() -> Vector2:
	return global_position


func hurt_rect() -> Rect2:
	return Rect2(global_position - Vector2(4, 4), Vector2(8, 8))


func invulnerable() -> bool:
	return true


func take_bullet(_b: Node) -> bool:
	return false


func melee_hit(_dir: Vector2, _dmg: int) -> void:
	pass


func take_control(inp: PlayerInput, vel: Vector2) -> void:
	input = inp
	velocity = vel


func release_control() -> void:
	remove_from_group("controlled")
	queue_free()


func _physics_process(delta: float) -> void:
	if _homing:
		# 飞回本体：不受输入控制，穿墙直飞，碰到本体就回去
		if not is_instance_valid(home):
			expired.emit()
			queue_free()
			return
		var to: Vector2 = home.center() - global_position
		velocity = to.normalized() * minf(SPEED * 2.2, to.length() / maxf(delta, 0.001))
		global_position += velocity * delta
		if to.length() < 14.0:
			get_tree().call_group("consciousness", "return_home", self)
		_trail_step()
		return
	life -= delta  # 按游戏时间算（慢动作里也慢）
	if life <= 0.0:
		if is_instance_valid(home):
			_homing = true
			Audio.play("possess", -8.0, 0.7)
			return
		remove_from_group("controlled")
		expired.emit()
		queue_free()
		return
	input.poll(self)
	var m := input.move
	velocity = velocity.move_toward(m.normalized() * SPEED if m.length() > 0.1 else Vector2.ZERO, 2400.0 * delta)
	if absf(velocity.x) > 10.0:
		facing = 1 if velocity.x > 0.0 else -1
	move_and_slide()
	_trail_step()


func _trail_step() -> void:
	_trail.append(global_position)
	if _trail.size() > 10:
		_trail.pop_front()
	queue_redraw()


func _draw() -> void:
	var k := clampf(life / (BURNOUT_LIFE if home != null else LIFE), 0.0, 1.0)
	for i in range(1, _trail.size()):
		var a: Vector2 = _trail[i - 1] - global_position
		var b: Vector2 = _trail[i] - global_position
		draw_line(a, b, Color(0.5, 1.8, 2.1, 0.15 + 0.06 * i), 1.0 + 0.4 * i, true)
	draw_circle(Vector2.ZERO, 6.0, Color(0.3, 1.2, 1.4, 0.25))
	draw_circle(Vector2.ZERO, 3.0, Neon.CYAN_HOT)
	# 剩余时间：一圈逐渐缩短的弧
	draw_arc(Vector2.ZERO, 9.0, -PI * 0.5, -PI * 0.5 + TAU * k, 24, Color(0.6, 1.6, 1.9, 0.8), 1.5, true)
