shader_type canvas_item;

// 油画后期：柔化边缘 + 画布纹理 + 色阶化 + 暗部提暖 + 暗角 + 颗粒
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette_strength = 0.42;
uniform float vignette_start = 0.30;
uniform float grain_amount = 0.045;
uniform vec3 shadow_tint = vec3(0.19, 0.14, 0.10);
uniform float warm_lift = 0.26;
uniform float contrast_boost = 1.12;
uniform float soften = 1.6;
uniform float canvas_strength = 0.05;
uniform float posterize_mix = 0.22;
uniform float aberration = 0.0009;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE * soften;

	// 轻微多点采样：把几何硬边揉软，模仿笔触的糊
	// 轻微色差：老镜头/油画罩染的边角泛色
	vec2 ca = (uv - 0.5) * aberration;
	vec3 c = vec3(
		texture(screen_tex, uv + ca).r,
		texture(screen_tex, uv).g,
		texture(screen_tex, uv - ca).b
	) * 0.36;
	c += texture(screen_tex, uv + vec2(px.x, 0.0)).rgb * 0.16;
	c += texture(screen_tex, uv - vec2(px.x, 0.0)).rgb * 0.16;
	c += texture(screen_tex, uv + vec2(0.0, px.y)).rgb * 0.16;
	c += texture(screen_tex, uv - vec2(0.0, px.y)).rgb * 0.16;

	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float shadow = 1.0 - smoothstep(0.0, 0.40, l);
	c = mix(c, shadow_tint + c * 0.62, shadow * warm_lift);

	c = (c - 0.5) * contrast_boost + 0.5;

	// 色阶化：把渐变压成几档，像颜料堆出来的块
	vec3 quantized = floor(c * 26.0) / 26.0;
	c = mix(c, quantized, posterize_mix);

	// 画布纹理
	float weave = sin(uv.x * 1500.0) * sin(uv.y * 1500.0);
	c *= 1.0 + weave * canvas_strength;

	// 暗角
	vec2 d = (uv - 0.5) * vec2(1.0, 0.82);
	float v = smoothstep(vignette_start, 0.78, length(d) * 1.5);
	c *= 1.0 - v * vignette_strength;

	// 颗粒
	float g = hash(uv * 1024.0 + vec2(TIME * 0.7));
	c += (g - 0.5) * grain_amount;

	COLOR = vec4(clamp(c, vec3(0.0), vec3(1.0)), 1.0);
}
