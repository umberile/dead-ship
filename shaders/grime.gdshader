// Grime overlay. `mask` is painted by GrimeSurface as the player scrubs:
// 1.0 = caked in filth, 0.0 = bare metal showing through.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D mask : filter_linear, repeat_disable, hint_default_black;
uniform vec3 color_a : source_color = vec3(0.09, 0.075, 0.06);
uniform vec3 color_b : source_color = vec3(0.2, 0.16, 0.1);
uniform vec2 size_m = vec2(2.0, 2.0);
uniform float seed = 0.0;
uniform float fade = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 5.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * size_m;
	float m = texture(mask, UV).r;
	float n1 = fbm(p * 2.6 + seed);
	float n2 = fbm(p * 13.0 + seed * 1.7);
	// Thin grime breaks up into speckle before it disappears entirely.
	float thickness = m * (0.6 + 0.7 * n1);
	float a = smoothstep(0.04, 0.5, thickness);
	a *= 0.84 + 0.16 * n2;

	ALBEDO = mix(color_a, color_b, clamp(n1 * 0.7 + n2 * 0.5 - 0.1, 0.0, 1.0));
	ROUGHNESS = 0.93;
	METALLIC = 0.0;
	SPECULAR = 0.15;
	ALPHA = a * fade * 0.97;
}
