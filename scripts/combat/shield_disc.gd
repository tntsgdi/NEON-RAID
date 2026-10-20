class_name ShieldDisc
extends Node2D
## 盾兵异体：晶化塔盾被掷出去回旋——0.3 秒飞出去，再飞回主人手里；一路打穿敌人（每段每个敌人一次，伤害 2）。
## 飞行中盾面翻转着转（像素贴图交替镜像），身后留青色拖尾。

const OUT_TIME := 0.3
const SPEED := 620.0

var owner_bot: Node2D
var dir := Vector2.RIGHT
var _t := 0.0
var _back := false
var _hit := {}
var _trail: Array[Vector2] = []
var _part: PixelPart


func _ready() -> void:
	z_index = 6
	top_level = true
	_part = PixelPart.get_part("res://assets/sprites/trooper/shield_p")
	Audio.play("dash", -4.0, 1.3)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(owner_bot):
		queue_free()
		return
	_t += delta
	if not _back:
		global_position += dir * SPEED * delta
		if _t >= OUT_TIME or _blocked(dir * 6.0):
			_back = true
			_hit.clear()
	else:
		var home: Vector2 = owner_bot.center()
		var to := home - global_position
		global_position += to.normalized() * minf(SPEED * 1.15 * delta, to.length())
		if to.length() < 10.0:
			owner_bot.catch_shield()
			queue_free()
			return
	for n in get_tree().get_nodes_in_group("hittable"):
		if _hit.has(n) or n == owner_bot or (n.has_method("alive") and not n.alive()):
			continue
		if n.hurt_rect().grow(5.0).has_point(global_position):
			_hit[n] = true
			n.take_hit(dir if not _back else -dir, 2, "rail")
			Fx.sparks(get_parent(), global_position, dir, 10, Color(1.0, 2.2, 2.4))
			Audio.play("hit_heavy", -4.0, 1.2)
			TimeFx.hitstop(0.03)
	_trail.append(global_position)
	if _trail.size() > 8:
		_trail.pop_front()
	queue_redraw()


func _blocked(off: Vector2) -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = global_position + off
	q.collision_mask = 1
	return not get_world_2d().direct_space_state.intersect_point(q).is_empty()


func _draw() -> void:
	for i in range(1, _trail.size()):
		var k := float(i) / _trail.size()
		PixelFx.line(self, _trail[i - 1] - global_position, _trail[i] - global_position, Color(PixelFx.CYAN[2], 0.2 + 0.5 * k), 2)
	# 回旋：每 3 帧翻一次面
	var flip := int(_t * 20.0) % 2 == 0
	_part.draw(self, Transform2D.IDENTITY, Vector2(0, 2), 0.0, flip, Color(1.3, 1.4, 1.5))
