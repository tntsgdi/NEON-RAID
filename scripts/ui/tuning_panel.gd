class_name TuningPanel
extends PanelContainer
## F1 手感调参面板：拖动即时生效；"导出"写入 user://tuning.json，下次启动自动读取。

var _sliders := {}
var _values := {}
var _status: Label


func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -236
	offset_right = -4
	offset_top = 34
	offset_bottom = -16
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.9)
	sb.border_color = Color(0.25, 0.85, 0.95, 0.6)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	add_child(col)
	var title := Label.new()
	title.text = "TUNE_TITLE"
	title.add_theme_font_size_override("font_size", 9)
	col.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 1)
	scroll.add_child(grid)
	for s in Tuning.SPECS:
		var key: String = s[0]
		var name_label := Label.new()
		name_label.text = "TUNE_" + key
		name_label.custom_minimum_size.x = 82
		name_label.clip_text = true
		name_label.add_theme_font_size_override("font_size", 6)
		grid.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = s[2]
		slider.max_value = s[3]
		slider.step = s[4]
		slider.custom_minimum_size = Vector2(90, 8)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.focus_mode = Control.FOCUS_NONE
		slider.value = Tuning.v[key]
		slider.value_changed.connect(_on_changed.bind(key))
		grid.add_child(slider)
		var value_label := Label.new()
		value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value_label.custom_minimum_size.x = 32
		value_label.add_theme_font_size_override("font_size", 6)
		grid.add_child(value_label)
		_sliders[key] = slider
		_values[key] = value_label
		_show_value(key)

	var buttons := HBoxContainer.new()
	col.add_child(buttons)
	for b in [["TUNE_EXPORT", _export], ["TUNE_RESET", _reset]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 7)
		btn.pressed.connect(b[1])
		buttons.add_child(btn)
	_status = Label.new()
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_status.add_theme_font_size_override("font_size", 6)
	col.add_child(_status)


func _on_changed(value: float, key: String) -> void:
	Tuning.v[key] = value
	_show_value(key)


func _show_value(key: String) -> void:
	var v: float = Tuning.v[key]
	_values[key].text = str(int(v)) if v >= 100.0 or is_equal_approx(v, roundf(v)) else "%.3f" % v


func _export() -> void:
	var path := Tuning.export_file()
	_status.text = tr("TUNE_SAVED") % path if path != "" else tr("TUNE_TEST")


func _reset() -> void:
	Tuning.reset()
	for key in _sliders:
		_sliders[key].set_value_no_signal(Tuning.v[key])
		_show_value(key)
