class_name SettingsPanel
extends PanelContainer
## 设置页（Esc）：闪光、色差、震屏、雨、辉光、音乐和音效音量。打开时游戏暂停。


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -130
	offset_right = 130
	offset_top = -95
	offset_bottom = 95
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.95)
	sb.border_color = Color(0.3, 0.9, 1.0, 0.7)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var title := Label.new()
	title.text = "SET_TITLE"
	title.add_theme_font_size_override("font_size", 11)
	col.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	col.add_child(grid)
	for s in Settings.SPECS:
		var key: String = s[0]
		var l := Label.new()
		l.text = "SET_" + key
		l.custom_minimum_size.x = 90
		l.add_theme_font_size_override("font_size", 8)
		grid.add_child(l)
		var slider := HSlider.new()
		slider.min_value = s[2]
		slider.max_value = s[3]
		slider.step = s[4]
		slider.value = Settings.v[key]
		slider.custom_minimum_size = Vector2(130, 10)
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(func(value): Settings.set_value(key, value))
		grid.add_child(slider)
	var hint := Label.new()
	hint.text = "SET_HINT"
	hint.add_theme_font_size_override("font_size", 7)
	col.add_child(hint)
