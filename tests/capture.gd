extends RefCounted
## 截图工具：读主窗口画面（HDR 2D 下是半精度浮点的线性颜色），每个原生像素取一个采样点，
## 用浮点精度转回 sRGB（先压成 8 位线性再转会让暗部只剩几阶、出现色偏和"光圈"），
## 再按最近邻放大成整数倍。窗口必须是 640×360 的整数倍（测试窗口是 1920×1080）。


static func native(main: Node, scale := 3) -> Image:
	var src: Image = main.get_tree().root.get_texture().get_image()
	src.convert(Image.FORMAT_RGBAF)
	var k := src.get_width() / 640
	var out := Image.create(640, 360, false, Image.FORMAT_RGBA8)
	for y in 360:
		for x in 640:
			var c := src.get_pixel(x * k + k / 2, y * k + k / 2)
			out.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0).clamp().linear_to_srgb())
	if scale > 1:
		out.resize(640 * scale, 360 * scale, Image.INTERPOLATE_NEAREST)
	return out
