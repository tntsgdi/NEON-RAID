class_name Billboard
extends Node2D
## 环境文字：墙上的霓虹广告牌 / 终端，一两句政治讽刺。玩家走近时扫描线把字"打"出来，走远淡掉。

const SHOW_DIST := 150.0

var key := ""
var _shown := 0.0
var _t := 0.0
var _label: Label


func _ready() -> void:
	z_index = -2
	_label = Label.new()
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.text = tr(key)
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color(1.6, 0.6, 1.4))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 2)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size = Vector2(170, 30)
	_label.position = Vector2(-85, -34)
	_label.visible_ratio = 0.0
	add_child(_label)


func _process(delta: float) -> void:
	_t += delta
	var body := get_tree().get_first_node_in_group("controlled") as Node2D
	var near := body != null and body.global_position.distance_to(global_position) < SHOW_DIST
	_shown = move_toward(_shown, 1.0 if near else 0.0, delta * (2.5 if near else 1.2))
	_label.visible_ratio = clampf(_shown * 1.3, 0.0, 1.0)
	# 霓虹接触不良：偶尔闪一下
	var flicker := 0.6 if fmod(_t * 3.7, 5.0) < 0.08 else 1.0
	_label.modulate.a = clampf(_shown * 1.5, 0.0, 1.0) * flicker
	queue_redraw()


func _draw() -> void:
	var a := 0.25 + 0.6 * _shown
	var r := Rect2(-90, -38, 180, 38)
	draw_rect(r, Color(0.06, 0.02, 0.06, 0.7 * a))
	draw_rect(r, Color(1.4, 0.4, 1.2, 0.6 * a), false, 1.0)
	draw_line(Vector2(-60, 0), Vector2(-60, 14), Color(0.3, 0.3, 0.35, a), 2.0)
	draw_line(Vector2(60, 0), Vector2(60, 14), Color(0.3, 0.3, 0.35, a), 2.0)
	if _shown > 0.0 and _shown < 1.0:
		var x := lerpf(r.position.x, r.end.x, _shown)
		draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(2.0, 1.0, 1.8, 1.0 - _shown), 1.5)
