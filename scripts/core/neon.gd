class_name Neon
## 霓虹调色板。HDR 颜色（分量 >1）会被辉光放大、真正"亮起来"；
## 填充和描边这类不该发光的地方用普通颜色。青 = 玩家，红 = 敌人，白 = 可夺壳；洋红、琥珀只用于环境。

const CYAN := Color(0.3, 1.0, 1.0)
const CYAN_GLOW := Color(0.35, 1.5, 1.8)
const CYAN_HOT := Color(0.7, 2.4, 2.8)
const RED := Color(0.95, 0.22, 0.28)
const RED_GLOW := Color(1.9, 0.3, 0.38)
const RED_HOT := Color(3.0, 0.5, 0.6)
const WHITE_HOT := Color(2.6, 2.8, 3.0)
const MAGENTA := Color(2.0, 0.35, 1.7)
const AMBER := Color(2.2, 1.15, 0.3)

static var _light_tex: Texture2D
static var _streak_tex: Texture2D


## 点光源用的径向渐变贴图（中心亮、边缘透明）
static func light_texture() -> Texture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.45))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_light_tex = t
	return _light_tex


## 雨丝用的细长贴图
static func streak_texture() -> Texture2D:
	if _streak_tex == null:
		var img := Image.create(2, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			var a := float(y) / 15.0
			img.set_pixel(0, y, Color(1, 1, 1, a))
			img.set_pixel(1, y, Color(1, 1, 1, a * 0.5))
		_streak_tex = ImageTexture.create_from_image(img)
	return _streak_tex


## 角色、敌人、子弹、特效用光照层 2：不被点光源照到（否则自己把自己照成一团光）
const ACTOR_LIGHT_MASK := 2


## 挂一个点光源（只照亮光照层 1：地面、墙、背景）
## 像素美术里不用机体身上的点光源（它会在雨丝、积水上照出一个大光圈）；发光靠像素本身的高光色
static var lights_enabled := false


static func add_light(parent: Node2D, color: Color, energy: float, scale: float, offset := Vector2.ZERO) -> PointLight2D:
	var l := PointLight2D.new()
	l.enabled = lights_enabled
	l.texture = light_texture()
	l.color = color
	l.energy = energy
	l.texture_scale = scale
	l.position = offset
	l.range_item_cull_mask = 1
	parent.add_child(l)
	return l
