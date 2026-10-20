class_name Player
extends CharacterBody2D
## R-0 基础机体的移动与动作（M1）。
## 只读 PlayerInput，不直接读按键；夺壳时（M3）换的是 input 的来源和机体，不是这套逻辑。
## 移动是一层状态机；挥刀是并行的上半身层，任何移动状态下都能出刀，不会让角色停下。

signal landed(impact: float)
signal state_changed(from: int, to: int)
signal slash_hit(target: Node)
## 请求震屏（强度约 1–8 像素）；dir 不为零时镜头沿这个方向被推一下
signal impact(strength: float, dir: Vector2)
signal died
signal overclocked

enum State { GROUND, AIR, DASH, SLIDE, WALL }
const STATE_NAMES := ["ground", "air", "dash", "slide", "wall"]

const CHEST := Vector2(0, -26)
const STAND := Vector2(12, 36)
const LOW := Vector2(12, 16)
const MAX_HP := 3

var input: PlayerInput = DeviceInput.new()
var state := State.AIR
var facing := 1
var aim := Vector2.RIGHT
var fx_parent: Node
## 最近一次站在地面上的 x，用于掉坑后回到检查点
var last_floor_x := 0.0
var hp := MAX_HP
var energy := 8.0
## >0 时下一次命中伤害翻倍（神经超频的奖励）
var overclock_charge := 0.0

var _iframes := 0.0
var _shot_cd := 0.0
var _regen_delay := 0.0
var _gun_raise := 0.0
var _perfect_used := false

var _coyote := 0.0
var _jump_buffer := 0.0
var _cut_immune := 0.0
var _air_dashes := 1
var _dash_left := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector2.RIGHT
var _ghost_timer := 0.0
var _slide_time := 0.0
var _wall_dir := 0
var _wall_coyote := 0.0
var _last_wall := 0
var _wall_lock := 0.0
var _land_squash := 0.0
var _run_phase := 0.0
var _idle_time := 0.0
var _squash := Vector2.ONE
var _prev_vx := 0.0
var _skid_dust := 0.0
var _air_hang_used := false
var _streak_timer := 0.0

# 挥刀层
var slash_step := -1
var _slash_time := 0.0
var _slash_queued := false
var _slash_hit_done := false
var _slash_dash := false
var _slash_aim := Vector2.RIGHT
var _next_step := 0
var _combo_window := 0.0
## 命中定格：刀停在命中的那一刻
var _slash_freeze := 0.0
## 第三刀之后的后摇，期间不能出刀
var _slash_lock := 0.0

var _rect: RectangleShape2D
var _shape: CollisionShape2D
var rig: StriderRig
var trail: BladeTrail


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 4.0
	_rect = RectangleShape2D.new()
	_shape = CollisionShape2D.new()
	_shape.shape = _rect
	add_child(_shape)
	_set_low(false)
	rig = StriderRig.new()
	add_child(rig)
	if fx_parent == null:
		fx_parent = get_parent()
	add_to_group("player")
	trail = BladeTrail.new()
	trail.z_index = 5
	fx_parent.add_child.call_deferred(trail)


func reset_at(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	_set_low(false)
	slash_step = -1
	_slash_queued = false
	_slash_lock = 0.0
	_slash_freeze = 0.0
	_combo_window = 0.0
	_dash_left = 0.0
	_jump_buffer = 0.0
	_wall_lock = 0.0
	_wall_coyote = 0.0
	_squash = Vector2.ONE
	_air_dashes = int(Tuning.v.air_dashes)
	hp = MAX_HP
	energy = Tuning.v.gun_energy
	overclock_charge = 0.0
	_iframes = 0.0
	rig.visible = true
	last_floor_x = pos.x
	_set_state(State.AIR)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	var T: Dictionary = Tuning.v
	input.poll(self)
	if input.aim.length() > 0.1:
		aim = input.aim.normalized()
	_jump_buffer = T.jump_buffer if input.jump_pressed else maxf(_jump_buffer - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_wall_lock = maxf(_wall_lock - delta, 0.0)
	_wall_coyote = maxf(_wall_coyote - delta, 0.0)
	_cut_immune = maxf(_cut_immune - delta, 0.0)
	_land_squash = maxf(_land_squash - delta * 8.0, 0.0)
	_iframes = maxf(_iframes - delta, 0.0)
	overclock_charge = maxf(overclock_charge - delta, 0.0)
	_idle_time += delta

	match state:
		State.GROUND:
			_ground(delta, T)
		State.AIR:
			_air(delta, T)
		State.DASH:
			_dash(delta, T)
		State.SLIDE:
			_slide(delta, T)
		State.WALL:
			_wall(delta, T)

	var vy_before := velocity.y
	move_and_slide()
	_ledge_assist()
	_after_move(vy_before, T)
	_update_slash(delta, T)
	_update_gun(delta, T)
	_update_facing()
	_animate(delta, T)
	_prev_vx = velocity.x


# ---------------------------------------------------------------- 状态

func _ground(delta: float, T: Dictionary) -> void:
	if input.slide_pressed:
		_start_slide(T)
		return
	if input.dash_pressed and _dash_cd <= 0.0:
		_start_dash(T)
		return
	if _jump_buffer > 0.0:
		_jump(T)
		return
	_run_x(delta, T.run_speed / T.run_accel_time, T.ground_decel, T.turn_accel, T)
	_gravity(delta, T.max_fall, T)


func _air(delta: float, T: Dictionary) -> void:
	_coyote = maxf(_coyote - delta, 0.0)
	_run_x(delta, T.air_accel, T.air_decel, T.air_accel * 1.5, T)
	_wall_dir = touching_wall()
	if _wall_dir != 0:
		_wall_coyote = 0.1
		_last_wall = _wall_dir
	if _jump_buffer > 0.0:
		if _coyote > 0.0:
			_jump(T)
			return
		if _wall_coyote > 0.0:
			_wall_jump(T, _last_wall)
			return
	if input.dash_pressed and _air_dashes > 0 and _dash_cd <= 0.0:
		_start_dash(T)
		return
	if _wall_dir != 0 and velocity.y > 0.0 and _dir_x() == _wall_dir and _wall_lock <= 0.0:
		_set_state(State.WALL)
		_air_dashes = int(T.air_dashes)
		_air_hang_used = false
	_gravity(delta, T.max_fall, T)


func _wall(delta: float, T: Dictionary) -> void:
	_wall_dir = touching_wall()
	if _wall_dir != 0:
		_wall_coyote = 0.1
		_last_wall = _wall_dir
	if _wall_dir == 0 or _dir_x() != _wall_dir:
		_set_state(State.AIR)
		_gravity(delta, T.max_fall, T)
		return
	if _jump_buffer > 0.0:
		_wall_jump(T, _wall_dir)
		return
	if input.dash_pressed and _dash_cd <= 0.0:
		_start_dash(T)
		return
	velocity.x = _wall_dir * 30.0
	_gravity(delta, T.wall_slide_speed, T)
	# 贴墙时手上擦出火星，一眼看出"正扒在墙上"
	_skid_dust -= delta
	if _skid_dust <= 0.0 and velocity.y > 20.0:
		_skid_dust = 0.05
		Fx.dust(fx_parent, global_position + Vector2(_wall_dir * 6, -24), float(-_wall_dir), 2)


func _dash(delta: float, T: Dictionary) -> void:
	_dash_left -= delta
	velocity = _dash_dir * T.dash_speed
	if _dash_dir.y == 0.0:
		velocity.y = 5.0  # 贴着地面冲刺时保持落地判定
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = 0.022
		_spawn_ghost(0.55)
	if _jump_buffer > 0.0:
		if is_on_floor():
			_end_dash(T)
			_jump(T)
			return
		var w := touching_wall()
		if w != 0:
			_end_dash(T)
			_wall_jump(T, w)
			return
	if input.slide_pressed and is_on_floor():
		_end_dash(T)
		_start_slide(T)
		return
	if _dash_left <= 0.0:
		_end_dash(T)


func _slide(delta: float, T: Dictionary) -> void:
	_slide_time += delta
	var blocked := _ceiling_blocked()
	velocity.x = move_toward(velocity.x, 0.0, T.slide_friction * delta)
	if blocked and absf(velocity.x) < T.slide_min_speed:
		velocity.x = facing * T.slide_min_speed
	_gravity(delta, T.max_fall, T)
	_skid_dust -= delta
	if _skid_dust <= 0.0:
		_skid_dust = 0.06
		Fx.dust(fx_parent, global_position + Vector2(-facing * 4, 0), float(-facing), 2)
	if blocked:
		return
	if _jump_buffer > 0.0:
		_end_slide()
		_jump(T)
		return
	if input.dash_pressed and _dash_cd <= 0.0:
		_end_slide()
		_start_dash(T)
		return
	if _slide_time >= T.slide_max_time or (_slide_time >= T.slide_min_time and not input.slide_held) or absf(velocity.x) < 40.0:
		_end_slide()
		_set_state(State.GROUND)


func _after_move(vy_before: float, T: Dictionary) -> void:
	match state:
		State.GROUND, State.SLIDE:
			if not is_on_floor():
				if state == State.SLIDE and not _ceiling_blocked():
					_end_slide()
				if state == State.GROUND or _rect.size == STAND:
					_set_state(State.AIR)
					_coyote = T.coyote
		State.AIR, State.WALL:
			if is_on_floor() and velocity.y >= 0.0:
				_land(vy_before, T)
		State.DASH:
			if is_on_wall() and _dash_dir.x != 0.0 and _dash_left < T.dash_time - 0.02:
				_end_dash(T)
	if is_on_floor():
		last_floor_x = global_position.x


## 墙顶自动翻上：贴墙往上冲、头已经高过墙沿时，把机体推上去
func _ledge_assist() -> void:
	if state != State.AIR and state != State.WALL:
		return
	var dir := _dir_x()
	if dir == 0 or velocity.y > 80.0 or not test_move(global_transform, Vector2(dir * 2, 0)):
		return
	for up in [2, 4, 6, 8, 10, 12, 14]:
		if test_move(global_transform, Vector2(0, -up)):
			return
		if not test_move(global_transform.translated(Vector2(0, -up)), Vector2(dir * 3, 0)):
			global_position += Vector2(dir * 2, -up)
			velocity.y = minf(velocity.y, -60.0)
			velocity.x = dir * maxf(absf(velocity.x), 120.0)
			return


# ---------------------------------------------------------------- 动作

func _jump(T: Dictionary) -> void:
	if _rect.size == LOW:
		_set_low(false)
	velocity.y = -T.jump_velocity
	_jump_buffer = 0.0
	_coyote = 0.0
	_squash = Vector2(0.8, 1.22)
	_set_state(State.AIR)
	Fx.dust(fx_parent, global_position, 0.0, 6)


## 按住朝墙的方向按跳：轻推离墙、向上力度大，会回到同一面墙，单面墙也能一路爬上去；
## 不按方向或按离墙方向：大力蹬开墙面。
func _wall_jump(T: Dictionary, wall: int) -> void:
	if _dir_x() == wall:
		velocity = Vector2(-wall * T.wall_climb_x, -T.wall_climb_y)
		_wall_lock = 0.05
		facing = wall
	else:
		velocity = Vector2(-wall * T.wall_jump_x, -T.wall_jump_y)
		_wall_lock = T.wall_jump_lock
		facing = -wall
	_cut_immune = 0.12
	_jump_buffer = 0.0
	_coyote = 0.0
	_wall_coyote = 0.0
	_air_hang_used = false
	_squash = Vector2(0.82, 1.2)
	_set_state(State.AIR)
	Fx.dust(fx_parent, global_position + Vector2(wall * 6, -12), float(-wall), 5)
	Fx.ring(fx_parent, global_position + Vector2(wall * 6, -16), 18.0)
	Audio.play("walljump", -6.0)


func _start_dash(T: Dictionary) -> void:
	var m := input.move
	var d := Vector2(signf(m.x) if absf(m.x) > 0.3 else 0.0, signf(m.y) if absf(m.y) > 0.3 else 0.0)
	var grounded := is_on_floor() or state == State.SLIDE
	if grounded and d.y > 0.0:
		d.y = 0.0
	if state == State.WALL and int(d.x) == _wall_dir:
		d.x = -_wall_dir
	if d == Vector2.ZERO:
		d = Vector2(facing, 0.0) if state != State.WALL else Vector2(-_wall_dir, 0.0)
	d = d.normalized()
	if not grounded:
		_air_dashes -= 1
	_dash_dir = d
	_dash_left = T.dash_time
	_dash_cd = T.dash_cooldown
	_ghost_timer = 0.0
	_perfect_used = false
	if d.x != 0.0:
		facing = int(signf(d.x))
	if _rect.size == LOW:
		_set_low(false)
	_squash = Vector2(1.25, 0.82)
	_set_state(State.DASH)
	Fx.dust(fx_parent, global_position, -d.x, 6)
	Audio.play("dash", -4.0)
	impact.emit(1.0, -d)


func _end_dash(T: Dictionary) -> void:
	if _dash_dir.x != 0.0:
		velocity.x = _dash_dir.x * maxf(T.run_speed, T.dash_speed * T.dash_carry)
	velocity.y = _dash_dir.y * T.dash_speed * 0.4
	_set_state(State.GROUND if is_on_floor() and _dash_dir.y >= 0.0 else State.AIR)


func _start_slide(T: Dictionary) -> void:
	var dir := _dir_x()
	if absf(velocity.x) > 60.0:
		dir = int(signf(velocity.x))
	elif dir == 0:
		dir = facing
	velocity.x = dir * maxf(absf(velocity.x), T.slide_speed)
	facing = dir
	_slide_time = 0.0
	_skid_dust = 0.0
	_squash = Vector2(1.15, 0.88)
	_set_low(true)
	_set_state(State.SLIDE)
	Fx.dust(fx_parent, global_position, float(-dir), 8)
	Audio.play("slide", -4.0)


func _end_slide() -> void:
	_set_low(false)


func _land(vy: float, T: Dictionary) -> void:
	_air_dashes = int(T.air_dashes)
	_air_hang_used = false
	var hit := clampf(vy / T.max_fall, 0.0, 1.0)
	_land_squash = hit
	_squash = Vector2(1.0 + 0.3 * hit, 1.0 - 0.28 * hit)
	_set_state(State.GROUND)
	if hit > 0.25:
		Fx.dust(fx_parent, global_position, 0.0, 4 + int(hit * 8))
	if hit > 0.6:
		Audio.play("land", lerpf(-10.0, -2.0, hit))
	if hit > 0.85:
		impact.emit(1.5, Vector2.DOWN)
	landed.emit(hit)
	if input.slide_held and absf(velocity.x) > 150.0:
		_start_slide(T)


# ---------------------------------------------------------------- 挥刀层

func _update_slash(delta: float, T: Dictionary) -> void:
	_combo_window = maxf(_combo_window - delta, 0.0)
	_slash_lock = maxf(_slash_lock - delta, 0.0)
	if input.slash_pressed and _slash_lock <= 0.0:
		if slash_step < 0:
			_start_slash(_next_step if _combo_window > 0.0 else 0, T)
		else:
			_slash_queued = true
	if slash_step < 0:
		return
	if _slash_freeze > 0.0:
		_slash_freeze -= delta
		return
	_slash_time += delta
	var dur := slash_duration()
	if _slash_time <= T.deflect_window:
		_try_deflect(T)
	if not _slash_hit_done and _slash_time >= dur * 0.3:
		_do_hit(T)
	if _slash_time >= dur:
		var step := slash_step
		slash_step = -1
		if _slash_queued and step < 2:
			_start_slash(step + 1, T)
		else:
			_next_step = (step + 1) % 3
			_combo_window = 0.0 if step >= 2 else 0.3
			if step >= 2:
				_slash_lock = 0.25


func slash_duration() -> float:
	return Tuning.v.slash_duration * (1.5 if slash_step == 2 else 1.0)


func _start_slash(step: int, T: Dictionary) -> void:
	slash_step = step
	_slash_time = 0.0
	_slash_queued = false
	_slash_hit_done = false
	_slash_dash = state == State.DASH
	_slash_aim = _slash_dir()
	var heavy := step == 2 or _slash_dash
	trail.heavy = heavy
	Audio.play("swing_heavy" if heavy else "swing_%d" % (step + 1), -4.0)
	# 出刀前冲：横斩在地面朝前踏一步；空中第一刀稍微滞空
	var lunge: float = T.slash_lunge * (1.5 if step == 2 else 1.0)
	var sx := float(facing)
	if state == State.GROUND and _slash_aim.y == 0.0:
		if signf(velocity.x) == sx:
			velocity.x = sx * maxf(absf(velocity.x), lunge)
		else:
			velocity.x = sx * lunge
	elif state == State.AIR:
		velocity.x += sx * lunge * 0.4
		if not _air_hang_used:
			_air_hang_used = true
			velocity.y = minf(velocity.y, 10.0)


## 挥刀方向：固定朝面朝方向；按住上 = 上挑，空中按住下 = 下劈（不看鼠标）
func _slash_dir() -> Vector2:
	if input.move.y < -0.5:
		return Vector2.UP
	if input.move.y > 0.5 and state != State.GROUND and state != State.SLIDE:
		return Vector2.DOWN
	return Vector2(facing, 0)


func _do_hit(T: Dictionary) -> void:
	_slash_hit_done = true
	var heavy := slash_step == 2 or _slash_dash
	var reach := 20.0 + (6.0 if slash_step == 2 else 0.0) + (8.0 if _slash_dash else 0.0)
	# 下劈从腰部出刀，打得到脚下的敌人
	var origin := global_position + (Vector2(0, -10) if _slash_aim == Vector2.DOWN else CHEST)
	var center := origin + _slash_aim * 14.0
	var hit_any := false
	for n in get_tree().get_nodes_in_group("hittable"):
		if n.has_method("alive") and not n.alive():
			continue
		var r: Rect2 = n.hurt_rect()
		var closest := Vector2(clampf(center.x, r.position.x, r.end.x), clampf(center.y, r.position.y, r.end.y))
		if closest.distance_to(center) <= reach:
			var power := (2 if heavy else 1) * (2 if overclock_charge > 0.0 else 1)
			n.take_hit(_slash_aim, power, "slash")
			Fx.sparks(fx_parent, closest, _slash_aim, 14 if heavy else 9)
			slash_hit.emit(n)
			hit_any = true
	var s: Dictionary = StriderRig.SLASH[slash_step]
	var base := rad_to_deg(Vector2(_slash_aim.x * facing, _slash_aim.y).angle())
	SlashFx.spawn(fx_parent, origin, base + s.from, base + s.to, facing, 14.0 + reach, heavy)
	if hit_any:
		Audio.play("hit_heavy" if heavy else "hit", -2.0)
		if heavy:
			Music.duck(6.0, 0.25)
		# 下劈打中：像踩弹一样弹起来，并恢复空中冲刺
		if _slash_aim == Vector2.DOWN and state != State.GROUND:
			velocity.y = -T.jump_velocity * 0.85
			_air_dashes = int(T.air_dashes)
			_set_state(State.AIR)
		impact.emit(6.0 if heavy else 3.5, _slash_aim)
		overclock_charge = 0.0
		_slash_freeze = 0.08
		var stop: float = T.hit_stop * (1.7 if heavy else 1.0)
		if stop > 0.0:
			TimeFx.hitstop(stop)


## 刀碰到敌弹就弹回去（弹回的子弹一发打死射手），同时触发神经超频
func _try_deflect(T: Dictionary) -> void:
	var origin := global_position + CHEST
	var center := origin + _slash_aim * 14.0
	var reach := 26.0 + (8.0 if _slash_dash else 0.0)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		if b.global_position.distance_to(center) <= reach:
			b.deflect(self)
			Fx.sparks(fx_parent, b.global_position, -b.velocity.normalized(), 12, Color(1, 1, 1))
			Audio.play("deflect", -2.0)
			Music.duck(6.0, 0.3)
			impact.emit(4.0, _slash_aim)
			TimeFx.hitstop(T.hit_stop * 1.5)
			_overclock(T)


# ---------------------------------------------------------------- 射击与受伤

func _update_gun(delta: float, T: Dictionary) -> void:
	_shot_cd = maxf(_shot_cd - delta, 0.0)
	_gun_raise = maxf(_gun_raise - delta, 0.0)
	_regen_delay = maxf(_regen_delay - delta, 0.0)
	if _regen_delay <= 0.0:
		energy = minf(energy + T.gun_energy / T.gun_regen_time * delta, T.gun_energy)
	if not input.shoot_pressed or _shot_cd > 0.0 or energy < 1.0:
		return
	energy -= 1.0
	_shot_cd = T.gun_cooldown
	_regen_delay = 0.35
	_gun_raise = 0.3
	var muzzle := rig.muzzle()
	var dmg := 2 if overclock_charge > 0.0 else 1
	overclock_charge = 0.0
	Bullet.fire(fx_parent, muzzle, aim * T.bullet_speed, Bullet.Team.PLAYER, dmg, self)
	Fx.sparks(fx_parent, muzzle, aim, 5, Bullet.PLAYER_COLOR)
	Audio.play("shot", -3.0)
	rig.kick()
	if state == State.GROUND:
		velocity.x -= aim.x * 40.0


func hurt_rect() -> Rect2:
	return Rect2(global_position + Vector2(-_rect.size.x * 0.5, -_rect.size.y), _rect.size)


func invulnerable() -> bool:
	return state == State.DASH or _iframes > 0.0


## 敌弹碰到机体时调用；返回 true 表示吃下这发（子弹消失）
func take_bullet(b: Node) -> bool:
	var T: Dictionary = Tuning.v
	if state == State.DASH:
		_try_perfect_dodge(T)
		return false
	if _iframes > 0.0:
		return false
	hurt(b.velocity.normalized(), b.damage)
	return true


## 被冲锋机撞到；冲刺中穿过去则可能触发精准闪避
func melee_hit(dir: Vector2, dmg: int) -> void:
	if state == State.DASH:
		_try_perfect_dodge(Tuning.v)
		return
	hurt(dir, dmg)


## 冲锋机撞上来时：正面朝着它、在出刀的前 60% 里，就算招架成功
func parry_ready(enemy_facing: int) -> bool:
	return slash_step >= 0 and facing == -enemy_facing and _slash_time <= slash_duration() * 0.6


## 正面砍中冲锋中的敌人 = 招架
func parried() -> void:
	var T: Dictionary = Tuning.v
	TimeFx.hitstop(T.hit_stop * 2.0)
	_overclock(T)


func _try_perfect_dodge(T: Dictionary) -> void:
	if not _perfect_used and T.dash_time - _dash_left <= T.perfect_window:
		_perfect_used = true
		_overclock(T)


func hurt(dir: Vector2, dmg: int) -> void:
	if invulnerable() or hp <= 0:
		return
	var T: Dictionary = Tuning.v
	hp -= dmg
	_iframes = T.iframes
	slash_step = -1
	if _rect.size == LOW and not _ceiling_blocked():
		_set_low(false)
	velocity = Vector2((signf(dir.x) if absf(dir.x) > 0.1 else -facing) * 220.0, -200.0)
	_set_state(State.AIR)
	Fx.sparks(fx_parent, global_position + CHEST, dir, 10, Color(1, 0.4, 0.4))
	Audio.play("hurt", -3.0)
	Music.duck(8.0, 0.4)
	impact.emit(5.0, dir)
	TimeFx.hitstop(0.08)
	if hp <= 0:
		died.emit()


func _overclock(T: Dictionary) -> void:
	TimeFx.slowmo(T.overclock_time, T.overclock_scale)
	overclock_charge = 2.5
	Audio.play("overclock", -1.0)
	impact.emit(2.0, Vector2.ZERO)
	overclocked.emit()


# ---------------------------------------------------------------- 表现

func _skidding() -> bool:
	var d := _dir_x()
	return state == State.GROUND and d != 0 and signf(velocity.x) != d and absf(velocity.x) > 110.0


func _update_facing() -> void:
	if state == State.WALL:
		facing = -_wall_dir
		return
	# 挥刀期间锁朝向：刀不会挥到一半转身
	if state == State.DASH or state == State.SLIDE or _wall_lock > 0.0 or _skidding() or slash_step >= 0:
		return
	var d := _dir_x()
	if d != 0:
		facing = d


func _animate(delta: float, T: Dictionary) -> void:
	_squash = _squash.lerp(Vector2.ONE, 1.0 - exp(-14.0 * delta))
	rig.scale = Vector2(facing * _squash.x, _squash.y)
	var ratio: float = absf(velocity.x) / T.run_speed
	var mode := "idle"
	match state:
		State.GROUND:
			if _skidding():
				mode = "skid"
				_skid_dust -= delta
				if _skid_dust <= 0.0:
					_skid_dust = 0.05
					Fx.dust(fx_parent, global_position + Vector2(facing * 10, 0), float(facing), 2)
			elif ratio > 0.05:
				mode = "run"
				var before := _run_phase
				_run_phase = fmod(_run_phase + absf(velocity.x) * delta / StriderRig.stride(ratio), 1.0)
				if (before < 0.5 and _run_phase >= 0.5) or _run_phase < before:
					_footstep(ratio)
		State.AIR:
			mode = "air"
		State.DASH:
			mode = "dash"
		State.SLIDE:
			mode = "slide"
		State.WALL:
			mode = "wall"
	rig.update({
		"state": mode,
		"facing": facing,
		"vel": velocity,
		"accel_x": (velocity.x - _prev_vx) / maxf(delta, 0.0001),
		"speed_ratio": ratio,
		"run_phase": _run_phase,
		"time": _idle_time,
		"land_squash": _land_squash,
		"slash_step": slash_step,
		"slash_t": clampf(_slash_time / slash_duration(), 0.0, 1.0) if slash_step >= 0 else 0.0,
		"slash_dir": rad_to_deg(Vector2(_slash_aim.x * facing, _slash_aim.y).angle()),
		"aim_local": Vector2(aim.x * facing, aim.y),
		"glow": 1.0 if state == State.DASH or overclock_charge > 0.0 else 0.0,
	}, delta)
	if slash_step >= 0:
		var pts := rig.blade_points()
		trail.add(pts[0], pts[1])
	# 受伤后无敌期间闪烁
	rig.visible = _iframes <= 0.0 or int(_iframes * 20.0) % 2 == 0
	# 高速时身边掠过速度线
	if absf(velocity.x) > T.run_speed * 0.9 or state == State.DASH:
		_streak_timer -= delta
		if _streak_timer <= 0.0:
			_streak_timer = 0.03
			Fx.streak(fx_parent, global_position + Vector2(signf(velocity.x) * randf_range(10.0, 60.0), randf_range(-55.0, 4.0)), signf(velocity.x), randf_range(24.0, 56.0))
	# 超过疾跑速度时留下淡淡的残影
	if state != State.DASH and absf(velocity.x) > T.run_speed * 1.15:
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = 0.045
			_spawn_ghost(0.25)


func _footstep(ratio: float) -> void:
	if ratio > 0.8:
		Fx.dust(fx_parent, global_position + Vector2(-facing * 3, 0), float(-facing), 1)


func _spawn_ghost(alpha: float) -> void:
	rig.spawn_ghost(fx_parent, alpha)


# ---------------------------------------------------------------- 工具

func _run_x(delta: float, accel: float, decel: float, turn: float, T: Dictionary) -> void:
	if _wall_lock > 0.0:
		return
	var dir := _dir_x()
	var top: float = T.run_speed
	var vx := velocity.x
	if dir == 0:
		vx = move_toward(vx, 0.0, decel * delta)
	elif signf(vx) == dir and absf(vx) > top:
		vx = move_toward(vx, dir * top, T.overspeed_decay * delta)
	else:
		var a := accel if (vx == 0.0 or signf(vx) == dir) else turn
		vx = move_toward(vx, dir * top, a * delta)
	velocity.x = vx


func _gravity(delta: float, max_fall: float, T: Dictionary) -> void:
	var g: float = T.gravity if velocity.y < 0.0 else T.fall_gravity
	if velocity.y < 0.0 and state == State.AIR and not input.jump_held and _cut_immune <= 0.0:
		g *= T.jump_cut_mult
	velocity.y = minf(velocity.y + g * delta, max_fall)


func _dir_x() -> int:
	if input.move.x > 0.3:
		return 1
	if input.move.x < -0.3:
		return -1
	return 0


## 左右 2 像素内有墙：返回 1（右）/ -1（左）/ 0
func touching_wall() -> int:
	if is_on_floor() and state != State.AIR and state != State.WALL:
		return 0
	if test_move(global_transform, Vector2(2, 0)):
		return 1
	if test_move(global_transform, Vector2(-2, 0)):
		return -1
	return 0


func _ceiling_blocked() -> bool:
	if _rect.size != LOW:
		return false
	return test_move(global_transform, Vector2(0, -(STAND.y - LOW.y)))


func _set_low(low: bool) -> void:
	_rect.size = LOW if low else STAND
	_shape.position = Vector2(0, -_rect.size.y * 0.5)


func _set_state(s: State) -> void:
	if s == state:
		return
	var old := state
	state = s
	state_changed.emit(old, s)
