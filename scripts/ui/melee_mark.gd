class_name MeleeMark
extends Node2D
## 刀的锁定标记：这一刀会冲向谁，就在谁头顶挂一把朝下的小刀。
## 换目标时滑过去；出刀突进的一瞬间亮一下；没有目标时淡出。

var target: Node2D
var _pos := Vector2.ZERO
var _shown := 0.0
var _t := 0.0
var _pulse := 0.0


func _ready() -> void:
	top_level = true
	z_index = 40


## 出刀突进：标记闪白一下
func pulse() -> void:
	_pulse = 1.0


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.0001)
	_t += real
	_pulse = maxf(_pulse - real / 0.2, 0.0)
	if is_instance_valid(target):
		var r: Rect2 = target.hurt_rect()
		var want := Vector2(r.get_center().x, r.position.y - 10.0)
		_pos = _pos.lerp(want, 1.0 - exp(-22.0 * real)) if _shown > 0.05 else want
		_shown = minf(_shown + real * 7.0, 1.0)
	else:
		_shown = maxf(_shown - real * 7.0, 0.0)
	queue_redraw()


func _draw() -> void:
	if _shown <= 0.0:
		return
	var a := _shown
	var p := _pos + Vector2(0, sin(_t * 6.0) * 1.5 - (1.0 - a) * 6.0)
	var col := Color(0.5, 1.7, 1.9, 0.9 * a).lerp(Color(2.6, 2.8, 2.8, a), _pulse)
	# 朝下的小刀：刀身 + 护手 + 刀尖
	draw_line(p + Vector2(0, -9), p + Vector2(0, -1), col, 2.0, false)
	draw_line(p + Vector2(-3, -6), p + Vector2(3, -6), col, 1.5, false)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-2, -1), p + Vector2(2, -1), p + Vector2(0, 3)]), col)
