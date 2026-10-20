shader_type canvas_item;
// 积水倒影：把水面线以上的画面上下翻转画到水面线以下，越往下越淡、越暗、带一点横向水波。
// 水面线 = 这个节点本地 y = 0 的那一行，在顶点阶段换算成屏幕像素，传给片元。
// 在 640×360 原生像素视口里采样，倒影本身也是像素的。

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float depth_px = 28.0;
uniform float time = 0.0;
uniform vec4 tint : source_color = vec4(0.45, 0.62, 0.85, 1.0);

varying float surface_px;

void vertex() {
	surface_px = (CANVAS_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).y;
}

void fragment() {
	float d = FRAGCOORD.y - surface_px;                 // 离水面多深（像素）
	float k = clamp(d / depth_px, 0.0, 1.0);            // 0 = 水面，1 = 最深
	// 横向水波：按行整数像素偏移，保持像素感
	float wave = floor(sin(FRAGCOORD.y * 0.9 + time * 3.0) * 1.2 + 0.5);
	vec2 src = vec2(FRAGCOORD.x + wave * k * 2.0, surface_px - d * 1.15);
	vec3 c = texture(screen_tex, src * SCREEN_PIXEL_SIZE).rgb;
	float a = (1.0 - k) * 0.8 * texture(TEXTURE, UV).a;
	// 深处一半像素的倒影只留 40%（像素风的半透明抖动）
	vec2 cell = floor(FRAGCOORD.xy);
	if (k > 0.5 && mod(cell.x + cell.y, 2.0) > 0.5) {
		a *= 0.4;
	}
	COLOR = vec4(c * tint.rgb * 1.3, a);
}
