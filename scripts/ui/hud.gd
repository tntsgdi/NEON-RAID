class_name Hud
extends Control
## 灰盒 HUD：区段名、计时、速度、操作提示。坐标按 640×360 基准，渲染是清晰的。

var _section: Label
var _time: Label
var _speed: Label
var _hint: Label
var _finish: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_section = _label(Vector2(8, 6), 10, HORIZONTAL_ALIGNMENT_LEFT)
	_time = _label(Vector2(8, 20), 9, HORIZONTAL_ALIGNMENT_LEFT)
	_speed = _label(Vector2(432, 6), 8, HORIZONTAL_ALIGNMENT_RIGHT)
	_hint = _label(Vector2(8, 344), 7, HORIZONTAL_ALIGNMENT_LEFT)
	_hint.size.x = 624
	_finish = _label(Vector2(120, 150), 20, HORIZONTAL_ALIGNMENT_CENTER)
	_finish.size.x = 400


func _label(pos: Vector2, font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = pos
	l.size = Vector2(200, font_size + 4)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	add_child(l)
	return l


func refresh(section_key: String, run_time: float, best: float, speed: float, finished: bool, mode_key: String) -> void:
	_section.text = tr(section_key)
	_time.text = tr("HUD_TIME") % _fmt(run_time)
	var right := tr("HUD_SPEED") % int(round(speed)) + "\n" + tr(mode_key)
	if best >= 0.0:
		right += "\n" + tr("HUD_BEST") % _fmt(best)
	_speed.text = right
	_speed.size.y = 40
	_hint.text = tr("HUD_HINT")
	_finish.visible = finished
	_finish.text = tr("HUD_FINISH") % _fmt(run_time)


static func _fmt(t: float) -> String:
	var m := int(t / 60.0)
	return "%02d:%05.2f" % [m, t - m * 60.0]
