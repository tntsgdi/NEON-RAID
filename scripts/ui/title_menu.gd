class_name TitleMenu
extends Control
## 标题菜单：开始游戏 / 继续 / 选择区域 / 训练场 / 设置 / 退出。
## 打开时游戏暂停，背后的关卡照样看得见（压暗 + 扫描线）。
## 标题扫描线"打印"出来；菜单项依次从左边滑进来；选中框是弹簧，带一点过冲地滑到选中项。
## W/S 或 ↑/↓ 选择，空格 / J / 回车 确认，Esc 返回；鼠标悬停选择、点击确认。

signal chosen(action: String, arg: int)

const ITEM_H := 22.0
const TOP := 150.0
const LEFT := 64.0

var _page := "main"
var _items: Array = []      # [文字, action, arg, 可用]
var _sel := 0
var _labels: Array[Label] = []
var _bar_y := TOP
var _bar_v := 0.0
var _age := 0.0
var _title: Label
var _sub: Label
var _hint: Label
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title = _make_label(Vector2(LEFT - 4, 52), 34, Color(0.75, 1.0, 1.0))
	_title.text = "TITLE_NAME"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	_sub = _make_label(Vector2(LEFT, 98), 9, Color(1.4, 0.6, 1.3))
	_sub.text = "TITLE_SUB"
	_sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	_hint = _make_label(Vector2(LEFT, 330), 7, Color(0.6, 0.75, 0.8))
	_hint.text = "TITLE_HINT"
	_hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	visible = false


func _make_label(pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(460, size + 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	add_child(l)
	return l


func open(page := "main") -> void:
	visible = true
	_age = 0.0
	_show_page(page)


func close() -> void:
	visible = false


func _show_page(page: String) -> void:
	_page = page
	_items.clear()
	match page:
		"main":
			if Progress.has_save():
				_items.append([tr("MENU_CONTINUE") % (int(Progress.data.region) + 1), "continue", 0, true])
			_items.append([tr("MENU_NEW"), "region", 0, true])
			_items.append([tr("MENU_REGIONS"), "page", 1, true])
			_items.append([tr("MENU_TRAINING"), "page", 2, true])
			_items.append([tr("MENU_SETTINGS"), "settings", 0, true])
			_items.append([tr("MENU_QUIT"), "quit", 0, true])
		"regions":
			var unlocked := Progress.unlocked()
			for i in 5:
				var name: String = tr(D13Maps.REGIONS[i].name)
				var b := Progress.best(i)
				var txt := name + ("   " + Hud._fmt(b) if b >= 0.0 else "")
				if i >= unlocked:
					txt = name + "   " + tr("MENU_LOCKED")
				_items.append([txt, "region", i, i < unlocked])
			_items.append([tr("MENU_BACK"), "page", 0, true])
		"training":
			_items.append([tr("MENU_T_RANGE"), "training", 0, true])
			_items.append([tr("MENU_T_ARENA"), "training", 1, true])
			_items.append([tr("MENU_T_POSSESS"), "training", 2, true])
			_items.append([tr("MENU_BACK"), "page", 0, true])
	for l in _labels:
		l.queue_free()
	_labels.clear()
	for i in _items.size():
		var l := _make_label(Vector2(LEFT, TOP + i * ITEM_H), 12, C_ITEM if _items[i][3] else C_LOCKED)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.text = _items[i][0]
		_labels.append(l)
	_sel = 0
	_bar_y = TOP
	_age = minf(_age, 0.3)
	_page_age = 0.0


const C_ITEM := Color(0.75, 0.92, 1.0)
const C_LOCKED := Color(0.35, 0.42, 0.48)
var _page_age := 0.0


func _move(d: int) -> void:
	if _items.is_empty():
		return
	_sel = (_sel + d + _items.size()) % _items.size()
	Audio.play("ui_tick", -6.0, 1.1)


func _confirm() -> void:
	var it: Array = _items[_sel]
	if not it[3]:
		Audio.play("shield_block", -12.0, 1.6)
		return
	Audio.play("ui_open", -2.0)
	if it[1] == "page":
		_show_page(["main", "regions", "training"][it[2]])
		return
	chosen.emit(it[1], it[2])


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
		_move(1)
	elif event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
		_move(-1)
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("jump") or event.is_action_pressed("slash_key"):
		_confirm()
	elif event.is_action_pressed("settings") or event.is_action_pressed("ui_cancel"):
		if _page != "main":
			Audio.play("ui_tick", -6.0, 0.8)
			_show_page("main")
	else:
		return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var i := _item_at(event.position)
		if i >= 0 and i != _sel:
			_sel = i
			Audio.play("ui_tick", -10.0, 1.1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _item_at(event.position)
		if i >= 0:
			_sel = i
			_confirm()


func _item_at(p: Vector2) -> int:
	var s := p
	for i in _labels.size():
		var r := Rect2(LEFT - 12, TOP + i * ITEM_H - 2, 300, ITEM_H)
		if r.has_point(s):
			return i
	return -1


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_age += delta
	_page_age += delta
	_title.visible_ratio = clampf(_age / 0.5, 0.0, 1.0)
	_sub.visible_ratio = clampf((_age - 0.3) / 0.4, 0.0, 1.0)
	_hint.modulate.a = clampf((_age - 0.6) / 0.3, 0.0, 1.0)
	# 选中框：弹簧（阻尼比约 0.6，带一点过冲）
	var target := TOP + _sel * ITEM_H
	_bar_v += ((target - _bar_y) * 520.0 - _bar_v * 28.0) * delta
	_bar_y += _bar_v * delta
	for i in _labels.size():
		var l := _labels[i]
		# 依次滑进来：每项晚 0.04 秒，缓出
		var k := clampf((_page_age - 0.04 * i) / 0.22, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		var off := 12.0 if i == _sel else 0.0
		var x: float = l.position.x
		var want := LEFT - 40.0 * (1.0 - e) + off
		l.position.x = lerpf(x, want, 1.0 - exp(-24.0 * delta)) if k >= 1.0 else want
		l.modulate.a = e
		var base_c: Color = C_ITEM if _items[i][3] else C_LOCKED
		l.add_theme_color_override("font_color", Color(1.6, 2.0, 2.1) if i == _sel and _items[i][3] else base_c)
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.01, 0.02, 0.04, 0.84))
	# 扫描线
	var y := fmod(_t * 40.0, 4.0)
	while y < vp.y:
		draw_line(Vector2(0, y), Vector2(vp.x, y), Color(0.3, 0.8, 1.0, 0.03), 1.0)
		y += 4.0
	# 标题下的青色横线：从左向右展开
	var k := 1.0 - pow(1.0 - clampf(_age / 0.6, 0.0, 1.0), 3.0)
	draw_line(Vector2(LEFT, 96), Vector2(LEFT + 300 * k, 96), Color(0.4, 1.6, 1.9, 0.9), 1.0)
	draw_rect(Rect2(LEFT - 6, 92, 3, 8), Color(1.4, 0.5, 1.3))
	# 选中框：左边一根亮条 + 一道渐隐的底
	if not _items.is_empty():
		var by := _bar_y - 1.0
		draw_rect(Rect2(LEFT - 14, by, 3, ITEM_H - 4), Color(0.5, 1.8, 2.0))
		for i in 8:
			draw_rect(Rect2(LEFT - 10 + i * 30, by, 30, ITEM_H - 4), Color(0.2, 0.7, 0.9, 0.12 * (1.0 - i / 8.0)))
