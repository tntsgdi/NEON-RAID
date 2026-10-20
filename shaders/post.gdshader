shader_type canvas_item;
// 屏幕后处理：重击/超频时的色差、招架/弹反/打碎时的冲击波扭曲、暗角。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float ca = 0.0;               // 色差强度（像素）
uniform vec2 shock_center = vec2(0.5);
uniform float shock_t = 1.0;          // 冲击波进度 0..1，>=1 关闭
uniform float vignette = 0.22;
uniform float aspect = 1.7778;
uniform float speed_blur = 0.0;       // 疾驰时屏幕左右边缘的横向模糊（0..1）

void fragment() {
	vec2 uv = SCREEN_UV;
	if (shock_t < 1.0) {
		vec2 d = (uv - shock_center) * vec2(aspect, 1.0);
		float dist = length(d);
		float r = shock_t * 0.45;
		float k = smoothstep(0.07, 0.0, abs(dist - r)) * (1.0 - shock_t);
		uv -= normalize(d + vec2(1e-5)) / vec2(aspect, 1.0) * k * 0.025;
	}
	vec2 dir = normalize(uv - vec2(0.5) + vec2(1e-5));
	vec2 off = dir * ca * SCREEN_PIXEL_SIZE * (0.4 + length(uv - vec2(0.5)) * 1.6);
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;
	if (speed_blur > 0.01) {
		float edge = smoothstep(0.22, 0.5, abs(uv.x - 0.5)) * speed_blur;
		vec3 acc = col;
		for (int i = 1; i <= 4; i++) {
			acc += texture(screen_tex, uv + vec2(float(i) * edge * SCREEN_PIXEL_SIZE.x * 7.0, 0.0)).rgb;
		}
		col = acc / 5.0;
	}
	float v = length((uv - vec2(0.5)) * vec2(aspect, 1.0)) / 1.25;
	col *= 1.0 - vignette * smoothstep(0.2, 1.15, v);
	COLOR = vec4(col, 1.0);
}
