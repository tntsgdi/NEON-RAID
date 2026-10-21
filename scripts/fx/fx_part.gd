class_name FxPart
extends RigidBody2D
## 敌人碎裂后的零件：带物理，飞出去、转着、落地弹跳，2.5 秒后淡出消失。

var size := Vector2(8, 8)
var fill := Color.BLACK
var edge := Color.RED
var _life := 2.5
## 像素部件（敌人自己的贴图）；为空时画方块
var sprite: PixelPart
var _age := 0.0


static func spawn(parent: Node, pos: Vector2, _shape: String, part_size: Vector2, vel: Vector2, fill_color: Color, edge_color: Color) -> void:
	if parent == null:
		return
	var p := FxPart.new()
	p.size = part_size
	p.fill = fill_color
	p.edge = edge_color
	p.position = pos
	p.collision_layer = 0
	p.collision_mask = 1
	p.gravity_scale = 1.6
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.35
	mat.friction = 0.6
	p.physics_material_override = mat
	var shape := RectangleShape2D.new()
	shape.size = part_size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	p.add_child(cs)
	parent.add_child.call_deferred(p)
	p.linear_velocity = vel + Vector2(randf_range(-40, 40), randf_range(-40, 0))
	p.angular_velocity = randf_range(-14.0, 14.0)


## 击毁时四散的像素零件：path 是 assets/sprites 下的部件（"trooper/head" 之类）
static func spawn_sprite(parent: Node, pos: Vector2, path: String, vel: Vector2, hit_size := Vector2(8, 8)) -> void:
	if parent == null:
		return
	var p := FxPart.new()
	p.sprite = PixelPart.get_part("res://assets/sprites/" + path)
	p.size = hit_size
	p._life = 3.2
	p.position = pos
	p.collision_layer = 0
	p.collision_mask = 1
	p.gravity_scale = 1.7
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.4
	mat.friction = 0.7
	p.physics_material_override = mat
	var shape := RectangleShape2D.new()
	shape.size = hit_size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	p.add_child(cs)
	p.z_index = 4
	parent.add_child.call_deferred(p)
	p.linear_velocity = vel + Vector2(randf_range(-60, 60), randf_range(-80, 0))
	p.angular_velocity = randf_range(-16.0, 16.0)


func _process(delta: float) -> void:
	_age += delta
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	modulate.a = clampf(_life / 0.6, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if sprite != null:
		# 抵消刚体自身的旋转，在不转的像素格上画最接近的预旋转帧；头 0.35 秒烧红，再冷却回本色
		var hot := clampf(1.0 - _age / 0.35, 0.0, 1.0)
		sprite.draw(self, Transform2D(-rotation, Vector2.ZERO), Vector2.ZERO, rotation, false, Color(1, 1, 1).lerp(Color(2.6, 1.1, 0.6), hot))
		return
	var r := Rect2(-size * 0.5, size)
	draw_rect(r, fill)
	draw_rect(r, edge, false, 1.0)
