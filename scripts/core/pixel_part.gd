class_name PixelPart
extends RefCounted
## 一个像素部件（tools/pixel 预生成的 RotSprite 图集：N 个角度横排，每格正方形，轴心在格子正中）。
## 画的时候不让引擎旋转贴图（那样会出锯齿和混合像素），而是取最接近的预旋转角度，位置取整，
## 镜像用 scale.x = -1（像素级精确）。

static var _cache := {}

var tex: Texture2D
var cell := 0
var pivot := Vector2i.ZERO
var angles := 32


static func get_part(path: String) -> PixelPart:
	if _cache.has(path):
		return _cache[path]
	var p := PixelPart.new()
	p.tex = load(path + ".png")
	var meta = JSON.parse_string(FileAccess.get_file_as_string(path + ".json"))
	p.cell = int(meta.cell)
	p.pivot = Vector2i(int(meta.pivot[0]), int(meta.pivot[1]))
	p.angles = int(meta.angles)
	_cache[path] = p
	return p


func index_for(angle: float) -> int:
	return posmod(int(round(angle / (TAU / angles))), angles)


## 画到 ci 上：base 是从"像素坐标系"到 ci 本地坐标的变换（骨架用它抵消自身的旋转 / 缩放，
## 让所有部件都在不旋转的世界像素格上画）；pos 是轴心在像素坐标系里的位置（会取整）；
## angle 是贴图自身的旋转（朝右为 0，顺时针为正）；flip = 旋转后再水平镜像（看起来的朝向是 PI - angle）；
## modulate 用于受击闪白、残影等整体调色
func draw(ci: CanvasItem, base: Transform2D, pos: Vector2, angle: float, flip := false, modulate := Color.WHITE) -> void:
	var i := index_for(angle)
	var t := base * Transform2D(0.0, Vector2(-1.0 if flip else 1.0, 1.0), 0.0, pos.round())
	ci.draw_set_transform_matrix(t)
	ci.draw_texture_rect_region(tex, Rect2(-Vector2(pivot), Vector2(cell, cell)), Rect2(i * cell, 0, cell, cell), modulate)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
