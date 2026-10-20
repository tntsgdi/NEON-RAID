class_name Progress
## 第 1 关的进度存档（user://progress.json）：解锁到第几个区域、最远的检查点、每个区域的最佳用时。
## 测试运行（-s / --script / tests/）既不读也不写——绝不碰玩家的真实存档；写入前留一份 .bak。

const PATH := "user://progress.json"

static var data := {"unlocked": 1, "region": 0, "checkpoint": [], "best": {}}
static var _loaded := false


static func _testing() -> bool:
	return Tuning.is_test_run()


static func load_data() -> void:
	if _loaded:
		return
	_loaded = true
	if _testing() or not FileAccess.file_exists(PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if d is Dictionary:
		for k in d:
			data[k] = d[k]


static func save() -> void:
	if _testing():
		return
	if FileAccess.file_exists(PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(PATH + ".bak"))
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


static func has_save() -> bool:
	load_data()
	return int(data.region) > 0 or not (data.checkpoint as Array).is_empty()


static func unlocked() -> int:
	load_data()
	return int(data.unlocked)


## 走过一个检查点：记下区域和位置（"继续游戏"从这里开始）
static func reach_checkpoint(region: int, pos: Vector2) -> void:
	load_data()
	data.region = region
	data.checkpoint = [pos.x, pos.y]
	save()


## 打完一个区域：解锁下一个、更新最佳用时；下一次"继续"从下一个区域开头开始
static func clear_region(region: int, time: float) -> bool:
	load_data()
	data.unlocked = maxi(int(data.unlocked), mini(region + 2, 5))
	var key := str(region)
	var record: bool = not data.best.has(key) or time < float(data.best[key])
	if record:
		data.best[key] = time
	data.region = mini(region + 1, 4)
	data.checkpoint = []
	save()
	return record


static func best(region: int) -> float:
	load_data()
	return float(data.best.get(str(region), -1.0))
