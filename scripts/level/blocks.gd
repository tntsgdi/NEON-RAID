class_name Blocks
## 灰盒实体：碰撞 + 绘制。实体要和背景一眼分开：亮填充 + 四边描边；高墙面上有横向抓痕（能蹬）。

const FILL := Color(0.19, 0.23, 0.3)
const EDGE := Color(0.46, 0.56, 0.7)
const TOP := Color(0.75, 0.84, 0.95)
const GRIP := Color(0.36, 0.44, 0.56)


static func build(parent: Node, rects: Array) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	parent.add_child(body)
	for r in rects:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = r.get_center()
		body.add_child(cs)


static func draw(ci: CanvasItem, rects: Array) -> void:
	for r in rects:
		ci.draw_rect(r, FILL)
		ci.draw_rect(r, EDGE, false, 1.0)
		ci.draw_line(r.position + Vector2(0, 0.5), Vector2(r.end.x, r.position.y + 0.5), TOP, 2.0)
		if r.size.y > 60.0:
			var y: float = r.position.y + 10.0
			while y < minf(r.end.y, 0.0) - 6.0:
				ci.draw_line(Vector2(r.position.x, y), Vector2(r.position.x + 5, y), GRIP, 1.0)
				ci.draw_line(Vector2(r.end.x - 5, y), Vector2(r.end.x, y), GRIP, 1.0)
				y += 14.0
