shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.115, 0.13, 0.17, 1.0);
uniform vec4 glint_color : source_color = vec4(0.22, 0.22, 0.27, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.92;

void fragment() {
	float a = sin(UV.x * 44.0 + UV.y * 19.0 + TIME * 0.36);
	float b = sin(UV.x * 17.0 - UV.y * 31.0 - TIME * 0.23);
	float glint = smoothstep(0.8, 1.7, a + b) * 0.24;
	ALBEDO = mix(deep_color.rgb, glint_color.rgb, glint);
	ROUGHNESS = 0.26;
	SPECULAR = 0.52;
	METALLIC = 0.05;
	ALPHA = opacity;
}
