class_name StreetSet
extends Node2D
## 第十三街的正式像素场景（tools/pixel/build_street.py 生成的资源）：
##   L0 夜空渐变 → L1 远景天际线（视差 0.15）→ L2 中景楼体（0.4）→ L3 近景墙（0.8）
##   → L4 游戏层地图块（按地形自动选：厚的是湿混凝土、1 格高的是钢格栅、窄高的是钢板墙）+ 道具
##   → L5 前景暗剪影（1.25）
## 由 Region 在 _ready 里创建。碰撞仍由 Blocks 负责，这里只管画。

const TILE := 16
const BG := "res://assets/bg/"
const PROPS := "res://assets/props/"

var region: Node


static func build(r: Node) -> StreetSet:
	var s := StreetSet.new()
	s.region = r
	s.z_index = -1
	r.add_child(s)
	r.move_child(s, 0)
	return s


func _ready() -> void:
	var lim: Rect2 = region.limits()
	_sky(lim)
	# 各层底边对齐地面（y = 0）附近；越远的层底边越高一点（地平线透视）
	_layer("street_far.png", Vector2(0.15, 0.15), -30.0, -90)
	_layer("street_mid.png", Vector2(0.4, 0.4), -10.0, -80)
	_layer("street_near.png", Vector2(0.8, 0.8), 6.0, -70)
	_tiles()
	_props()
	_decor()
	_puddles()
	_foreground()


## L0：夜空——从顶部的夜空蓝渐变到地平线的雾
func _sky(lim: Rect2) -> void:
	var p := Parallax2D.new()
	p.scroll_scale = Vector2.ZERO
	p.z_index = -100
	var g := Gradient.new()
	g.set_color(0, Color8(5, 8, 14))
	g.set_color(1, Color8(16, 30, 46))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = false
	# 贴着屏幕（scroll 0）：铺满 640×360 再多出一圈
	sp.scale = Vector2(700.0 / 4.0, 420.0 / 64.0)
	sp.position = Vector2(-30, -30)
	sp.light_mask = 0
	p.add_child(sp)
	add_child(p)


## bottom：这一层贴图底边在世界里的高度
func _layer(file: String, scroll: Vector2, bottom: float, z: int) -> void:
	var tex: Texture2D = load(BG + file)
	var p := Parallax2D.new()
	p.scroll_scale = scroll
	p.repeat_size = Vector2(tex.get_width(), 0)
	p.repeat_times = 4
	p.z_index = z
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = false
	# Parallax2D 按屏幕左上角计算偏移：镜头平时在地面上方约 220 像素处，补回 (1 - scroll) × 220，
	# 让这一层在常规镜头高度下底边正好落在 bottom
	sp.position = Vector2(0, bottom - tex.get_height() + (1.0 - scroll.y) * 236.0)
	sp.light_mask = 0  # 背景不受机体身上的点光源影响
	p.add_child(sp)
	add_child(p)


# ---------------------------------------------------------------- 地图块

func _solid(c: int, r: int) -> bool:
	return region.char_at(Vector2(c * TILE + 1, r * TILE + 1)) == "#"


func _tiles() -> void:
	var meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles/street/tiles.json"))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src := TileSetAtlasSource.new()
	src.texture = load("res://assets/tiles/street/tiles.png")
	src.texture_region_size = Vector2i(TILE, TILE)
	var ids := {}
	for k in meta.map:
		var at := Vector2i(int(meta.map[k][0]), int(meta.map[k][1]))
		src.create_tile(at)
		ids[k] = at
	ts.add_source(src, 0)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	layer.light_mask = 0
	add_child(layer)
	var lim: Rect2 = region.limits()
	var c0 := int(floor(lim.position.x / TILE))
	var c1 := int(ceil(lim.end.x / TILE))
	var r0 := int(floor(lim.position.y / TILE))
	var r1 := int(ceil(lim.end.y / TILE))
	for r in range(r0, r1):
		for c in range(c0, c1):
			if not _solid(c, r):
				continue
			layer.set_cell(Vector2i(c, r), 0, ids[_pick(c, r)])


func _pick(c: int, r: int) -> String:
	var up := _solid(c, r - 1)
	var down := _solid(c, r + 1)
	var left := _solid(c - 1, r)
	var right := _solid(c + 1, r)
	var h := hash(Vector2i(c, r))
	# 1 格高：钢格栅平台
	if not up and not down:
		return "grate%d" % (h % 2)
	# 窄高：钢板墙
	var run := 1
	while run < 6 and _solid(c - run, r):
		run += 1
	var run_r := 1
	while run_r < 6 and _solid(c + run_r, r):
		run_r += 1
	if run + run_r - 1 <= 4 and (up or down):
		return "steel_top" if not up else "steel%d" % (h % 2)
	if not up:
		if not left:
			return "con_tl"
		if not right:
			return "con_tr"
		return "con_top%d" % (h % 3)
	if not down:
		return "con_bot"
	if not left:
		return "con_l"
	if not right:
		return "con_r"
	var depth := 0
	while depth < 4 and _solid(c, r - depth - 1):
		depth += 1
	if depth >= 4:
		return "con_deep"
	return "con_in%d" % (h % 3)


# ---------------------------------------------------------------- 道具

func _sprite(file: String, pos: Vector2, z := 0, flip := false) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = load(PROPS + file)
	sp.centered = false
	sp.offset = Vector2(-sp.texture.get_width() * 0.5, -sp.texture.get_height())
	sp.position = pos.round()
	sp.flip_h = flip
	sp.z_index = z
	sp.light_mask = 0
	add_child(sp)
	return sp


## 地面顶面的列：每段连续地面上隔一段放路灯、空调外机、灯牌
func _props() -> void:
	var lim: Rect2 = region.limits()
	var c0 := int(floor(lim.position.x / TILE)) + 2
	var c1 := int(ceil(lim.end.x / TILE)) - 2
	var last_lamp := -999
	var n := 0
	for c in range(c0, c1):
		# 找这一列的地面顶面（从上往下第一块实心，且上面 4 格是空的）
		var top := _ground_row(c)
		if top == -999:
			continue
		var y := float(top * TILE)
		var h := hash(c * 7919)
		if c - last_lamp >= 22 and h % 5 == 0:
			last_lamp = c
			var lamp := _sprite("lamp.png", Vector2(c * TILE + 8, y), -2)
			_light_cone(Vector2(c * TILE + 8 + 7, y - 62), y)
			n += 1
		elif h % 37 == 3:
			_sprite("ac.png", Vector2(c * TILE + 8, y - 40 - (h % 3) * 12), -3)
		elif h % 41 == 5:
			_sprite("sign%d.png" % (h % 3), Vector2(c * TILE + 8, y - 54 - (h % 4) * 8), -3)
		elif h % 53 == 7:
			_fan(Vector2(c * TILE + 8, y - 30))


func _ground_row(c: int) -> int:
	var lim: Rect2 = region.limits()
	var r0 := int(floor(lim.position.y / TILE))
	var r1 := int(ceil(lim.end.y / TILE))
	for r in range(r0 + 4, r1):
		if _solid(c, r) and not _solid(c, r - 1) and not _solid(c, r - 2) and not _solid(c, r - 3) and not _solid(c, r - 4):
			# 只要宽的地面（左右都有实心），薄平台上不放
			if _solid(c, r + 1) and _solid(c - 1, r) and _solid(c + 1, r):
				return r
	return -999


## 路灯的光锥：抖动点阵的暖黄三角，叠加混合；地面上一小块光斑
func _light_cone(at: Vector2, floor_y: float) -> void:
	var cone := LightCone.new()
	cone.position = at.round()
	cone.height = floor_y - at.y
	cone.z_index = -1
	add_child(cone)


func _fan(at: Vector2) -> void:
	var f := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.add_animation("spin")
	for i in 4:
		frames.add_frame("spin", load(PROPS + "fan%d.png" % i))
	frames.set_animation_speed("spin", 12.0)
	f.sprite_frames = frames
	f.animation = "spin"
	f.position = at.round()
	f.z_index = -3
	f.play("spin")
	add_child(f)


## 地图里指定的装饰：检查站岗亭、闸门栏杆、路灯
func _decor() -> void:
	for d in region.decor:
		var pos: Vector2 = d[1]
		match d[0]:
			"B":
				_sprite("booth.png", pos, -2)
				# 岗亭顶上的红色警示灯：慢闪
				var beacon := Beacon.new()
				beacon.position = (pos + Vector2(0, -54)).round()
				beacon.z_index = -1
				add_child(beacon)
			"G":
				_sprite("gate.png", pos + Vector2(30, 0), -2)
			"L":
				_sprite("lamp.png", pos, -2)
				_light_cone(pos + Vector2(7, -62), pos.y)


## L5 前景：比游戏层移动得更快的暗剪影（钢柱、垂下的电缆），稀疏、很暗，不挡判定
func _foreground() -> void:
	var p := Parallax2D.new()
	p.scroll_scale = Vector2(1.25, 1.0)
	p.repeat_size = Vector2(900, 0)
	p.repeat_times = 3
	p.z_index = 40
	var fg := ForegroundStrip.new()
	fg.light_mask = 0
	p.add_child(fg)
	add_child(p)


class ForegroundStrip extends Node2D:
	func _draw() -> void:
		var dark := Color(0.012, 0.014, 0.02)
		var edge := Color(0.05, 0.06, 0.08)
		# 两根钢柱（900 像素一个循环）
		# （通天的前景立柱去掉了：没有细节的纯黑竖条看起来像渲染故障；只保留下垂电缆）
		# 下垂电缆：一像素宽的弧
		for seg in [[0.0, 300.0, -260.0, 40.0], [430.0, 900.0, -250.0, 55.0]]:
			var x0: float = seg[0]
			var x1: float = seg[1]
			for xi in range(int(x0), int(x1)):
				var t := (xi - x0) / (x1 - x0)
				var y: float = seg[2] + seg[3] * 4.0 * t * (1.0 - t)
				draw_rect(Rect2(xi, round(y), 1, 1), dark)


class Beacon extends Node2D:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var on := fmod(_t, 1.2) < 0.6
		if on:
			draw_rect(Rect2(-1, -1, 3, 2), Color(2.0, 0.35, 0.4))


## 积水：沿宽地面的顶面隔一段铺一块，倒影画在地面线以下
func _puddles() -> void:
	var lim: Rect2 = region.limits()
	var c := int(floor(lim.position.x / TILE)) + 2
	var c1 := int(ceil(lim.end.x / TILE)) - 2
	while c < c1:
		var top := _ground_row(c)
		var h := hash(c * 104729)
		if top != -999 and h % 3 == 0:
			var w := 2 + h % 4
			var ok := true
			for k in w:
				if _ground_row(c + k) != top:
					ok = false
			if ok:
				var p := Puddle.new()
				p.position = Vector2(c * TILE, top * TILE)
				p.width = w * TILE
				add_child(p)
				c += w + 4
				continue
		c += 3


class Puddle extends Node2D:
	const SHADER := preload("res://shaders/puddle.gdshader")
	var width := 48.0
	var depth := 28.0
	var _mat: ShaderMaterial

	func _ready() -> void:
		z_index = 2
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.set_shader_parameter("depth_px", depth)
		material = _mat

	func _process(_delta: float) -> void:
		_mat.set_shader_parameter("time", Time.get_ticks_msec() * 0.001)

	func _draw() -> void:
		# 水面形状：两端收窄的扁平块（像素边），顶上 1 像素亮线是水面高光
		for y in int(depth):
			var inset := int(round(absf(float(y) - 2.0) * 0.0)) + (3 if y < 2 else 0)
			draw_rect(Rect2(inset, y + 1, width - inset * 2, 1), Color.WHITE)
		draw_rect(Rect2(6, 0, width - 12, 1), Color(0.7, 0.85, 1.0, 0.35))


class LightCone extends Node2D:
	var height := 60.0

	func _ready() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m

	func _draw() -> void:
		# 光锥：两层半透明的实心梯形（外层淡、内层稍亮），像素边缘不抗锯齿；地面上一块椭圆光斑
		var h := height
		draw_colored_polygon(PackedVector2Array([Vector2(-3, 0), Vector2(3, 0), Vector2(h * 0.36, h), Vector2(-h * 0.36, h)]), Color(1.0, 0.75, 0.38, 0.006))
		draw_colored_polygon(PackedVector2Array([Vector2(-2, 0), Vector2(2, 0), Vector2(h * 0.18, h), Vector2(-h * 0.18, h)]), Color(1.0, 0.8, 0.45, 0.008))
		for i in 3:
			var w := h * (0.42 - i * 0.12)
			draw_rect(Rect2(-w, h - 1 - i, w * 2, 1), Color(1.0, 0.8, 0.45, 0.02 + 0.012 * i))
