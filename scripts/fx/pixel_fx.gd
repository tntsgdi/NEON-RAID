class_name PixelFx
## 像素特效的公用画法：在世界像素格上一格一格地画（不抗锯齿、位置取整）。
## 特效统一配色（见 design/PIXEL_ART_PLAN.md）：玩家青（刀光、子弹、夺壳）、敌方红（敌弹、敌方受击）、
## 白（命中核心、可夺壳）、暖黄（重装机冲撞火花、尘土里的火星）、灰（尘土、碎屑）。

const CYAN := [Color(0.06, 0.23, 0.27), Color(0.09, 0.44, 0.49), Color(0.17, 0.77, 0.84), Color(0.62, 0.96, 1.0)]
const RED := [Color(0.23, 0.05, 0.08), Color(0.48, 0.09, 0.14), Color(0.84, 0.2, 0.27), Color(1.0, 0.6, 0.64)]
const WHITE := Color(0.95, 0.97, 0.98)


## 一条像素直线（Bresenham），宽度 1 或 2
static func line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, width := 1) -> void:
	a = a.round()
	b = b.round()
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / maxf(n, 1)).round()
		ci.draw_rect(Rect2(p, Vector2(width, width)), col)


## 像素圆环
static func ring(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var n := maxi(12, int(r * 6.0))
	var last := Vector2(INF, INF)
	for i in n:
		var p := (c + Vector2.from_angle(TAU * i / n) * r).round()
		if p != last:
			ci.draw_rect(Rect2(p, Vector2.ONE), col)
			last = p


## 像素十字星（闪光）：中心白点 + 四个方向的短刺，size 决定刺长
static func star(ci: CanvasItem, c: Vector2, size: int, col: Color) -> void:
	c = c.round()
	ci.draw_rect(Rect2(c - Vector2(1, 1), Vector2(3, 3)), col)
	ci.draw_rect(Rect2(c, Vector2.ONE), WHITE)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		for k in range(2, size + 2):
			var a := 1.0 - float(k) / (size + 2)
			ci.draw_rect(Rect2(c + d * k, Vector2.ONE), Color(col, a))
