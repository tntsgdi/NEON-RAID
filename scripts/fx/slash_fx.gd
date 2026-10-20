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
	# 像素月牙（逐帧感：按 30 帧/秒跳格）。外缘一圈最亮（白 / 亮青），向内渐暗，内侧随时间被"吃掉"
	var step := floorf(_t * 30.0) / 30.0
	var k := clampf(1.0 - step / life, 0.0, 1.0)
	var outer := reach
	var inner := reach * lerpf(0.55, 0.92, 1.0 - k)
	var lo := minf(a0, a1)
	var hi := maxf(a0, a1)
	var r := int(ceil(outer)) + 1
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var d := Vector2(x + 0.5, y + 0.5)
			var dist := d.length()
			if dist > outer or dist < inner:
				continue
			var ang := d.angle()
			# 角度落在弧内（处理跨 ±PI）
			var inside := false
			for off in [-TAU, 0.0, TAU]:
				if ang + off >= lo and ang + off <= hi:
					inside = true
			if not inside:
				continue
			var t := (dist - inner) / maxf(outer - inner, 0.001)   # 0 内缘 → 1 外缘
			var col: Color
			if t > 0.82:
				col = PixelFx.WHITE if heavy or k > 0.6 else PixelFx.CYAN[3]
			elif t > 0.55:
				col = PixelFx.CYAN[3] if heavy else PixelFx.CYAN[2]
			elif t > 0.25:
				col = PixelFx.CYAN[2] if heavy else PixelFx.CYAN[1]
			else:
				# 内缘抖动：棋盘格去掉一半像素
				if (x + y) % 2 != 0:
					continue
				col = PixelFx.CYAN[1]
			draw_rect(Rect2(x, y, 1, 1), Color(col, 0.35 + 0.65 * k))
