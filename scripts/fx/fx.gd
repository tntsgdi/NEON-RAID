class_name Fx
## 小型一次性特效。


## 脚下扬尘。dir_x：粒子偏向（-1 左 / 0 两边 / 1 右）
static func dust(parent: Node, pos: Vector2, dir_x: float, amount: int) -> void:
	if parent == null:
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = Vector2(dir_x, -1.0).normalized()
	p.spread = 55.0 if dir_x != 0.0 else 80.0
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 70.0
	p.gravity = Vector2(0, 120)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(0.5, 0.56, 0.64, 0.85)
	p.position = pos + Vector2(0, -1)
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
