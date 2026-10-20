class_name SoulFlow
extends Node2D
## 夺壳的意识光流：一团光沿弧线从旧机体流进新机体（约 0.2 秒真实时间，期间时间放慢），
## 身后拖着越来越细的光尾；到达时一闪 + 光环，新机体"醒来"（目镜由暗到亮、身体一抖站稳）。
## 镜头在光流飞行期间跟着它走。

const DURATION := 0.2

var from := Vector2.ZERO
var target: Node2D
var _to := Vector2.ZERO
var _ctrl := Vector2.ZERO
var _t := 0.0
var _trail: Array[Vector2] = []
var done := false


static func spawn(parent: Node, start: Vector2, tgt: Node2D) -> SoulFlow:
	var f := SoulFlow.new()
	f.from = start
	f.target = tgt
	f.z_index = 8
	f.top_level = true
	parent.add_child(f)
	f._to = tgt.center()
	# 弧线：控制点在两点中间、往上抬起距离的 35%（光是"跃"过去的）
	var mid := (start + f._to) * 0.5
	var d := start.distance_to(f._to)
	f._ctrl = mid + Vector2(0, -maxf(d * 0.35, 18.0))
	f.global_position = start
	return f


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.0001)
	_t += real
	if is_instance_valid(target):
		_to = target.center()
	if done:
		if _trail.size() > 1:
			_trail.remove_at(0)
			_trail.remove_at(0) if _trail.size() > 1 else null
		else:
			queue_free()
		queue_redraw()
		return
	var k := clampf(_t / DURATION, 0.0, 1.0)
	# 先慢后快（ease-in）：从旧壳里"抽"出来，再冲进新壳
	var e := k * k * (3.0 - 2.0 * k)
	var p := from.lerp(_ctrl, e).lerp(_ctrl.lerp(_to, e), e)
	global_position = p
	_trail.append(p)
	if _trail.size() > 14:
		_trail.remove_at(0)
	if k >= 1.0:
		done = true
		var parent := get_parent()
		Fx.flash(parent, _to, Neon.WHITE_HOT, 18.0)
		Fx.ring(parent, _to, 24.0)
		if is_instance_valid(target) and target.has_method("wake"):
			target.wake()
	queue_redraw()


func _draw() -> void:
	# 像素意识流：拖尾是一串 1–2 像素的亮点（越新越亮越粗），头部是一个 3×3 的光团 + 白芯
	var n := _trail.size()
	for i in range(1, n):
		var k := float(i) / n
		var col: Color = PixelFx.CYAN[1].lerp(PixelFx.CYAN[3], k)
		PixelFx.line(self, to_local(_trail[i - 1]), to_local(_trail[i]), Color(col, 0.4 + 0.6 * k), 2 if k > 0.6 else 1)
	if not done:
		draw_rect(Rect2(-2, -2, 5, 5), Color(PixelFx.CYAN[2], 0.6))
		draw_rect(Rect2(-1, -1, 3, 3), PixelFx.CYAN[3])
		draw_rect(Rect2(0, 0, 1, 1), Color(2.4, 2.6, 2.7))
