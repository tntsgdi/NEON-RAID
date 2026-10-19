extends Node
## 手感参数。F1 面板里实时调整，"导出"写到 user://tuning.json，启动时读回。
## 测试运行（-s / --script / tests/）既不读也不写这个文件。

const PATH := "user://tuning.json"

## [名字, 默认值, 最小, 最大, 步长]。速度单位：像素/秒（主角约 40 像素高）。
const SPECS := [
	["run_speed", 260.0, 120.0, 420.0, 5.0],
	["run_accel_time", 0.25, 0.05, 0.6, 0.01],
	["ground_decel", 2200.0, 400.0, 6000.0, 50.0],
	["turn_accel", 3200.0, 400.0, 8000.0, 50.0],
	["air_accel", 1100.0, 200.0, 4000.0, 50.0],
	["air_decel", 500.0, 0.0, 3000.0, 50.0],
	["overspeed_decay", 450.0, 0.0, 3000.0, 25.0],
	["jump_velocity", 470.0, 250.0, 700.0, 5.0],
	["gravity", 1500.0, 600.0, 3000.0, 25.0],
	["fall_gravity", 2100.0, 600.0, 4000.0, 25.0],
	["jump_cut_mult", 2.6, 1.0, 5.0, 0.1],
	["max_fall", 520.0, 200.0, 900.0, 10.0],
	["coyote", 0.1, 0.0, 0.25, 0.01],
	["jump_buffer", 0.12, 0.0, 0.25, 0.01],
	["dash_speed", 540.0, 250.0, 900.0, 10.0],
	["dash_time", 0.14, 0.05, 0.35, 0.01],
	["dash_cooldown", 0.25, 0.0, 1.0, 0.01],
	["dash_carry", 0.6, 0.0, 1.0, 0.05],
	["air_dashes", 1.0, 0.0, 3.0, 1.0],
	["slide_speed", 340.0, 150.0, 600.0, 5.0],
	["slide_friction", 380.0, 0.0, 1500.0, 10.0],
	["slide_min_time", 0.22, 0.05, 0.6, 0.01],
	["slide_max_time", 0.6, 0.2, 1.5, 0.01],
	["slide_min_speed", 210.0, 50.0, 300.0, 5.0],
	["wall_slide_speed", 120.0, 30.0, 400.0, 5.0],
	["wall_jump_x", 290.0, 100.0, 600.0, 5.0],
	["wall_jump_y", 450.0, 200.0, 700.0, 5.0],
	["wall_jump_lock", 0.13, 0.0, 0.4, 0.01],
	["wall_climb_x", 120.0, 0.0, 300.0, 5.0],
	["wall_climb_y", 480.0, 250.0, 700.0, 5.0],
	["slash_duration", 0.17, 0.08, 0.4, 0.01],
	["slash_lunge", 170.0, 0.0, 500.0, 5.0],
	["hit_stop", 0.06, 0.0, 0.15, 0.005],
	["shake", 1.0, 0.0, 2.0, 0.05],
	["camera_look_ahead", 0.35, 0.0, 0.8, 0.01],
]

var v := {}
var testing := false


func _ready() -> void:
	testing = is_test_run()
	reset()
	if not testing:
		load_file()


func is_test_run() -> bool:
	for a in OS.get_cmdline_args():
		if a in ["-s", "--script"] or a.contains("tests/") or a.begins_with("--test"):
			return true
	return false


func reset() -> void:
	for s in SPECS:
		v[s[0]] = s[1]


func load_file() -> void:
	if testing or not FileAccess.file_exists(PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Dictionary:
		for k in data:
			if v.has(k):
				v[k] = float(data[k])


## 返回导出文件的完整路径；测试运行时不写文件，返回空串。
func export_file() -> String:
	if testing:
		return ""
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(v, "\t"))
	return ProjectSettings.globalize_path(PATH)
