class_name StriderRig
extends Node2D
## R-0 基础机体：反关节（鸟腿）双足机。全部程序化：
##   楔形机身——天生前倾，疾跑时压到约 40°，倾角由弹簧驱动（加速前冲、急停后坐、落地回弹）
##   鸟腿——大腿/小腿/跖骨三节（膝朝前、踝朝后），IK 求落脚点；跑步有腾空期，触地时脚与地面同速不打滑
##   刀臂——右臂就是长刀，平时拖在身后；挥刀 = 短蓄力 → 全身扭转劈下 → 挥过头再收回
##   背炮——机身背上的小炮塔 360° 跟鼠标
##   线缆——背后两条发光线缆按弹簧物理被风往后拉
## 原点在脚底，按面朝右画；面朝左时 scale.x = -1。

const CYAN := Neon.CYAN_HOT
## 外壳描边带一点点霓虹发光
const EDGE := Color(0.3, 1.1, 1.25)
const EDGE_BACK := Color(0.13, 0.42, 0.5)
const FILL := Color(0.15, 0.18, 0.24)
const FILL_BACK := Color(0.09, 0.11, 0.15)
## 出刀 / 冲刺时刀刃发强光；平时只是亮青色，不盖住机身和腿
const BLADE := Color(1.05, 1.9, 2.1)
const BLADE_REST := Color(0.55, 1.15, 1.3)

const HIP_H := 21.0
const THIGH := 13.0
const SHIN := 13.0
## 跖骨：踝关节在脚尖的后上方
const META := Vector2(-3.0, -7.5)
const BLADE_LEN := 26.0
const ARM_LEN := 6.0
## 触地占一个跑步周期的 40%，其余是摆腿（两条腿交替，中间有腾空）
const STANCE := 0.4

## 挥刀三段：刀相对出刀方向的起止角（度）和挥过头的角度
const SLASH := [
	{"from": -115.0, "to": 70.0, "over": 28.0},
	{"from": 85.0, "to": -100.0, "over": 28.0},
	{"from": -165.0, "to": 195.0, "over": 20.0},
]

## 机身外形：紧凑楔形（后背高厚、机鼻低尖），以髋部为原点、面朝右；和像素贴图 hull 对齐
const HULL := [Vector2(-11, -8), Vector2(-8, -13), Vector2(2, -14), Vector2(10, -11), Vector2(17.5, -4), Vector2(13, -1.5), Vector2(1, 0.5), Vector2(-9, -1.5)]
## 胸口的核心环
const CORE := Vector2(6, -5)
## 脖子根（在机身上）；头是横放的传感器盒，以脖子顶为原点
const NECK := Vector2(4, -13)
const NECK_LEN := 5.0
const HEAD := [Vector2(-6, -3.5), Vector2(8, -3.5), Vector2(10, -0.5), Vector2(8, 2), Vector2(-6, 2)]
const EYE := [Vector2(5, -2), Vector2(9.5, -1.2), Vector2(9.5, 0.6), Vector2(5, 0.6)]
const SHOULDER := Vector2(10, -5)
const TURRET := Vector2(-6, -13)
const CABLE_ANCHORS := [Vector2(-10, -10), Vector2(-10, -6)]
## 持刀三档（刀相对机体的角度，0 = 正前方，90 = 正下方）：
##   走路 / 待机 竖在身前、刀尖点地；跑步 向前平举；疾驰 甩到身后拖着
const HOLD_WALK := 55.0
const HOLD_RUN := 12.0
const HOLD_SPRINT := 165.0
## 转身时长（秒）：慢—快—慢的缓动，像动物转身先收身体再甩过去
const TURN_TIME := 0.14
const CABLE_POINTS := 7
## 像素部件图集目录（tools/pixel/build_r0.py 生成）
const PART_DIR := "res://assets/sprites/r0/"
const CABLE_SEG := 4.0

var hull_angle := 12.0
var _hull_vel := 0.0
var _pelvis_y := -HIP_H
var _pelvis_vel := 0.0
var _blade_angle := 150.0
var _turret_angle := 0.0
var _recoil := 0.0
var _facing := 1
var _cables: Array = []      # 每条线缆：[当前点数组, 上一帧点数组]（局部坐标，面朝右）
var _shapes: Array = []      # 本帧要画的图形，残影直接复制它
var _blade_pts := [Vector2.ZERO, Vector2.ZERO]
var _muzzle := Vector2.ZERO
## 转身：从 ±1 平滑过渡（中途压扁成一条，再翻过来），而不是瞬间翻面
var turn := 1.0
var _prev_blade := 150.0
## 惯性化过渡：切换动作时，旧姿势和新姿势的差在约 0.1 秒内衰减到零（输入立即生效，画面不跳）
const INERTIA_TAU := 0.07
var _last_mode := ""
var _last_toes := [Vector2.ZERO, Vector2.ZERO]
var _last_tilts := [0.0, 0.0]
var _toe_off := [Vector2.ZERO, Vector2.ZERO]
var _tilt_off := [0.0, 0.0]
var _inert_t := 1.0
## 刀臂也做惯性化：出刀、收刀那一刻不会一帧跳过去
## 台阶：机体整体被挪上/挪下时，脚先留在原来的世界位置，再平滑踩到新地面
var _toe_shift := 0.0
var _was_slashing := false
var _last_step := -1
## 关键关节（机体坐标，丝滑探针用）
var keys := {}
var _blade_off := 0.0
## 受击后仰的剩余时间（目镜同时闪红）
var _flinch := 0.0
## 醒来：目镜和核心由暗到亮的剩余时间
var _wake := 0.0
var _blade_t := 1.0
## 刀臂不出刀时是弹簧（换持刀姿势会甩过去、带一点过冲）
var _blade_vel := 0.0
var _turn_lin := 1.0
## 出刀时髋部往前送（重心前移），弹簧
var _pelvis_x := 0.0
var _px_vel := 0.0
## 头：像鸟一样稳住，角度和位置都是弹簧
var _head_angle := 0.0
var _head_vel := 0.0
var _head_off := Vector2.ZERO
var _head_off_vel := Vector2.ZERO


func _ready() -> void:
	for a in CABLE_ANCHORS:
		var pts := []
		for i in CABLE_POINTS:
			pts.append(Vector2(0, -HIP_H) + a + Vector2(-CABLE_SEG * i, 0))
		_cables.append([pts, pts.duplicate()])


## 每个物理帧由 Player 调用。m 是机体的运动状态（见 Player._motion）。
func update(m: Dictionary, delta: float) -> void:
	if m.facing != _facing:
		_mirror_cables()
		_facing = m.facing
	# 转身：慢—快—慢（smoothstep）约 0.14 秒压扁再翻过来；中途身体收一下、髋往下沉
	_turn_lin = move_toward(_turn_lin, float(m.facing), delta / TURN_TIME * 2.0)
	var ts := (_turn_lin + 1.0) * 0.5
	turn = ts * ts * (3.0 - 2.0 * ts) * 2.0 - 1.0
	var state: String = m.state
	var ratio: float = m.speed_ratio

	# ---- 机身倾角与髋部高度（弹簧：有过冲和回弹）
	var target_angle := 12.0
	var target_y := -HIP_H
	match state:
		"run":
			# 每一步：落地时压低、蹬地时弹起，机身跟着点头；疾驰档再压低、再前倾
			var beat: float = sin(m.run_phase * TAU * 2.0)
			target_angle = 14.0 + 26.0 * clampf(ratio, 0.0, 1.0) + beat * 3.0 * ratio + (7.0 if m.sprint else 0.0)
			target_y = -HIP_H + 2.5 - absf(beat) * 4.5 * clampf(ratio, 0.0, 1.0) + (2.0 if m.sprint else 0.0)
		"idle":
			target_angle = 10.0 + sin(m.time * 2.2) * 1.5
			target_y = -HIP_H + 1.0 + sin(m.time * 2.2) * 0.6
		"skid":
			target_angle = -12.0
			target_y = -HIP_H + 4.0
		"air":
			target_angle = 18.0 + clampf(m.vel.y / 30.0, -10.0, 14.0)
			target_y = -HIP_H - 2.0
		"dash":
			target_angle = 52.0
			target_y = -HIP_H + 3.0
		"slide":
			target_angle = -6.0
			target_y = -10.0
		"wall":
			target_angle = -28.0
			target_y = -HIP_H
		"kneel":
			target_angle = 30.0
			target_y = -11.0
	target_angle += clampf(m.accel_x * m.facing * 0.012, -14.0, 16.0)
	target_y += m.land_squash * 7.0
	var turning := 1.0 - absf(turn)
	target_y += turning * 3.0
	target_angle -= turning * 6.0
	# 出刀：重心前送、髋下沉（地面上）
	var lunge_x := 0.0
	if m.slash_step >= 0 and (state == "idle" or state == "run" or state == "skid"):
		var w := sin(clampf(m.slash_t / 0.7, 0.0, 1.0) * PI)
		lunge_x = 4.0 * w
		target_y += 2.0 * w
	_px_vel += ((lunge_x - _pelvis_x) * 400.0 - _px_vel * 28.0) * delta
	_pelvis_x += _px_vel * delta
	if m.slash_step >= 0:
		target_angle += _slash_twist(m.slash_step, m.slash_t)
	var k_angle := 260.0 if state != "dash" else 600.0
	_hull_vel += ((target_angle - hull_angle) * k_angle - _hull_vel * 24.0) * delta
	hull_angle += _hull_vel * delta
	_pelvis_vel += ((target_y - _pelvis_y) * 500.0 - _pelvis_vel * 30.0) * delta
	_pelvis_y += _pelvis_vel * delta
	# 贴墙时机身挪离墙面，不插进墙里（墙在身后）
	var pelvis := Vector2((8.0 if state == "wall" else 0.0) + _pelvis_x, _pelvis_y)
	var rot := deg_to_rad(hull_angle)

	# ---- 腿：脚尖落点 → 三节 IK（膝朝前、踝朝后）
	var feet := _foot_targets(m, pelvis)
	if state != _last_mode:
		# 动作切换：记下旧脚位与新目标的差，接下来让它平滑衰减
		for i in 2:
			_toe_off[i] = _last_toes[i] - feet[i][0] - Vector2(0, _toe_shift)  # 台阶补偿另外单独衰减，别算两遍
			_tilt_off[i] = _last_tilts[i] - feet[i][1]
		_inert_t = 0.0
		_last_mode = state
	_inert_t += delta
	var fade := exp(-_inert_t / INERTIA_TAU)
	_toe_shift *= exp(-delta / 0.05)
	var legs := []
	for i in 2:
		var toe: Vector2 = feet[i][0] + _toe_off[i] * fade + Vector2(0, _toe_shift)
		var tilt: float = feet[i][1] + _tilt_off[i] * fade
		_last_toes[i] = toe
		_last_tilts[i] = tilt
		legs.append(_leg(pelvis, toe, tilt))

	# ---- 刀臂
	var shoulder := pelvis + SHOULDER.rotated(rot)
	var rest := 130.0 + hull_angle * 0.3
	match state:
		"idle":
			rest = HOLD_WALK + sin(m.time * 2.2) * 2.0
		"run":
			if m.sprint:
				rest = HOLD_SPRINT + hull_angle * 0.3
			elif ratio > 0.6:
				rest = HOLD_RUN + sin(m.run_phase * TAU * 2.0) * 4.0
			else:
				rest = HOLD_WALK + sin(m.run_phase * TAU) * 6.0
		"skid":
			rest = 30.0
		"kneel":
			rest = 100.0
		"wall":
			rest = 60.0
		"dash":
			rest = 175.0
		"slide":
			rest = 170.0
	var want := rest
	var slashing: bool = m.slash_step >= 0
	if slashing:
		want = m.slash_dir + _slash_arc(m.slash_step, m.slash_t)
	# 出刀、收刀、连击换下一刀时：记下旧刀角与新目标的差，接下来平滑接上（不会一帧跳过去）
	if slashing != _was_slashing or (slashing and m.slash_step != _last_step):
		_blade_off = rad_to_deg(angle_difference(deg_to_rad(want), deg_to_rad(_blade_angle)))
		_blade_t = 0.0
		_was_slashing = slashing
	_last_step = m.slash_step
	if slashing:
		# 出刀：前约 0.06 秒从原来的位置接过去，之后严格按挥刀曲线走（命中判定不受影响）
		var before := _blade_angle
		_blade_angle = want + _blade_off * exp(-_blade_t / 0.05)
		# 记下刀的角速度：收刀时带着这股劲甩过去再回位（随势）
		_blade_vel = clampf(rad_to_deg(angle_difference(deg_to_rad(before), deg_to_rad(_blade_angle))) / maxf(delta, 0.001), -1500.0, 1500.0)
	else:
		# 弹簧（阻尼比约 0.7）：换持刀姿势时刀甩过去、稍微过一点再回来，像手臂有重量
		var diff := rad_to_deg(angle_difference(deg_to_rad(_blade_angle), deg_to_rad(want)))
		_blade_vel += (diff * 240.0 - _blade_vel * 22.0) * delta
		_blade_angle += _blade_vel * delta
	_blade_t += delta
	var bdir := Vector2.from_angle(deg_to_rad(_blade_angle))
	var hand := shoulder + bdir * ARM_LEN
	var tip := hand + bdir * BLADE_LEN
	_blade_pts = [to_global(hand + bdir * 4.0), to_global(tip)]

	# ---- 头：像鸟一样稳住——机身怎么前倾后仰，头只跟四分之一；朝瞄准 / 出刀方向点头；
	#      位置挂在脖子上，加速、落地时会晚一点跟上（弹簧）
	var look := 0.0
	if slashing:
		look = clampf(wrapf(m.slash_dir, -180.0, 180.0), -30.0, 30.0)
	elif m.aim_local.x > 0.2:
		look = clampf(rad_to_deg(m.aim_local.angle()), -25.0, 25.0) * 0.6
	var head_target := hull_angle * 0.25 + look - turning * 10.0
	_head_vel += ((head_target - _head_angle) * 320.0 - _head_vel * 22.0) * delta
	_head_angle += _head_vel * delta
	var off_target := Vector2(clampf(-m.accel_x * m.facing * 0.0015, -3.0, 3.0), m.land_squash * 2.5)
	_head_off_vel += ((off_target - _head_off) * 380.0 - _head_off_vel * 20.0) * delta
	_head_off += _head_off_vel * delta
	var neck_base := pelvis + NECK.rotated(rot)
	var head_pos := neck_base + Vector2(0, -NECK_LEN).rotated(deg_to_rad(hull_angle * 0.4)) + _head_off
	var hrot := deg_to_rad(_head_angle)

	# ---- 背炮
	var mount := pelvis + TURRET.rotated(rot)
	var aim: Vector2 = m.aim_local
	_turret_angle = lerp_angle_deg(_turret_angle, rad_to_deg(aim.angle()), 1.0 - exp(-30.0 * delta))
	_recoil = move_toward(_recoil, 0.0, 30.0 * delta)
	var tdir := Vector2.from_angle(deg_to_rad(_turret_angle - _recoil * 3.0))
	var barrel_end := mount + tdir * (9.0 - _recoil)
	_muzzle = barrel_end

	# ---- 线缆
	var world_vel: Vector2 = m.vel
	var local_vel := Vector2(world_vel.x * m.facing, world_vel.y)
	var anchors := []
	for a in CABLE_ANCHORS:
		anchors.append(pelvis + a.rotated(rot))
	_step_cables(anchors, local_vel, delta)

	# ---- 关键关节：换到机体坐标（含骨架自身的旋转、缩放、平移）
	var tf := transform
	keys = {
		"pelvis": tf * pelvis,
		"knee_f": tf * legs[0][1], "knee_b": tf * legs[1][1],
		"toe_f": tf * legs[0][3], "toe_b": tf * legs[1][3],
		"nose": tf * (pelvis + HULL[4].rotated(rot)),
		"tail": tf * (pelvis + HULL[0].rotated(rot)),
		"head": tf * (head_pos + HEAD[2].rotated(hrot)),
		"blade_tip": tf * tip,
		"muzzle": tf * barrel_end,
	}

	# ---- 收集要画的部件（正式像素贴图，见 tools/pixel/build_r0.py）
	_shapes.clear()
	var g: float = maxf(m.glow, 0.0)
	_flinch = maxf(_flinch - delta, 0.0)
	_wake = maxf(_wake - delta, 0.0)
	# glow < 0：没有意识的空机体，目镜和核心变暗
	var eye: Color = Color(0.6, 2.0, 2.3).lerp(Color(2.4, 2.6, 2.7), g) if m.glow >= 0.0 else Color(0.25, 0.35, 0.4)
	if _flinch > 0.0:
		eye = eye.lerp(Color(2.6, 0.5, 0.6), _flinch / 0.25)
	if _wake > 0.0:
		eye = Color(0.25, 0.35, 0.4).lerp(eye, pow(1.0 - _wake / 0.35, 2.0))
	var core: Color = core_color(m.get("hp_k", 1.0), m.time) if m.glow >= 0.0 else Color(0.3, 0.4, 0.45)
	# 后腿（压暗一阶的贴图）
	_add_leg(legs[1], "_b")
	for c in _cables:
		_shapes.append(["cable", c[0].duplicate()])
	_part("turret", mount, tdir.angle())
	_part("hull", pelvis, rot)
	_part("core", pelvis + CORE.rotated(rot), 0.0, core.lerp(Color.WHITE, g * 0.4))
	_part("neck", neck_base, (head_pos - neck_base).angle())
	_part("head", head_pos, hrot)
	_part("eye", head_pos + Vector2(4, -2).rotated(hrot), hrot, eye)
	# 待机：目镜上一道亮光来回扫（机器在"看"）
	if state == "idle" and m.glow >= 0.0:
		var u := 0.5 + 0.5 * sin(m.time * 1.7)
		_shapes.append(["px", head_pos + Vector2(4.5 + 4.0 * u, -2).rotated(hrot), Color(2.6, 2.8, 2.8)])
	if state == "kneel":
		_shapes.append(["ring", pelvis + Vector2(0, -4), 20.0 + 3.0 * sin(m.time * 3.0), Color(0.4, 1.4, 1.7, 0.35 + 0.2 * sin(m.time * 3.0))])
	_add_leg(legs[0], "")
	# 刀残影：挥得越快，前一帧到这一帧之间留下的半透明刀身越多
	var swing := angle_difference(deg_to_rad(_prev_blade), deg_to_rad(_blade_angle))
	if absf(swing) > deg_to_rad(6.0):
		for i in 3:
			var a := deg_to_rad(_prev_blade) + swing * (float(i) + 0.5) / 3.0
			_part("blade", shoulder + Vector2.from_angle(a) * ARM_LEN, a, Color(0.5, 1.6, 1.9, 0.15 + 0.12 * i))
	_prev_blade = _blade_angle
	var hot: bool = m.slash_step >= 0 or state == "dash"
	# 连击越往后刀越亮：第一刀青、第二刀更亮、第三刀接近白热
	var heat := clampf(float(m.slash_step), 0.0, 2.0) / 2.0 if m.slash_step >= 0 else 0.0
	_part("arm", shoulder, bdir.angle())
	_part("blade", hand, bdir.angle())
	if hot:
		_part("blade_glow", hand, bdir.angle(), Color(0.6, 2.0, 2.3).lerp(Color(2.8, 3.0, 3.0), heat))
	_part("shoulder", shoulder, rot)
	queue_redraw()


## 跑步步幅随速度拉长（48–100 像素）：跑得越快步子越大，高速时步频不会快到发抖
static func stride_px(speed: float) -> float:
	return clampf(40.0 + speed * 0.13, 48.0, 100.0)


## 每条腿返回 [脚尖位置, 跖骨方向偏转（度，正值脚尖下垂）]
func _foot_targets(m: Dictionary, pelvis: Vector2) -> Array:
	match m.state:
		"run":
			var out := []
			var length := stride_px(absf(m.vel.x))
			for i in 2:
				var p := fmod(m.run_phase + 0.5 * i, 1.0)
				var half := length * STANCE * 0.5
				if p < STANCE:
					out.append([Vector2(lerpf(half, -half, p / STANCE) + 4.0, 0.0), 0.0])
				else:
					var s := (p - STANCE) / (1.0 - STANCE)
					var x := lerpf(-half, half, s * s * (3.0 - 2.0 * s))
					var lift := sin(s * PI) * (6.0 + 8.0 * clampf(m.speed_ratio, 0.0, 1.0) + (3.0 if m.sprint else 0.0))
					out.append([Vector2(x + 4.0, -lift), 35.0 * sin(s * PI)])
			return out
		"skid":
			return [[Vector2(15, 0), -10.0], [Vector2(-3, 0), 0.0]]
		"air":
			var tuck := clampf(-m.vel.y / 450.0, 0.0, 1.0)
			return [[pelvis + Vector2(7, lerpf(21.0, 13.0, tuck)), 30.0 * tuck], [pelvis + Vector2(-6, lerpf(20.0, 15.0, tuck)), 40.0]]
		"dash":
			return [[pelvis + Vector2(-10, 17), 50.0], [pelvis + Vector2(-19, 12), 60.0]]
		"slide":
			return [[Vector2(20, 0), -20.0], [Vector2(-6, 0), 0.0]]
		"kneel":
			# 待机：一条腿跪下，一条腿撑着
			return [[Vector2(7, 0), -10.0], [Vector2(-9, 0), 70.0]]
		"wall":
			# 一只脚抵住身后的墙，另一条腿收起
			return [[Vector2(-6, -9), -80.0], [pelvis + Vector2(2, 13), 50.0]]
	return [[Vector2(6, 0), 0.0], [Vector2(-5, 0), 0.0]]


## 三节 IK：脚尖 → 踝（跖骨固定长度），髋 → 踝用两节、膝盖朝前。返回 [髋, 膝, 踝, 脚尖]
func _leg(hip: Vector2, toe: Vector2, meta_tilt: float) -> Array:
	var ankle := toe + META.rotated(deg_to_rad(meta_tilt))
	# 踝关节至少在髋部下方 9 像素：脚抬得再高也不会翻到髋部上面（那里 IK 的膝盖方向不确定，会乱跳）
	if ankle.y < hip.y + 9.0:
		var lift_fix := hip.y + 9.0 - ankle.y
		ankle.y += lift_fix
		toe.y += lift_fix
	var d := hip.distance_to(ankle)
	# 腿不完全伸直：接近伸直时 IK 的膝盖位置会剧烈变化（奇异点），留 5% 余量
	var reach := (THIGH + SHIN) * 0.95
	if d > reach:
		var pull := (ankle - hip).normalized() * (d - reach)
		ankle -= pull
		toe -= pull
		d = reach
	d = maxf(d, 2.0)
	var dir := (ankle - hip) / d
	var along := (THIGH * THIGH - SHIN * SHIN + d * d) / (2.0 * d)
	var h := sqrt(maxf(THIGH * THIGH - along * along, 0.0))
	var knee := hip + dir * along - Vector2(-dir.y, dir.x) * h
	return [hip, knee, ankle, toe]


## 一条腿：大腿、膝、小腿、踝、跖骨、脚爪（suffix "_b" = 后腿用的压暗贴图）
func _add_leg(l: Array, suffix: String) -> void:
	_part("thigh" + suffix, l[0], (l[1] - l[0]).angle())
	_part("shin" + suffix, l[1], (l[2] - l[1]).angle())
	_part("meta" + suffix, l[2], (l[3] - l[2]).angle())
	_part("foot" + suffix, l[3], 0.0)
	_part("ankle" + suffix, l[2], 0.0)
	_part("knee" + suffix, l[1], 0.0)


func _part(name: String, pos: Vector2, angle: float, mod := Color.WHITE) -> void:
	_shapes.append(["part", PART_DIR + name, pos, angle, mod])


## 挥刀：第一刀 0–15% 回拉蓄力，然后劈过去并挥过头，最后收回到终点。
## 连击的第二、三刀不再回拉：接着上一刀的收势直接劈出去，整串连起来不顿。
func _slash_arc(step: int, t: float) -> float:
	var s: Dictionary = SLASH[step]
	var sgn := signf(s.to - s.from)
	var wind := 0.15 if step == 0 else 0.0
	var pull := 18.0 if step == 0 else 0.0
	if t < wind:
		return s.from - sgn * pull * (t / wind)
	# 劈砍段占 50%，用正弦缓出（起始角速度约为平均的 1.6 倍）：依然快，但每一帧刀都看得清
	var strike_end := wind + 0.5
	if t < strike_end:
		var u := (t - wind) / 0.5
		var e := sin(u * PI * 0.5)
		return lerpf(s.from - sgn * pull, s.to + sgn * s.over, e)
	var v := (t - strike_end) / (1.0 - strike_end)
	return lerpf(s.to + sgn * s.over, s.to, v * v)


## 挥刀时全身扭转：蓄力往后仰，劈下时往前压（连击的后两刀不再后仰）
func _slash_twist(step: int, t: float) -> float:
	var wind := 0.15 if step == 0 else 0.0
	var back := -10.0 if step == 0 else 4.0
	if t < wind:
		return back * (t / wind)
	if t < wind + 0.5:
		return lerpf(back, 16.0, sin((t - wind) / 0.5 * PI * 0.5))
	return lerpf(16.0, 0.0, (t - wind - 0.5) / (1.0 - wind - 0.5))


func _step_cables(anchors: Array, local_vel: Vector2, delta: float) -> void:
	# 风：和速度反向；重力往下。用 Verlet 积分 + 长度约束
	var acc := Vector2(0, 260.0) - local_vel * 2.2
	for ci in _cables.size():
		var cur: Array = _cables[ci][0]
		var prev: Array = _cables[ci][1]
		for i in range(1, cur.size()):
			var p: Vector2 = cur[i]
			var nxt: Vector2 = p + (p - prev[i]) * 0.86 + acc * delta * delta
			prev[i] = p
			cur[i] = nxt
		cur[0] = anchors[ci]
		prev[0] = anchors[ci]
		for it in 3:
			for i in range(1, cur.size()):
				var a: Vector2 = cur[i - 1]
				var b: Vector2 = cur[i]
				var dv := b - a
				var dl := dv.length()
				if dl > 0.001:
					cur[i] = a + dv / dl * CABLE_SEG


func _mirror_cables() -> void:
	for c in _cables:
		for arr in c:
			for i in arr.size():
				arr[i].x = -arr[i].x


## 机体被整体挪了 dy（世界坐标，正 = 往下）：髋、脚、线缆先留在原处，再平滑追上
func ground_shift(dy: float) -> void:
	_pelvis_y -= dy
	_toe_shift -= dy
	for c in _cables:
		for arr in c:
			for i in arr.size():
				arr[i].y -= dy


func kick() -> void:
	_recoil = 3.0


## 意识回到这具机体：目镜由暗到亮，身体一抖、髋一沉再站稳
func wake_up() -> void:
	_wake = 0.35
	_pelvis_vel += 80.0
	_hull_vel += 260.0


## 受击：机身猛地后仰、髋往下一沉，目镜闪红 0.25 秒（之后弹簧自己弹回来）
func flinch() -> void:
	_hull_vel -= 420.0
	_pelvis_vel += 90.0
	_flinch = 0.25


## 核心灯随血量变色：满血青 → 半血琥珀 → 残血红色脉冲
static func core_color(hp_k: float, time: float) -> Color:
	if hp_k > 0.67:
		return CYAN
	if hp_k > 0.34:
		return Color(2.0, 1.15, 0.3)
	return Color(2.2, 0.25, 0.3) * (0.55 + 0.45 * absf(sin(time * 6.0)))


func muzzle() -> Vector2:
	return to_global(_muzzle)


## 刀身根部与刀尖的全局坐标（刀光拖尾用）
func blade_points() -> Array:
	return _blade_pts


## 当前这一帧要画的图形（倒影用）
func shapes() -> Array:
	return _shapes


## 冲刺残影：把当前这一帧的图形复制一份，慢慢淡出
func spawn_ghost(parent: Node, alpha: float) -> void:
	var g := RigGhost.new()
	g.shapes = _shapes.duplicate(true)
	parent.add_child(g)
	g.global_transform = global_transform
	# 残影：整体压成玩家青的一个暗色剪影（不发光），像素风的"拖影"
	g.modulate = Color(0.25, 0.75, 0.85, alpha)
	g.z_index = -1
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.22)
	tw.tween_callback(g.queue_free)


func _draw() -> void:
	draw_shapes(self, _shapes)


static func draw_shapes(ci: CanvasItem, shapes: Array) -> void:
	# 像素部件：抵消 ci 自身的旋转和缩放，在不旋转的世界像素格上贴预旋转好的图（见 PixelPart）
	var gx := ci.get_global_transform()
	var flip := gx.determinant() < 0.0
	var rho := (gx * Transform2D(0.0, Vector2(-1, 1), 0.0, Vector2.ZERO)).get_rotation() if flip else gx.get_rotation()
	var inv := gx.affine_inverse()
	for s in shapes:
		match s[0]:
			"part":
				var part := PixelPart.get_part(s[1])
				var a: float = (s[3] - rho) if flip else (s[3] + rho)
				part.draw(ci, inv, gx * s[2], a, flip, s[4])
			"px":
				# 单个发光像素
				var wp: Vector2 = (gx * s[1]).round()
				ci.draw_set_transform_matrix(inv)
				ci.draw_rect(Rect2(wp, Vector2.ONE), s[2])
				ci.draw_set_transform_matrix(Transform2D.IDENTITY)
			"poly":
				ci.draw_colored_polygon(s[1], s[2])
				var outline: PackedVector2Array = s[1].duplicate()
				outline.append(s[1][0])
				ci.draw_polyline(outline, s[3], 1.0, true)
			"line":
				ci.draw_line(s[1], s[2], s[4], s[3], true)
			"polyline":
				ci.draw_polyline(s[1], s[2], 1.0, true)
			"dot":
				ci.draw_circle(s[1], s[2], s[3])
			"ring":
				ci.draw_arc(s[1], s[2], 0.0, TAU, 32, s[3], 1.5, true)
			"cable":
				# 线缆：世界像素格上 1 像素宽的暗色线（不抗锯齿），末端一个 2×2 的发光插头
				var pts: Array = s[1]
				ci.draw_set_transform_matrix(inv)
				var prev: Vector2 = (gx * pts[0]).round()
				for i in range(1, pts.size()):
					var cur: Vector2 = (gx * pts[i]).round()
					ci.draw_line(prev + Vector2(0.5, 0.5), cur + Vector2(0.5, 0.5), Color(0.17, 0.2, 0.25), 1.0, false)
					prev = cur
				ci.draw_rect(Rect2(prev - Vector2(0, 0), Vector2(2, 2)), Color(0.8, 2.2, 2.5))
				ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func lerp_angle_deg(a: float, b: float, t: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(a), deg_to_rad(b), t))
