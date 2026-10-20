extends Node
## 玩家设置（Esc 打开设置页）：闪光、色差、震屏、雨、辉光。保存在 user://settings.json。
## 测试运行（-s / --script / tests/）既不读也不写。

const PATH := "user://settings.json"
## [名字, 默认值, 最小, 最大, 步长]
const SPECS := [
	["flash", 1.0, 0.0, 1.0, 1.0],
	["aberration", 1.0, 0.0, 1.0, 0.1],
	["shake", 1.0, 0.0, 1.0, 0.1],
	["rain", 1.0, 0.0, 1.0, 1.0],
	["glow", 1.0, 0.0, 1.5, 0.1],
	["music", 1.0, 0.0, 1.0, 0.05],
	["sfx", 1.0, 0.0, 1.0, 0.05],
]

signal changed

var v := {}
var testing := false


func _ready() -> void:
	testing = Tuning.is_test_run()
	for s in SPECS:
		v[s[0]] = s[1]
	if not testing and FileAccess.file_exists(PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			for k in data:
				if v.has(k):
					v[k] = float(data[k])
	_apply_volumes()


func set_value(key: String, value: float) -> void:
	v[key] = value
	_apply_volumes()
	changed.emit()
	if testing:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(v, "\t"))


func _apply_volumes() -> void:
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	if music >= 0:
		AudioServer.set_bus_volume_db(music, linear_to_db(maxf(v.music, 0.0001)))
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(v.sfx, 0.0001)))
