shader_type spatial;

uniform sampler2D worn_stone : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool graybox = false;
varying vec2 floor_pos;

void vertex() {
	floor_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

// How wide one screen pixel is in world metres. Every hairline below is floored by it:
// a line narrower than a pixel then widens and fades instead of blinking on and off
// as the camera creeps a fraction of a pixel (the 1.2 cm brass inlay did exactly that).
float footprint(vec2 p) {
	return max(max(fwidth(p.x), fwidth(p.y)), 0.00001);
}

// A line of half-width `width` centred on |x| = 0. Once the footprint passes the line width
// the mask is scaled by width / w, so the ink keeps its total energy: at the design camera
// this is untouched, at a distance or a grazing angle it dissolves into the stone instead of
// smearing into a fat band.
float band(float x, float width, float foot) {
	float w = max(width, foot * 0.75);
	float aa = max(fwidth(x), foot * 0.6);
	float mask = 1.0 - smoothstep(w - aa, w + aa, abs(x));
	return mask * (width / w);
}

void fragment() {
	vec2 p = floor_pos;
	float foot = footprint(p);

	float row = floor(p.y / 1.05);
	vec2 brick = vec2(p.x / 1.8 + mod(row, 2.0) * 0.5, p.y / 1.05);
	vec2 grid = min(fract(brick), 1.0 - fract(brick)) * vec2(1.8, 1.05);
	// Mortar joints: the ramp grows to at least a pixel and the darkening fades in proportion,
	// so a far floor reads as plain stone instead of a crawling grid of dark lines.
	float edge = min(grid.x, grid.y);
	float ramp = max(0.026, foot * 1.2);
	float joint = smoothstep(0.004, ramp, edge);
	joint = mix(1.0, joint, min(0.026 / ramp, 1.0));
	float variation = fract(sin(dot(floor(brick), vec2(78.3, 27.1))) * 1735.2);
	float grain = dot(texture(worn_stone, p * 0.42).rgb, vec3(0.3, 0.55, 0.15));
	vec3 stone = mix(vec3(0.21, 0.23, 0.23), vec3(0.43, 0.40, 0.33), variation * 0.7 + 0.13);
	stone *= 0.87 + 0.70 * grain;
	float side = abs(p.y - 0.35);
	vec3 color = stone * mix(0.48, 1.0, joint);
	if (!graybox) {
		// Dark serpentine and aged brass inset into the limestone processional way.
		float edging = band(side - 1.17, 0.15, foot);
		color = mix(color, vec3(0.065, 0.095, 0.096), edging * 0.9);
		float brass = max(band(side - 1.045, 0.016, foot), band(side - 1.295, 0.018, foot));
		vec2 repeat_pos = vec2(mod(p.x + 0.3, 0.6) - 0.3, side - 1.17);
		brass = max(brass, band(abs(repeat_pos.x) * 0.55 + abs(repeat_pos.y) - 0.079, 0.012, foot));
		vec2 seal = p - vec2(3.6, 0.35);
		float r = length(seal);
		float rings = max(band(r - 0.81, 0.020, foot), band(r - 0.9, 0.012, foot));
		float a = atan(seal.y, seal.x);
		float star = 0.60 * (0.27 + 0.73 * pow(abs(cos(a * 4.0)), 4.0));
		brass = max(brass, max(rings, band(r - star, 0.021, foot)));
		color = mix(color, vec3(0.48, 0.31, 0.13), brass);
		// Pools of window colour break up the arcades along the walk.
		vec2 glass = vec2(mod(p.x - p.y * 0.48 + 2.1, 4.2) - 2.1, p.y + 2.0);
		float wash = exp(-glass.x * glass.x * 0.95 - glass.y * glass.y * 0.15);
		float tracery = abs(fract((glass.x + 0.2 * glass.y) * 1.75) - 0.5);
		float panes = smoothstep(0.018, 0.095, tracery);
		float hue = 0.5 + 0.5 * sin(glass.x * 3.8);
		color += wash * mix(vec3(0.024, 0.07, 0.084), vec3(0.15, 0.06, 0.028), hue) * panes;
		// The walkable hall sits between cooler outer galleries.
		color *= mix(1.0, 0.47, smoothstep(4.7, 6.3, abs(p.y)));
	}
	ALBEDO = color;
	ROUGHNESS = 0.84;
}
