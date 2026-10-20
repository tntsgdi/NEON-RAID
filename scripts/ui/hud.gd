class_name Hud
extends Control
## 精密机械 HUD（640×360 基准）：
##   左上 机体模块——切角框、当前机体名、分段血条（掉血时白色残段收缩）、平滑能量条、夺壳就绪灯
##   顶部中间 区段名——换区段时扫描线从左到右"打印"出来，下划线从中间展开
##   右上 计时 / 最佳
##   底部 提示——切角面板从下往上滑入、滑出；屏幕中央 结算卡——冲击式弹出
## 所有动画用不受慢动作影响的真实时间。

const C_LINE := Color(0.35, 0.95, 1.1)
const C_DIM := Color(0.2, 0.45, 0.55, 0.7)
const C_FILL := Color(0.02, 0.04, 0.07, 0.86)
const C_TEXT := Color(0.8, 0.95, 1.0)
const SEG := Vector2(14, 6)
const SEG_SKEW := 3.0
const MOD := Rect2(8, 6, 150, 44)

var _section: Label
var _time: Label
var _speed: Label
var _hint: Label
var _finish: Label
var _overclock: Label
var _shell: Label
var _tip: Label
var _tip_time := 0.0
var _tip_in := 0.0
var _card: Label
var _card_body: Label
var _card_time := 0.0
var _card_age := 0.0
var _hp := 3
var _max_hp := 3
var _energy := 8.0
var _energy_shown := 8.0
var _max_energy := 8.0
## 每个血格掉血后残留的白色碎片（1 → 0）
var _chip: Array[float] = []
## 每个血格回血时的填充进度
var _fill: Array[float] = []
var _section_text := ""
var _wipe := 1.0
var _shell_text := ""
var _shell_wipe := 1.0
var _oc_age := 0.0
var _t := 0.0
## 夺壳冷却剩余比例（1 = 刚夺完）
var possess_k := 0.0
var _hp_k := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shell = _label(MOD.position + Vector2(9, 3), 8, HORIZONTAL_ALIGNMENT_LEFT)
	_shell.size.x = 120
	_section = _label(Vector2(170, 5), 9, HORIZONTAL_ALIGNMENT_CENTER)
	_section.size.x = 300
	_time = _label(Vector2(432, 5), 9, HORIZONTAL_ALIGNMENT_RIGHT)
	_speed = _label(Vector2(432, 18), 8, HORIZONTAL_ALIGNMENT_RIGHT)
	_speed.size.y = 40
	_speed.modulate = Color(1, 1, 1, 0.7)
	_hint = _label(Vector2(8, 344), 7, HORIZONTAL_ALIGNMENT_LEFT)
	_hint.size.x = 624
	_hint.modulate = Color(1, 1, 1, 0.55)
	_tip = _label(Vector2(50, 300), 10, HORIZONTAL_ALIGNMENT_CENTER)
	_tip.size = Vector2(540, 30)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_color_override("font_color", Color(0.88, 1.0, 1.0))
	_tip.visible = false
	_card = _label(Vector2(70, 120), 20, HORIZONTAL_ALIGNMENT_CENTER)
	_card.size = Vector2(500, 26)
	_card.pivot_offset = _card.size * 0.5
	_card.add_theme_color_override("font_color", Color(0.88, 1.0, 1.0))
	_card_body = _label(Vector2(70, 150), 9, HORIZONTAL_ALIGNMENT_CENTER)
	_card_body.size = Vector2(500, 40)
	_card.visible = false
	_card_body.visible = false
	_finish = _label(Vector2(120, 150), 20, HORIZONTAL_ALIGNMENT_CENTER)
	_finish.size.x = 400
	_overclock = _label(Vector2(220, 40), 11, HORIZONTAL_ALIGNMENT_CENTER)
	_overclock.size.x = 200
	_overclock.add_theme_color_override("font_color", Color(0.6, 1.0, 1.0))
	_overclock.visible = false


func _label(pos: Vector2, font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = pos
	l.size = Vector2(200, font_size + 4)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", C_TEXT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	add_child(l)
	return l


func refresh(section_text: String, run_time: float, best: float, speed: float, finished: bool, mode_key: String, debug: bool) -> void:
	if section_text != _section_text:
		_section_text = section_text
		_section.text = section_text
		_wipe = 0.0
	_time.text = tr("HUD_TIME") % _fmt(run_time)
	var right := ""
	if best >= 0.0:
		right = tr("HUD_BEST") % _fmt(best)
	if debug:
		right += "\n" + tr("HUD_SPEED") % int(round(speed)) + "\n" + tr(mode_key)
	_speed.text = right
	_hint.text = tr("HUD_HINT_PAD") if Input.get_connected_joypads().size() > 0 else tr("HUD_HINT")
	_finish.visible = finished and _card_time <= 0.0 and section_text == tr("SEC_7")
	_finish.text = tr("HUD_FINISH") % _fmt(run_time)


## 当前机体的名字（换壳时扫描线重新打印一遍）
func set_shell(text: String) -> void:
	if text == _shell_text:
		return
	_shell_text = text
	_shell.text = text
	_shell_wipe = 0.0


## 屏幕下方的提示：切角面板滑入，显示几秒后滑出
func show_tip(text: String) -> void:
	_tip.text = text
	_tip.visible = true
	if _tip_time <= 0.0:
		_tip_in = 0.0
	_tip_time = 4.5


## 屏幕中央的结算卡（评级、生存结果）：冲击式弹出，几秒后淡出
func show_card(title: String, body: String) -> void:
	_card.text = title
	_card_body.text = body
	_card.visible = true
	_card_body.visible = true
	_card_time = 5.0
	_card_age = 0.0


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.0001)
	_t += real
	_wipe = minf(_wipe + real / 0.35, 1.0)
	_shell_wipe = minf(_shell_wipe + real / 0.3, 1.0)
	_section.visible_ratio = _wipe
	_shell.visible_ratio = _shell_wipe
	for i in _chip.size():
		_chip[i] = maxf(_chip[i] - real / 0.4, 0.0)
		_fill[i] = minf(_fill[i] + real / 0.25, 1.0)
	_energy_shown = lerpf(_energy_shown, _energy, 1.0 - exp(-18.0 * real))
	if _card_time > 0.0:
		_card_time -= real
		_card_age += real
		# 冲击弹出：0.12 秒从 1.3 倍砸到 1.0，带一点回弹
		var k := clampf(_card_age / 0.12, 0.0, 1.0)
		var s := 1.0 + 0.3 * (1.0 - k) * (1.0 - k) - 0.04 * sin(clampf((_card_age - 0.12) / 0.15, 0.0, 1.0) * PI)
		_card.scale = Vector2(s, s)
		var a := clampf(_card_time / 0.8, 0.0, 1.0) * clampf(_card_age / 0.08, 0.0, 1.0)
		_card.modulate.a = a
		_card_body.modulate.a = a * clampf((_card_age - 0.15) / 0.2, 0.0, 1.0)
		_card.visible = _card_time > 0.0
		_card_body.visible = _card.visible
	if _tip_time > 0.0:
		_tip_time -= real
		_tip_in = minf(_tip_in + real / 0.25, 1.0)
		# 进：缓出滑上来；出：最后 0.3 秒滑下去
		var enter := 1.0 - pow(1.0 - _tip_in, 3.0)
		var leave := clampf(_tip_time / 0.3, 0.0, 1.0)
		var vis := minf(enter, leave * leave * (3.0 - 2.0 * leave))
		_tip.position.y = 300.0 + (1.0 - vis) * 22.0
		_tip.modulate.a = vis
		_tip.visible = _tip_time > 0.0
	if _overclock.visible:
		_oc_age += real
		# 超频字样闪烁着亮起（像信号接通），之后稳定呼吸
		_overclock.modulate.a = (1.0 if fmod(_oc_age * 37.0, 1.0) > 0.4 else 0.2) if _oc_age < 0.2 else 0.8 + 0.2 * sin(_t * 8.0)
	queue_redraw()


## 血、射击能量、神经超频提示
func refresh_combat(hp: int, max_hp: int, energy: float, max_energy: float, overclock: bool) -> void:
	if overclock and not _overclock.visible:
		_oc_age = 0.0
	_overclock.visible = overclock
	_overclock.text = tr("HUD_OVERCLOCK")
	if max_hp != _max_hp or _chip.size() != max_hp:
		_max_hp = max_hp
		_chip.resize(max_hp)
		_fill.resize(max_hp)
		_chip.fill(0.0)
		_fill.fill(1.0)
		_hp = hp
	if hp < _hp:
		for i in range(maxi(hp, 0), mini(_hp, _max_hp)):
			_chip[i] = 1.0
	elif hp > _hp:
		for i in range(maxi(_hp, 0), mini(hp, _max_hp)):
			_fill[i] = 0.0
	_hp = hp
	_hp_k = float(hp) / maxf(float(max_hp), 1.0)
	if max_energy != _max_energy:
		_energy_shown = energy
	_energy = energy
	_max_energy = max_energy


## 切角多边形：右上角和左下角各切掉 c 像素
static func _chamfer(r: Rect2, c: float) -> PackedVector2Array:
	return PackedVector2Array([
		r.position, Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		r.end, Vector2(r.position.x + c, r.end.y), Vector2(r.position.x, r.end.y - c),
	])


func _frame(r: Rect2, c: float, line: Color, fill: Color) -> void:
	var pts := _chamfer(r, c)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, line, 1.0)
	# 左上角加粗的定位角标
	draw_line(r.position, r.position + Vector2(10, 0), Color(line, 1.0), 2.0)
	draw_line(r.position, r.position + Vector2(0, 6), Color(line, 1.0), 2.0)


func _draw() -> void:
	_draw_module()
	_draw_section()
	_draw_tip()
	_draw_card()


func _draw_module() -> void:
	var low := _max_hp > 0 and _hp_k <= 0.34
	var line := C_LINE
	if low:
		line = Color(1.4, 0.3, 0.35).lerp(C_LINE, 0.5 + 0.5 * sin(_t * 6.0))
	var r := MOD
	if _max_energy <= 0.0:
		r.size.y = 32
	_frame(r, 7.0, Color(line, 0.55), C_FILL)
	# 机体名前的状态灯：颜色和机体核心灯一致
	var core := StriderRig.core_color(_hp_k, _t) if _max_hp > 0 else Color(1.6, 1.8, 1.9) * (0.6 + 0.4 * sin(_t * 9.0))
	draw_rect(Rect2(r.position + Vector2(4, 6), Vector2(3, 6)), core)
	# 扫描线：打印机体名时那一竖亮线
	if _shell_wipe < 1.0:
		var x := r.position.x + 9 + _shell_wipe * 110.0
		draw_line(Vector2(x, r.position.y + 3), Vector2(x, r.position.y + 14), Color(1.6, 2.0, 2.1, 1.0 - _shell_wipe), 1.5)
	# 夺壳就绪灯（右上）：冷却时是一圈进度，就绪时亮成实心菱形
	var pc := r.position + Vector2(r.size.x - 18, 10)
	var dia := PackedVector2Array([pc + Vector2(0, -4), pc + Vector2(4, 0), pc + Vector2(0, 4), pc + Vector2(-4, 0)])
	if possess_k > 0.0:
		draw_arc(pc, 5.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - possess_k), 16, Color(0.5, 1.3, 1.5, 0.9), 1.5)
		dia.append(dia[0])
		draw_polyline(dia, C_DIM, 1.0)
	else:
		draw_colored_polygon(dia, Color(1.5, 1.7, 1.8, 0.85 + 0.15 * sin(_t * 5.0)))
	var font := ThemeDB.fallback_font
	draw_string(font, pc + Vector2(-17, 3), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, C_DIM if possess_k > 0.0 else C_TEXT)
	# 分段血条：平行四边形格子
	if _max_hp > 0:
		var col := StriderRig.core_color(_hp_k, _t)
		var seg := SEG if _max_hp <= 6 else Vector2(maxf(4.0, 110.0 / _max_hp - 2.0), SEG.y)
		for i in _max_hp:
			var o := r.position + Vector2(9 + i * (seg.x + 2), 19)
			var cell := PackedVector2Array([o + Vector2(SEG_SKEW, 0), o + Vector2(seg.x + SEG_SKEW, 0), o + Vector2(seg.x, seg.y), o + Vector2(0, seg.y)])
			if i < _hp:
				var f: float = _fill[i] if i < _fill.size() else 1.0
				if f >= 1.0:
					draw_colored_polygon(cell, col)
				else:
					# 回血：从左往右刷满
					var w := seg.x * f
					draw_colored_polygon(PackedVector2Array([cell[0], o + Vector2(w + SEG_SKEW, 0), o + Vector2(w, seg.y), cell[3]]), Color(1.8, 2.0, 2.0))
			else:
				draw_colored_polygon(cell, Color(0.06, 0.1, 0.14, 0.9))
				var chip: float = _chip[i] if i < _chip.size() else 0.0
				if chip > 0.0:
					# 刚掉的血格：白色碎片向中间收缩消失，同时往上飘一点
					var c := (cell[0] + cell[2]) * 0.5 - Vector2(0, (1.0 - chip) * 4.0)
					var sh := PackedVector2Array()
					for p in cell:
						sh.append(c + (p - c) * chip)
					draw_colored_polygon(sh, Color(2.2, 2.2, 2.2, chip))
			var outline := cell.duplicate()
			outline.append(cell[0])
			draw_polyline(outline, Color(col, 0.5) if i < _hp else C_DIM, 1.0)
	else:
		draw_string(font, r.position + Vector2(9, 25), tr("HUD_PROJECT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.6, 1.8, 1.9) * (0.6 + 0.4 * sin(_t * 9.0)))
	# 能量条：平滑跟随的细条 + 每格刻度 + 前沿白色亮头
	if _max_energy > 0.0:
		var bar := Rect2(r.position + Vector2(9, 32), Vector2(120, 3))
		draw_rect(bar, Color(0.06, 0.1, 0.14, 0.9))
		var k := clampf(_energy_shown / _max_energy, 0.0, 1.0)
		var full := _energy >= _max_energy - 0.01
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color(0.4, 1.1, 1.3) if full else Color(0.3, 0.75, 0.9))
		if k > 0.01 and not full:
			draw_rect(Rect2(bar.position + Vector2(bar.size.x * k - 1.5, -1), Vector2(1.5, bar.size.y + 2)), Color(2.0, 2.2, 2.2))
		var cells := int(_max_energy)
		for i in range(1, cells):
			var x := bar.position.x + bar.size.x * i / cells
			draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0.02, 0.04, 0.07), 1.0)
		# 满能量时一道高光每两秒扫过一次
		if full:
			var g := fmod(_t * 0.5, 1.0)
			if g < 0.3:
				var gx := bar.position.x + bar.size.x * g / 0.3
				draw_rect(Rect2(Vector2(gx - 3, bar.position.y), Vector2(6, bar.size.y)), Color(1.8, 2.0, 2.0, 0.6))
		draw_string(font, bar.end + Vector2(4, 3), "EN", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, C_DIM)


func _draw_section() -> void:
	if _section_text == "":
		return
	var font := _section.get_theme_font("font")
	var w := font.get_string_size(_section_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var cx := _section.position.x + _section.size.x * 0.5
	var y := _section.position.y + 15.0
	# 下划线从中间展开；两端的小括号跟着走
	var half := (w * 0.5 + 10.0) * (1.0 - pow(1.0 - _wipe, 3.0))
	draw_line(Vector2(cx - half, y), Vector2(cx + half, y), Color(C_LINE, 0.6), 1.0)
	for s in [-1.0, 1.0]:
		var e := Vector2(cx + half * s, y)
		draw_line(e, e - Vector2(0, 4), Color(C_LINE, 0.9), 1.0)
	if _wipe < 1.0:
		var x := cx - w * 0.5 + w * _wipe
		draw_line(Vector2(x, _section.position.y + 1), Vector2(x, y - 1), Color(1.6, 2.0, 2.1, 1.0 - _wipe), 2.0)


func _draw_tip() -> void:
	if not _tip.visible:
		return
	var font := _tip.get_theme_font("font")
	var sz := font.get_multiline_string_size(_tip.text, HORIZONTAL_ALIGNMENT_CENTER, _tip.size.x, 10)
	var w := minf(sz.x + 24.0, 560.0)
	var h := maxf(sz.y + 8.0, 20.0)
	var r := Rect2(Vector2(320.0 - w * 0.5, _tip.position.y - 4.0), Vector2(w, h))
	var a := _tip.modulate.a
	_frame(r, 6.0, Color(C_LINE, 0.5 * a), Color(C_FILL, C_FILL.a * a))


func _draw_card() -> void:
	if not _card.visible:
		return
	var a := _card.modulate.a
	var k := 1.0 - pow(1.0 - clampf(_card_age / 0.25, 0.0, 1.0), 3.0)
	# 上下两道横线从中间向两边展开
	for y in [116.0, 190.0]:
		draw_line(Vector2(320 - 220 * k, y), Vector2(320 + 220 * k, y), Color(C_LINE, 0.7 * a), 1.0)
	draw_rect(Rect2(Vector2(320 - 220 * k, 117), Vector2(440 * k, 72)), Color(C_FILL, 0.5 * a))
	# 冲击闪光：弹出的头 0.1 秒整张卡发白
	if _card_age < 0.1:
		draw_rect(Rect2(Vector2(100, 117), Vector2(440, 72)), Color(1.5, 1.8, 1.9, 0.25 * (1.0 - _card_age / 0.1)))


static func _fmt(t: float) -> String:
	var m := int(t / 60.0)
	return "%02d:%05.2f" % [m, t - m * 60.0]
