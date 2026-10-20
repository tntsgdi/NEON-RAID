class_name Hud
extends Control
## 灰盒 HUD：区段名、计时、速度、操作提示。坐标按 640×360 基准，渲染是清晰的。

var _section: Label
var _time: Label
var _speed: Label
var _hint: Label
var _finish: Label
var _overclock: Label
var _tip: Label
var _tip_time := 0.0
var _card: Label
var _card_body: Label
var _card_time := 0.0
var _hp := 3
var _max_hp := 3
var _energy := 8.0
var _max_energy := 8.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_section = _label(Vector2(8, 6), 10, HORIZONTAL_ALIGNMENT_LEFT)
	_time = _label(Vector2(8, 20), 9, HORIZONTAL_ALIGNMENT_LEFT)
	_speed = _label(Vector2(432, 6), 8, HORIZONTAL_ALIGNMENT_RIGHT)
	_hint = _label(Vector2(8, 342), 8, HORIZONTAL_ALIGNMENT_LEFT)
	_hint.size.x = 624
	_tip = _label(Vector2(40, 290), 11, HORIZONTAL_ALIGNMENT_CENTER)
	_tip.size = Vector2(560, 40)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_color_override("font_color", Color(0.85, 1.0, 1.0))
	_tip.add_theme_constant_override("outline_size", 4)
	_tip.visible = false
	_card = _label(Vector2(70, 110), 20, HORIZONTAL_ALIGNMENT_CENTER)
	_card.size.x = 500
	_card.add_theme_color_override("font_color", Color(0.85, 1.0, 1.0))
	_card_body = _label(Vector2(70, 142), 9, HORIZONTAL_ALIGNMENT_CENTER)
	_card_body.size = Vector2(500, 40)
	_card.visible = false
	_card_body.visible = false
	_finish = _label(Vector2(120, 150), 20, HORIZONTAL_ALIGNMENT_CENTER)
	_finish.size.x = 400
	_overclock = _label(Vector2(220, 40), 12, HORIZONTAL_ALIGNMENT_CENTER)
	_overclock.size.x = 200
	_overclock.add_theme_color_override("font_color", Color(0.6, 1.0, 1.0))


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


func refresh(section_text: String, run_time: float, best: float, speed: float, finished: bool, mode_key: String, debug: bool) -> void:
	_section.text = section_text
	_time.text = tr("HUD_TIME") % _fmt(run_time)
	var right := ""
	if best >= 0.0:
		right = tr("HUD_BEST") % _fmt(best)
	if debug:
		right += "\n" + tr("HUD_SPEED") % int(round(speed)) + "\n" + tr(mode_key)
	_speed.text = right
	_speed.size.y = 40
	_hint.text = tr("HUD_HINT")
	_finish.visible = finished and _card_time <= 0.0 and section_text == tr("SEC_7")
	_finish.text = tr("HUD_FINISH") % _fmt(run_time)


## 屏幕下方的大字提示，显示几秒后淡出
func show_tip(text: String) -> void:
	_tip.text = text
	_tip.visible = true
	_tip_time = 4.5


## 屏幕中央的结算卡（评级、生存结果），几秒后淡出
func show_card(title: String, body: String) -> void:
	_card.text = title
	_card_body.text = body
	_card.visible = true
	_card_body.visible = true
	_card_time = 5.0


func _process(delta: float) -> void:
	if _card_time > 0.0:
		_card_time -= delta / maxf(Engine.time_scale, 0.0001)
		var a := clampf(_card_time / 0.8, 0.0, 1.0)
		_card.modulate.a = a
		_card_body.modulate.a = a
		_card.visible = _card_time > 0.0
		_card_body.visible = _card.visible
	if _tip_time > 0.0:
		_tip_time -= delta / maxf(Engine.time_scale, 0.0001)
		_tip.modulate.a = clampf(_tip_time / 0.6, 0.0, 1.0)
		_tip.visible = _tip_time > 0.0


## 血（青色方块）、射击能量（细条）、神经超频提示
func refresh_combat(hp: int, max_hp: int, energy: float, max_energy: float, overclock: bool) -> void:
	_overclock.visible = overclock
	_overclock.text = tr("HUD_OVERCLOCK")
	if hp != _hp or max_hp != _max_hp or not is_equal_approx(energy, _energy) or not is_equal_approx(max_energy, _max_energy):
		_hp = hp
		_max_hp = max_hp
		_energy = energy
		_max_energy = max_energy
		queue_redraw()


func _draw() -> void:
	for i in _max_hp:
		var r := Rect2(8 + i * 11, 36, 9, 9)
		draw_rect(r, Color(0.3, 1.0, 1.0) if i < _hp else Color(0.1, 0.18, 0.22))
		draw_rect(r, Color(0.6, 0.9, 1.0), false, 1.0)
	var cells := int(_max_energy)
	for i in cells:
		var fill := clampf(_energy - i, 0.0, 1.0)
		var r := Rect2(8 + i * 5, 49, 4, 3)
		draw_rect(r, Color(0.12, 0.2, 0.25))
		draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), Color(0.4, 0.95, 1.0) if fill >= 1.0 else Color(0.25, 0.6, 0.7))


static func _fmt(t: float) -> String:
	var m := int(t / 60.0)
	return "%02d:%05.2f" % [m, t - m * 60.0]
