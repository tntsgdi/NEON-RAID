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
	"TIP_RANGE": ["按住方向加速到疾跑 · 空格跳 · Shift 冲刺 · C 滑铲 · 右键挥刀 · 左键射击", "Hold a direction to sprint · SPACE jump · SHIFT dash · C slide · RMB slash · LMB shoot"],
	"TIP_WALL": ["贴住墙、按住朝墙的方向，连按空格就能沿墙往上爬", "Against a wall, hold toward it and tap SPACE to climb"],
	"TIP_ARENA": ["敌人开火前会拉出红色瞄准线：看准时机冲刺穿过子弹，或者右键把子弹砍回去", "Red aim lines warn of shots: dash through the bullet, or slash it back with RMB"],
	"TIP_RUSHER": ["冲锋机压低身体就要冲过来：冲刺穿过它，或者正面一刀招架", "A crouching rusher is about to charge: dash through, or slash it head-on to parry"],
	"TIP_SHIELD": ["盾兵正面挡子弹：绕到背后，或者跳起来下劈（空中按住 S + 右键）", "Shields block shots from the front: get behind, or down-slash from above (S + RMB in the air)"],
	"TIP_OVERCLOCK": ["神经超频！慢动作期间，下一击伤害翻倍", "NEURAL OVERCLOCK! Your next hit deals double damage"],
	"HUD_HINT": [
		"Esc 设置   R 重来   F1 调参   F2 English   F3 像素/高清   F4 切换场地（手感测试场 / 战斗训练场）   支持手柄",
		"ESC SETTINGS   R RESTART   F1 TUNING   F2 中文   F3 PIXEL/HD   F4 SWITCH LEVEL (feel range / combat arena)   GAMEPAD OK",
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
	"SET_TITLE": ["设置", "SETTINGS"],
	"SET_flash": ["闪光特效", "Flash effects"],
	"SET_aberration": ["色差", "Chromatic aberration"],
	"SET_shake": ["震屏", "Screen shake"],
	"SET_rain": ["雨", "Rain"],
	"SET_glow": ["辉光", "Glow"],
	"SET_music": ["音乐音量", "Music volume"],
	"SET_sfx": ["音效音量", "SFX volume"],
	"SET_HINT": ["Esc / 手柄 Start 关闭 · 设置会自动保存", "Esc / Start to close · saved automatically"],
	"RATE_TITLE": ["训练完成  评级 %s", "ARENA CLEAR  GRADE %s"],
	"RATE_BODY": ["用时 %s   受击 %d   弹反 %d   招架 %d   精准闪避 %d\n生存模式开始：敌人会越来越多", "Time %s   Hits %d   Deflects %d   Parries %d   Perfect dodges %d\nSurvival begins: waves keep growing"],
	"SURV_WAVE": ["生存模式 · 第 %d 波", "SURVIVAL · WAVE %d"],
	"SURV_OVER": ["生存到第 %d 波  最佳 %d 波", "SURVIVED TO WAVE %d  BEST %d"],
	"TUNE_slash_duration": ["挥刀时长", "Slash duration"],
	"TUNE_hit_stop": ["命中停顿", "Hit stop"],
	"TUNE_gun_cooldown": ["射击间隔", "Shot cooldown"],
	"TUNE_gun_energy": ["能量格数", "Gun energy cells"],
	"TUNE_gun_regen_time": ["能量回满(秒)", "Energy refill time"],
	"TUNE_bullet_speed": ["子弹速度", "Bullet speed"],
	"TUNE_iframes": ["受伤无敌时间", "Hurt i-frames"],
	"TUNE_perfect_window": ["精准闪避窗口", "Perfect dodge window"],
	"TUNE_dash_iframes": ["冲刺无敌时间", "Dash i-frames"],
	"TUNE_deflect_window": ["弹反判定时间", "Deflect window"],
	"TUNE_overclock_time": ["超频慢动作时长", "Overclock duration"],
	"TUNE_overclock_scale": ["超频时间流速", "Overclock time scale"],
	"ARENA_WAVE": ["战斗训练场 · 第 %d/%d 波", "COMBAT ARENA · WAVE %d/%d"],
	"ARENA_CLEAR": ["训练完成", "ARENA CLEAR"],
	"HUD_OVERCLOCK": ["神经超频", "OVERCLOCK"],
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
