class_name SecurityDoor
extends StaticBody2D
## 安保门：联合体的门禁只认安保机。被夺的安保机走到门前（40 像素内）门就滑开；
## 别的机体（基础机体、侦察机、重装机）都过不去——冲撞也撞不开。

var rect := Rect2()
var _open := 0.0
var _cs: CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	_cs = CollisionShape2D.new()
	_cs.shape = shape
	_cs.position = rect.size * 0.5
	add_child(_cs)
	add_to_group("security_door")


func _physics_process(delta: float) -> void:
	var body := get_tree().get_first_node_in_group("controlled") as Node2D
	var c := global_position + rect.size * 0.5
	var ok := body is EnemyBot and absf(body.global_position.x - c.x) < 44.0 and absf(body.global_position.y - (global_position.y + rect.size.y)) < 120.0
	var before := _open
	_open = move_toward(_open, 1.0 if ok else 0.0, delta * 4.0)
	_cs.disabled = _open > 0.5
	if before < 0.5 and _open >= 0.5:
		Audio.play("ui_open", -6.0, 0.7)
	queue_redraw()


func _draw() -> void:
	var h := rect.size.y * (1.0 - _open)
	draw_rect(Rect2(0, 0, rect.size.x, h), Color(0.12, 0.03, 0.05))
	draw_rect(Rect2(0, 0, rect.size.x, h), Color(1.4, 0.3, 0.35, 0.9), false, 1.0)
	# 门禁灯：红 = 锁着，青 = 认出安保机
	var lamp := Color(0.4, 1.6, 1.9) if _open > 0.0 else Color(2.0, 0.3, 0.35)
	draw_circle(Vector2(rect.size.x * 0.5, -6), 2.5, lamp)
	var y := 4.0
	while y < h - 2.0:
		draw_line(Vector2(2, y), Vector2(rect.size.x - 2, y), Color(1.2, 0.25, 0.3, 0.35), 1.0)
		y += 6.0
