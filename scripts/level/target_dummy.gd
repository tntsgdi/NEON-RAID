class_name TargetDummy
extends Node2D
## 挥刀靶桩（M1 只做受击闪白和抖动）。红色 = 敌方标识。

const SIZE := Vector2(16, 34)
const RED := Color(0.86, 0.2, 0.25)

var hits := 0
var _flash := 0.0
var _shake := 0.0
var _knock := 1.0


func _ready() -> void:
	add_to_group("hittable")


func hurt_rect() -> Rect2:
	return Rect2(global_position + Vector2(-SIZE.x * 0.5, -SIZE.y), SIZE)


func take_hit(dir: Vector2, power: int) -> void:
	hits += 1
	_flash = 0.07
	_shake = 2.5 * power
	_knock = signf(dir.x) if dir.x != 0.0 else 1.0


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_shake = move_toward(_shake, 0.0, 25.0 * delta)
	queue_redraw()


func _draw() -> void:
	var off := Vector2(_shake * _knock, 0).round()
	draw_rect(Rect2(-2, -8, 4, 8), Color(0.25, 0.28, 0.33))
	var body := Rect2(Vector2(-SIZE.x * 0.5, -SIZE.y) + off, Vector2(SIZE.x, SIZE.y - 8))
	draw_rect(body, Color.WHITE if _flash > 0.0 else Color(0.2, 0.06, 0.08))
	draw_rect(body, RED, false, 1.0)
	draw_rect(Rect2(Vector2(-3, -SIZE.y + 6) + off, Vector2(6, 3)), RED)
