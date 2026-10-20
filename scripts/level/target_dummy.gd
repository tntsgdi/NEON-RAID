class_name TargetDummy
extends Node2D
## 训练机（灰盒，红色 = 敌方）。被打会击退、摇晃、闪白冒火花；打满 HP 就碎掉，过一会儿重生。

signal broken(at: Vector2)

const SIZE := Vector2(16, 30)
const RED := Color(0.9, 0.2, 0.26)
const MAX_HP := 6
const RESPAWN := 1.4

var hits := 0
var hp := MAX_HP
var fx_parent: Node

var _flash := 0.0
var _off := 0.0       # 横向位移（弹簧）
var _off_v := 0.0
var _tilt := 0.0      # 倾斜（弹簧，弧度）
var _tilt_v := 0.0
var _dead := 0.0
var _pop := 0.0


func _ready() -> void:
	add_to_group("hittable")
	if fx_parent == null:
		fx_parent = get_parent()


func alive() -> bool:
	return _dead <= 0.0


func hurt_rect() -> Rect2:
	return Rect2(global_position + Vector2(-SIZE.x * 0.5 + _off, -SIZE.y - 6), SIZE)


func center() -> Vector2:
	return hurt_rect().get_center()


## 返回 0 = 没打到，1 = 打到
func take_hit(dir: Vector2, power: int, _kind := "slash") -> int:
	if not alive():
		return 0
	hits += 1
	hp -= power
	_flash = 0.08
	var sx := signf(dir.x) if absf(dir.x) > 0.1 else 1.0
	_off_v += sx * (140.0 + 90.0 * power)
	_tilt_v += sx * (9.0 + 6.0 * power)
	if hp <= 0:
		_break(dir)
	return 1


func _break(dir: Vector2) -> void:
	_dead = RESPAWN
	Fx.debris(fx_parent, center(), dir, 18, RED)
	Fx.debris(fx_parent, center(), dir, 10, Color(0.3, 0.33, 0.4))
	Fx.sparks(fx_parent, center(), dir, 14, Color(1.0, 0.6, 0.5))
	Audio.play("break", -3.0)
	broken.emit(center())


func _process(delta: float) -> void:
	if _dead > 0.0:
		_dead -= delta
		if _dead <= 0.0:
			hp = MAX_HP
			_off = 0.0
			_off_v = 0.0
			_tilt = 0.0
			_tilt_v = 0.0
			_pop = 0.2
		queue_redraw()
		return
	_flash = maxf(_flash - delta, 0.0)
	_pop = maxf(_pop - delta, 0.0)
	# 阻尼弹簧：被打退后晃回原位
	_off_v += (-_off * 180.0 - _off_v * 14.0) * delta
	_off += _off_v * delta
	_tilt_v += (-_tilt * 260.0 - _tilt_v * 9.0) * delta
	_tilt += _tilt_v * delta
	queue_redraw()


func _draw() -> void:
	if _dead > 0.0:
		draw_rect(Rect2(-6, -4, 12, 4), Color(0.25, 0.28, 0.33))
		return
	draw_rect(Rect2(-6, -4, 12, 4), Color(0.25, 0.28, 0.33))  # 底座
	draw_set_transform(Vector2(_off, -4), _tilt, Vector2.ONE * (1.0 + _pop))
	draw_line(Vector2(0, 0), Vector2(0, -6), Color(0.35, 0.38, 0.45), 2.0)
	var white := _flash > 0.0
	var body := Rect2(-SIZE.x * 0.5, -SIZE.y - 2, SIZE.x, SIZE.y - 6)
	draw_rect(body, Color.WHITE if white else Color(0.22, 0.06, 0.09))
	draw_rect(body, RED, false, 1.5)
	var head := Rect2(-5, -SIZE.y - 10, 10, 8)
	draw_rect(head, Color.WHITE if white else Color(0.22, 0.06, 0.09))
	draw_rect(head, RED, false, 1.5)
	draw_rect(Rect2(-3, -SIZE.y - 7, 6, 2), Color.WHITE if white else RED)
	# HP 刻度
	for i in MAX_HP:
		var c := RED if i < hp else Color(0.3, 0.1, 0.12)
		draw_rect(Rect2(-7 + i * 2.5, -SIZE.y + 4, 1.5, 3), c)
	draw_set_transform(Vector2.ZERO)
