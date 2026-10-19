extends Node
## 中英双语。所有界面文字都用这里的键；F2 切换语言。

const STRINGS := {
	"SEC_1": ["长直道 · 疾跑与急停", "STRAIGHT · SPRINT & STOP"],
	"SEC_2": ["台阶 · 跳跃高度", "STEPS · JUMP HEIGHT"],
	"SEC_3": ["低矮通道 · 滑铲通过", "LOW TUNNEL · SLIDE THROUGH"],
	"SEC_4": ["深沟 · 空中冲刺", "GAP · AIR DASH"],
	"SEC_5": ["竖井 · 蹬墙攀爬", "SHAFT · WALL CLIMB"],
	"SEC_6": ["靶桩 · 挥刀", "DUMMIES · SLASH"],
	"SEC_7": ["终点", "FINISH"],
	"HUD_TIME": ["用时 %s", "TIME %s"],
	"HUD_BEST": ["最佳 %s", "BEST %s"],
	"HUD_SPEED": ["速度 %d", "SPEED %d"],
	"HUD_FINISH": ["完成  %s", "CLEAR  %s"],
	"HUD_HINT": [
		"A/D 移动   空格/W 跳（贴墙按住朝墙连按=爬墙）   Shift 冲刺   S/Ctrl 滑铲   右键 挥刀   R 重来   F1 调参   F2 English   F3 像素/高清",
		"A/D MOVE   SPACE/W JUMP (hold toward wall + tap = climb)   SHIFT DASH   S/CTRL SLIDE   RMB SLASH   R RESTART   F1 TUNING   F2 中文   F3 PIXEL/HD",
	],
	"HUD_MODE_HD": ["高清渲染", "HD render"],
	"HUD_MODE_PIXEL": ["像素渲染 640×360", "Pixel render 640x360"],
	"TUNE_TITLE": ["手感调参", "FEEL TUNING"],
	"TUNE_EXPORT": ["导出", "Export"],
	"TUNE_RESET": ["恢复默认", "Defaults"],
	"TUNE_SAVED": ["已导出：%s", "Saved: %s"],
	"TUNE_TEST": ["测试运行，不写文件", "Test run, nothing written"],
	"TUNE_run_speed": ["疾跑速度", "Run speed"],
	"TUNE_run_accel_time": ["起步到全速(秒)", "Time to top speed"],
	"TUNE_ground_decel": ["地面松手减速", "Ground release decel"],
	"TUNE_turn_accel": ["转向加速度", "Turn accel"],
	"TUNE_air_accel": ["空中加速度", "Air accel"],
	"TUNE_air_decel": ["空中松手减速", "Air release decel"],
	"TUNE_overspeed_decay": ["超速衰减", "Overspeed decay"],
	"TUNE_jump_velocity": ["起跳速度", "Jump velocity"],
	"TUNE_gravity": ["上升重力", "Rise gravity"],
	"TUNE_fall_gravity": ["下落重力", "Fall gravity"],
	"TUNE_jump_cut_mult": ["松键截断倍率", "Jump cut multiplier"],
	"TUNE_max_fall": ["最大下落速度", "Max fall speed"],
	"TUNE_coyote": ["土狼时间", "Coyote time"],
	"TUNE_jump_buffer": ["跳跃缓冲", "Jump buffer"],
	"TUNE_dash_speed": ["冲刺速度", "Dash speed"],
	"TUNE_dash_time": ["冲刺时长", "Dash time"],
	"TUNE_dash_cooldown": ["冲刺冷却", "Dash cooldown"],
	"TUNE_dash_carry": ["冲刺后保留速度", "Dash speed carry"],
	"TUNE_air_dashes": ["空中冲刺次数", "Air dashes"],
	"TUNE_slide_speed": ["滑铲初速", "Slide speed"],
	"TUNE_slide_friction": ["滑铲摩擦", "Slide friction"],
	"TUNE_slide_min_time": ["滑铲最短时长", "Slide min time"],
	"TUNE_slide_max_time": ["滑铲最长时长", "Slide max time"],
	"TUNE_slide_min_speed": ["通道内最低滑速", "Slide min speed (tunnel)"],
	"TUNE_wall_slide_speed": ["贴墙下滑速度", "Wall slide speed"],
	"TUNE_wall_jump_x": ["蹬墙水平速度", "Wall jump X"],
	"TUNE_wall_jump_y": ["蹬墙垂直速度", "Wall jump Y"],
	"TUNE_wall_jump_lock": ["蹬墙锁方向", "Wall jump input lock"],
	"TUNE_wall_climb_x": ["爬墙跳离墙速度", "Climb jump X"],
	"TUNE_wall_climb_y": ["爬墙跳向上速度", "Climb jump Y"],
	"TUNE_slash_lunge": ["出刀前冲", "Slash lunge"],
	"TUNE_shake": ["震屏强度", "Screen shake"],
	"TUNE_slash_duration": ["挥刀时长", "Slash duration"],
	"TUNE_hit_stop": ["命中停顿", "Hit stop"],
	"TUNE_camera_look_ahead": ["镜头前瞻", "Camera look-ahead"],
}

const LOCALES := ["zh", "en"]


func _ready() -> void:
	for i in LOCALES.size():
		var t := Translation.new()
		t.locale = LOCALES[i]
		for key in STRINGS:
			t.add_message(key, STRINGS[key][i])
		TranslationServer.add_translation(t)
	TranslationServer.set_locale("zh" if OS.get_locale_language() == "zh" else "en")


func toggle() -> void:
	TranslationServer.set_locale("en" if TranslationServer.get_locale().begins_with("zh") else "zh")
