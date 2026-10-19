class_name Fx
## 小型一次性特效。


## 脚下扬尘。dir_x：粒子偏向（-1 左 / 0 两边 / 1 右）
static func dust(parent: Node, pos: Vector2, dir_x: float, amount: int) -> void:
	if parent == null:
		return
	var p := _burst(parent, pos + Vector2(0, -1), amount, 0.35)
	p.direction = Vector2(dir_x, -1.0).normalized()
	p.spread = 55.0 if dir_x != 0.0 else 80.0
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 75.0
	p.gravity = Vector2(0, 120)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color = Color(0.5, 0.56, 0.64, 0.85)


## 命中火花：沿 dir 方向喷出的亮线
static func sparks(parent: Node, pos: Vector2, dir: Vector2, amount: int, color := Color(0.85, 1.0, 1.0)) -> void:
	if parent == null:
		return
	var p := _burst(parent, pos, amount, 0.22)
	p.direction = dir.normalized()
	p.spread = 40.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 340.0
	p.damping_min = 300.0
	p.damping_max = 500.0
	p.gravity = Vector2(0, 300)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp


## 碎片：打碎训练机时的方块碎片
static func debris(parent: Node, pos: Vector2, dir: Vector2, amount: int, color: Color) -> void:
	if parent == null:
		return
	var p := _burst(parent, pos, amount, 0.9)
	p.direction = (dir.normalized() + Vector2(0, -1.2)).normalized()
	p.spread = 70.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 700)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(6, 12)


static func _burst(parent: Node, pos: Vector2, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.explosiveness = 1.0
	p.position = pos
	p.z_index = 6
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p
