class_name Consciousness
extends Node
## R-0 的意识：决定当前控制哪具机体，负责软锁定、夺壳和紧急投射。
##   软锁定：离瞄准方向最近、够得着（360 像素）的目标挂准星；纯键盘瞄准时锥角放宽
##   夺壳：E 夺准星目标（220 像素内、在 possessable 组里）；继承 70% 速度；旧机体——基础机体跪下待机，敌人机体断电报废
##   紧急投射：被夺来的机体被打坏 → 弹出光球，1.5 秒内可以投射到附近任意机体；超时 → lost（回检查点）

signal shell_changed(shell: Node2D)
signal lost

const POSSESS_RANGE := 220.0
## 每次夺壳后的冷却（秒）；光球的紧急投射不受限制
const COOLDOWN := 0.7
const LOCK_RANGE := 360.0

var base: Player
var current: Node2D
var input: PlayerInput = DeviceInput.new()
var lock: Node2D
var lock_in_range := false
var cooldown := 0.0
var world: Node2D
var reticle: Reticle
## 正在飞的意识光流（镜头跟着它）
var flow: SoulFlow
## 意识负荷：附身在敌人壳里越久越烫，满了壳过载自爆（0..1）
var load_k := 0.0
var _load := 0.0
var _smoke_t := 0.0


func setup(base_shell: Player, world_node: Node2D) -> void:
	base = base_shell
	world = world_node
	current = base
	base.input = input
	reticle = Reticle.new()
	reticle.z_index = 9
	world.add_child(reticle)
	process_physics_priority = -10  # 先算锁定，再让机体用
	add_to_group("consciousness")


## 回到基础机体并放到 pos（重来、回检查点、测试都用它）
func return_to_base(pos: Vector2) -> void:
	if current != base and is_instance_valid(current):
		_detach(current)
		current.release_control()
	if base.parked:
		base.take_control(input, Vector2.ZERO)
	base.input = input
	base.reset_at(pos)
	_load = 0.0
	load_k = 0.0
	current = base
	lock = null
	cooldown = 0.0
	shell_changed.emit(base)


## 每种壳能撑多久（秒）：轻的久、重的短（附身强化定案）
static func load_time(shell: Node) -> float:
	if shell is HeavyBot:
		return 10.0
	if shell is DroneBot:
		return 20.0
	if shell is EnemyBot:
		return 20.0 if shell.kind == "gunner" and not shell.shielded else 15.0
	return 0.0


func _physics_process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	if not is_instance_valid(current):
		return
	_update_load(delta)
	if not is_instance_valid(current):
		return
	_update_lock()
	if "lock_target" in current:
		current.lock_target = lock
	reticle.target = lock
	reticle.in_range = lock_in_range
	reticle.origin_node = current
	reticle.cooldown_k = 0.0 if current is Wisp else cooldown / COOLDOWN
	if input.possess_pressed and cooldown > 0.0 and not (current is Wisp):
		reticle.deny()
		Audio.play("shield_block", -16.0, 1.8)
	elif input.possess_pressed:
		var t := _possess_target()
		if t != null:
			possess(t)
			return
		reticle.deny()
		Audio.play("shield_block", -14.0, 1.6)
	# 光球碰到任意机体就直接投射进去
	if current is Wisp:
		for n in get_tree().get_nodes_in_group("possessable"):
			if n.alive() and n.center().distance_to(current.global_position) < 16.0:
				possess(n)
				return


func _aim_dir() -> Vector2:
	var f: float = float(current.facing) if "facing" in current else 1.0
	if input.aim_keys or input.aim.length() < 0.1:
		return Vector2(f, 0)
	return input.aim.normalized()


## 当前的夺壳距离：站在意识中继旁边时放大到中继的范围
func reach() -> float:
	for r in get_tree().get_nodes_in_group("relay"):
		if r.covers(current):
			return Relay.RANGE
	return POSSESS_RANGE


func _update_lock() -> void:
	var origin: Vector2 = current.global_position + Vector2(0, -18)
	var possess_reach := reach()
	var lock_range := maxf(LOCK_RANGE, possess_reach + 40.0)
	var dir := _aim_dir()
	var cone := deg_to_rad(75.0 if input.aim_keys else 35.0)
	if current is Wisp:
		cone = PI  # 光球：附近哪个都行
	var best: Node2D = null
	var best_score := INF
	var prev_score := INF
	var seen := {}
	for group in ["hittable", "possessable"]:
		for n in get_tree().get_nodes_in_group(group):
			if n == current or seen.has(n) or not n.alive():
				continue
			seen[n] = true
			var to: Vector2 = n.center() - origin
			var d := to.length()
			if d > lock_range or not _visible(origin, n):
				continue
			var ang := absf(dir.angle_to(to)) if d > 1.0 else 0.0
			if ang > cone and d > 40.0:
				continue
			var score := d * (1.0 + 1.5 * ang)
			if n.is_in_group("possessable"):
				score *= 0.7  # 可夺的目标优先挂准星
			if n == lock:
				prev_score = score
			if score < best_score:
				best_score = score
				best = n
	# 迟滞：原来的目标只要不比最好的差太多就不换，准星不会来回跳
	if is_instance_valid(lock) and prev_score < INF and prev_score < best_score * 1.3:
		best = lock
	lock = best
	lock_in_range = lock != null and lock.is_in_group("possessable") and lock.center().distance_to(origin) <= possess_reach


## 墙后面的不锁定、不能夺
func _visible(origin: Vector2, n: Node2D) -> bool:
	var q := PhysicsRayQueryParameters2D.create(origin, n.center(), 1)
	return world.get_world_2d().direct_space_state.intersect_ray(q).is_empty()


## 按 E 时要夺的目标：准星目标可夺就是它；否则在可夺的里面另找一个（距离内、看得见、离瞄准方向近）
func _possess_target() -> Node2D:
	if lock_in_range:
		return lock
	var origin: Vector2 = current.global_position + Vector2(0, -18)
	var dir := _aim_dir()
	var best: Node2D = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group("possessable"):
		if n == current or not n.alive():
			continue
		var to: Vector2 = n.center() - origin
		if to.length() > reach() or not _visible(origin, n):
			continue
		var ang := absf(dir.angle_to(to)) if not (current is Wisp) else 0.0
		if ang > deg_to_rad(80.0):
			continue
		var score := to.length() * (1.0 + 1.5 * ang)
		if score < best_score:
			best_score = score
			best = n
	return best


func possess(target: Node2D) -> void:
	if not is_instance_valid(target) or target == current:
		return
	var old := current
	var from: Vector2 = old.global_position + Vector2(0, -16)
	var vel: Vector2 = old.velocity * 0.7 if "velocity" in old else Vector2.ZERO
	# 意识光流：时间放慢 0.2 秒，一团光沿弧线从旧壳流进新壳；到达时新壳醒来
	flow = SoulFlow.spawn(world, from, target)
	Fx.flash(world, from, Color(0.6, 1.8, 2.0), 10.0)
	Audio.play("possess", -2.0)
	TimeFx.slowmo(SoulFlow.DURATION, 0.35, "possess")
	get_tree().call_group("game", "shockwave", target.center())
	_detach(old)
	old.release_control()
	target.take_control(input, vel)
	# 新机体继承原来的朝向：夺过去之后还是面朝同一边，锁定和出手方向不会突然反过来
	if "facing" in old and "facing" in target:
		target.facing = old.facing
	if target != base and target.has_signal("died"):
		target.died.connect(_on_shell_died, CONNECT_ONE_SHOT)
	current = target
	lock = null
	cooldown = COOLDOWN
	_load = 0.0
	load_k = 0.0
	shell_changed.emit(target)


## 负荷：只在敌人壳里涨；快满时冒烟，满了过载
func _update_load(delta: float) -> void:
	var cap := load_time(current)
	if cap <= 0.0:
		_load = 0.0
		load_k = 0.0
		return
	_load += delta
	load_k = clampf(_load / cap, 0.0, 1.0)
	if load_k > 0.75:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.12 if load_k < 0.9 else 0.06
			Fx.dust(world, current.center() + Vector2(randf_range(-6, 6), -8), 0.0, 2)
			if load_k > 0.9:
				Fx.sparks(world, current.center(), Vector2.UP, 3, Color(2.6, 0.6, 0.5))
	if load_k >= 1.0:
		_overload()


## 过载：壳当场自爆（炸伤周围的敌人），意识光流弹出——2.5 秒内碰到哪个壳就夺哪个，超时自动飞回本体
func _overload() -> void:
	var shell := current
	var at: Vector2 = shell.center()
	Fx.flash(world, at, Color(2.8, 2.9, 3.0), 26.0)
	Fx.ring(world, at, 46.0)
	Fx.sparks(world, at, Vector2.UP, 24, Color(1.0, 2.2, 2.4))
	Fx.debris(world, at, Vector2.UP, 12, Color(0.3, 1.1, 1.25))
	Audio.play("break", 0.0, 0.8)
	get_tree().call_group("game", "shockwave", at)
	get_tree().call_group("game", "impact", 7.0, Vector2.ZERO)
	for n in get_tree().get_nodes_in_group("hittable"):
		if n == shell or (n.has_method("alive") and not n.alive()):
			continue
		var c: Vector2 = n.hurt_rect().get_center()
		if c.distance_to(at) < 72.0:
			n.take_hit((c - at).normalized(), 2, "slam")
	_detach(shell)
	shell.release_control()
	_load = 0.0
	load_k = 0.0
	var w := Wisp.new()
	w.position = at
	w.life = Wisp.BURNOUT_LIFE
	w.home = base
	world.add_child(w)
	w.take_control(input, Vector2(0, -180))
	current = w
	lock = null
	shell_changed.emit(w)


## 光球超时：飞回本体后自动回到本体
func return_home(w: Node2D) -> void:
	if current != w:
		return
	possess(base)


## 意识主动离开一具机体时，先断开它的"被打坏"信号——它接下来的断电报废不算被打坏
func _detach(shell: Node) -> void:
	if shell.has_signal("died") and shell.died.is_connected(_on_shell_died):
		shell.died.disconnect(_on_shell_died)


## 夺来的机体被打坏：弹出意识光球
func _on_shell_died(shell: Node) -> void:
	if shell != current:
		return
	var w := Wisp.new()
	w.position = shell.global_position + Vector2(0, -10)
	world.add_child(w)
	w.take_control(input, Vector2(0, -160))
	w.expired.connect(func(): lost.emit())
	current = w
	lock = null
	Audio.play("overclock", -6.0, 1.4)
	shell_changed.emit(w)
