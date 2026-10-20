class_name BladeTrail
extends Node2D
## 刀光拖尾：每个物理帧记下刀身的根部和刀尖，画成一条迅速消失的光带。
## 挂在世界根节点下，用世界坐标。

const LIFE := 0.11

var heavy := false
var _pairs: Array = []   # [根部, 刀尖, 年龄]


func add(base: Vector2, tip: Vector2) -> void:
	_pairs.append([base, tip, 0.0])


func _process(delta: float) -> void:
	for p in _pairs:
		p[2] += delta
	while not _pairs.is_empty() and _pairs[0][2] >= LIFE:
		_pairs.pop_front()
	queue_redraw()


func _draw() -> void:
	for i in range(1, _pairs.size()):
		var a: Array = _pairs[i - 1]
		var b: Array = _pairs[i]
		var k: float = 1.0 - b[2] / LIFE
		var glow := Color(0.35, 0.95, 1.0, 0.18 * k)
		var core := Color(0.85, 1.0, 1.0, 0.7 * k) if heavy else Color(0.75, 1.0, 1.0, 0.55 * k)
		# 只在刀身外半段画拖尾，刀尖那一截最亮
		var root_a: Vector2 = a[0].lerp(a[1], 0.45)
		var root_b: Vector2 = b[0].lerp(b[1], 0.45)
		_quad(root_a, a[1], b[1], root_b, glow)
		var mid_a: Vector2 = a[0].lerp(a[1], 0.75)
		var mid_b: Vector2 = b[0].lerp(b[1], 0.75)
		_quad(mid_a, a[1], b[1], mid_b, core)
		draw_line(a[1], b[1], Color(1.6, 2.6, 2.8, k), 1.5, true)


## 直接按两个三角形画，刀光扫过时四边形可能自相交，不能走多边形三角剖分
func _quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, c: Color) -> void:
	draw_primitive(PackedVector2Array([p0, p1, p2]), PackedColorArray([c, c, c]), PackedVector2Array())
	draw_primitive(PackedVector2Array([p0, p2, p3]), PackedColorArray([c, c, c]), PackedVector2Array())
