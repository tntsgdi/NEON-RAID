class_name SlashFx
extends Node2D
## 刀光：一段迅速变细、变淡的月牙。

var a0 := 0.0
var a1 := 0.0
var reach := 24.0
var heavy := false
var life := 0.13
var _t := 0.0


## from_deg / to_deg 是面朝右时的局部角度，这里按朝向换成世界角度
static func spawn(parent: Node, pos: Vector2, from_deg: float, to_deg: float, facing: int, reach_px: float, is_heavy: bool) -> void:
	if parent == null:
		return
	var fx := SlashFx.new()
	fx.position = pos
	# 弧最多画 220°：回旋斩画成一整圈会变成一块实心圆盘，把机体盖住
	var span := clampf(to_deg - from_deg, -220.0, 220.0)
	var mid := (from_deg + to_deg) * 0.5
	fx.a0 = _world(mid - span * 0.5, facing)
	fx.a1 = _world(mid + span * 0.5, facing)
	fx.reach = reach_px
	fx.heavy = is_heavy
	fx.life = 0.2 if is_heavy else 0.15
	fx.z_index = 5
	parent.add_child(fx)


static func _world(deg: float, facing: int) -> float:
	var a := deg_to_rad(deg)
	return a if facing == 1 else PI - a


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - _t / life
	var n := 16
	# 细月牙：只占外侧一圈，越淡越细
	var inner := reach * lerpf(0.72, 0.96, 1.0 - k)
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * reach)
	var outer := pts.duplicate()
	for i in range(n, -1, -1):
		pts.append(Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * inner)
	var col := Color(0.45, 0.95, 1.0, 0.3 * k) if not heavy else Color(0.75, 1.0, 1.0, 0.45 * k)
	draw_colored_polygon(pts, col)
	draw_polyline(outer, Color(1.8, 2.6, 2.8, k), 2.0 if heavy else 1.5, true)
