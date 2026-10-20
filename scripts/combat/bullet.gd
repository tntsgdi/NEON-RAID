class_name Bullet
extends Node2D
## 可见的飞行弹。玩家弹青色，敌弹红色，被刀弹回的敌弹变青色、速度翻倍、一发打死射手。
## 每个物理帧按线段检测：先撞墙，再撞目标。

enum Team { PLAYER, ENEMY }

const PLAYER_COLOR := Color(0.6, 2.2, 2.6)
const ENEMY_COLOR := Color(2.8, 0.4, 0.5)

var team := Team.PLAYER
var velocity := Vector2.ZERO
var damage := 1
var shooter: Node
var deflected := false
var life := 2.0
var fx_parent: Node
## 追踪：每帧把速度方向往目标转（三连发异体的蜂群弹）
var homing: Node2D
var turn_rate := 9.0
var _light: PointLight2D


static func fire(parent: Node, pos: Vector2, vel: Vector2, t: Team, dmg: int, from: Node) -> Bullet:
	var b := Bullet.new()
	b.position = pos
	b.velocity = vel
	b.team = t
	b.damage = dmg
	b.shooter = from
	b.fx_parent = parent
	b.z_index = 4
	parent.add_child(b)
	return b


func _ready() -> void:
	add_to_group("enemy_bullets" if team == Team.ENEMY else "player_bullets")
	light_mask = Neon.ACTOR_LIGHT_MASK
	_light = Neon.add_light(self, Neon.RED if team == Team.ENEMY else Neon.CYAN, 0.5, 0.45)


func color() -> Color:
	return ENEMY_COLOR if team == Team.ENEMY else PLAYER_COLOR


## 被刀弹回：转成玩家方，朝射手飞回去
func deflect(by: Node) -> void:
	if deflected or team != Team.ENEMY:
		return
	deflected = true
	remove_from_group("enemy_bullets")
	add_to_group("player_bullets")
	team = Team.PLAYER
	var speed := velocity.length() * 2.0
	if is_instance_valid(shooter) and shooter.has_method("alive") and shooter.alive():
		velocity = (shooter.center() - global_position).normalized() * speed
	else:
		velocity = -velocity.normalized() * speed
	damage = 99
	life = 2.0
	shooter = by
	_light.color = Neon.CYAN
	queue_redraw()


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if is_instance_valid(homing) and (not homing.has_method("alive") or homing.alive()):
		var want: Vector2 = (homing.hurt_rect().get_center() - global_position).normalized()
		velocity = velocity.rotated(clampf(velocity.angle_to(want), -turn_rate * delta, turn_rate * delta))
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters2D.create(from, to, 1)
	var wall := get_world_2d().direct_space_state.intersect_ray(q)
	var end: Vector2 = to if wall.is_empty() else wall.position
	if _hit_targets(from, end):
		return
	global_position = end
	if not wall.is_empty():
		Fx.sparks(fx_parent, end, -velocity.normalized(), 4, color())
		queue_free()


func _hit_targets(from: Vector2, to: Vector2) -> bool:
	if team == Team.PLAYER:
		for n in get_tree().get_nodes_in_group("hittable"):
			if n == shooter or (n.has_method("alive") and not n.alive()):
				continue
			if _segment_hits(from, to, n.hurt_rect().grow(2.0)):
				var r: int = n.take_hit(velocity.normalized(), damage, "bullet")
				if r == 0:
					continue
				var at: Vector2 = n.hurt_rect().get_center().lerp(to, 0.5)
				if r == 2:
					Fx.sparks(fx_parent, at, -velocity.normalized(), 6, Color(1, 0.5, 0.5))
					Audio.play("shield_block", -8.0)
				else:
					Fx.sparks(fx_parent, at, velocity.normalized(), 7, PLAYER_COLOR)
					Audio.play("hit", -8.0)
				queue_free()
				return true
	else:
		for p in get_tree().get_nodes_in_group("controlled"):
			if _segment_hits(from, to, p.hurt_rect()):
				if p.take_bullet(self):
					queue_free()
					return true
	return false


static func _segment_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var steps := maxi(1, int(a.distance_to(b) / 3.0))
	for i in steps + 1:
		if r.has_point(a.lerp(b, float(i) / steps)):
			return true
	return false


func _draw() -> void:
	var dir := velocity.normalized()
	var length := 14.0 if team == Team.PLAYER else 8.0
	if deflected:
		length = 20.0
	# 像素电磁弹：2 像素宽的尾迹（暗阶 → 亮阶），弹头 2×2 白芯；每 2 帧闪一下
	var ramp: Array = PixelFx.CYAN if (team == Team.PLAYER or deflected) else PixelFx.RED
	var flick := int(life * 30.0) % 2 == 0
	PixelFx.line(self, -dir * length, -dir * length * 0.5, ramp[1], 1)
	PixelFx.line(self, -dir * length * 0.5, Vector2.ZERO, ramp[2], 2)
	draw_rect(Rect2(Vector2(-1, -1), Vector2(2, 2)), ramp[3] if flick else PixelFx.WHITE)
