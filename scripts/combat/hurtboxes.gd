class_name Hurtboxes
extends Node2D
## 精确受击框：每个部位（头 / 身 / 腿）一个 Area2D + 矩形 CollisionShape2D，每帧跟着骨架摆到位。
## 刀的判定直接拿这些物理形状和"刀光扫过的扇形"求交（Shape2D.collide，同一帧算完、结果确定），
## 不等 area_entered 信号——信号要晚一帧，高速刀光会漏判。
## F6 打开调试显示：头黄、身红、腿蓝，刚挥过的刀光扇形是青色。

const LAYER := 1 << 7
## 部位优先级：刀光同时扫到几块时按这个顺序算
const ORDER := ["head", "body", "legs"]
const COLORS := {"head": Color(1.6, 1.4, 0.2), "body": Color(1.6, 0.3, 0.3), "legs": Color(0.3, 0.7, 1.6)}

static var show_debug := false
## 最近一次挥刀的扇形（世界坐标），调试显示 0.2 秒
static var last_sweep: Array = []
static var last_sweep_time := -10.0

var parts := {}


func _ready() -> void:
	top_level = true
	z_index = 60


## r 是世界坐标的矩形
func set_part(part: String, r: Rect2) -> void:
	if not parts.has(part):
		var area := Area2D.new()
		area.monitoring = false
		area.monitorable = true
		area.collision_layer = LAYER
		area.collision_mask = 0
		var shape := RectangleShape2D.new()
		var cs := CollisionShape2D.new()
		cs.shape = shape
		area.add_child(cs)
		add_child(area)
		parts[part] = [area, shape]
	var p: Array = parts[part]
	p[0].global_position = r.get_center()
	p[1].size = Vector2(maxf(r.size.x, 1.0), maxf(r.size.y, 1.0))


## [[部位名, 形状, 形状的世界变换], ...]
func part_list() -> Array:
	var out := []
	for k in ORDER:
		if parts.has(k):
			out.append([k, parts[k][1], Transform2D(0.0, parts[k][0].global_position)])
	return out


## 刀光扇形扫到了 n 的哪个部位（"" = 没扫到）。没有受击框的对象用 hurt_rect 当身体。
static func sweep_hit(n: Node, pieces: Array) -> String:
	var list: Array
	var hb = n.get("hurtboxes")
	if hb != null and is_instance_valid(hb) and not hb.parts.is_empty():
		list = hb.part_list()
	else:
		var r: Rect2 = n.hurt_rect()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		list = [["body", shape, Transform2D(0.0, r.get_center())]]
	for p in list:
		for piece in pieces:
			if piece.collide(Transform2D.IDENTITY, p[1], p[2]):
				return p[0]
	return ""


## 刀光扇形：圆心 origin、半径 radius、从 a0 到 a1（世界角度，弧度），切成每块不超过 80° 的凸多边形
static func sector(origin: Vector2, radius: float, a0: float, a1: float) -> Array:
	var pieces := []
	var span := a1 - a0
	var n := maxi(1, int(ceil(absf(span) / deg_to_rad(80.0))))
	var pts_debug := PackedVector2Array([origin])
	for i in n:
		var b0 := a0 + span * i / n
		var b1 := a0 + span * (i + 1) / n
		var poly := PackedVector2Array([origin])
		for j in 5:
			var p := origin + Vector2.from_angle(lerpf(b0, b1, j / 4.0)) * radius
			poly.append(p)
			pts_debug.append(p)
		var shape := ConvexPolygonShape2D.new()
		shape.points = poly
		pieces.append(shape)
	last_sweep = [pts_debug]
	last_sweep_time = Time.get_ticks_msec() / 1000.0
	return pieces


func _process(_delta: float) -> void:
	if show_debug:
		queue_redraw()
	elif parts.size() > 0 and get_meta("drawn", false):
		set_meta("drawn", false)
		queue_redraw()


func _draw() -> void:
	if not show_debug:
		return
	set_meta("drawn", true)
	for k in parts:
		var p: Array = parts[k]
		var size: Vector2 = p[1].size
		draw_rect(Rect2(p[0].global_position - size * 0.5, size), COLORS.get(k, Color.WHITE), false, 1.0)
	if Time.get_ticks_msec() / 1000.0 - last_sweep_time < 0.25:
		for poly in last_sweep:
			var o: PackedVector2Array = poly.duplicate()
			o.append(poly[0])
			draw_polyline(o, Color(0.4, 2.0, 2.2, 0.8), 1.0)
