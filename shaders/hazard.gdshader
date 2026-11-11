// Worn hazard striping, projected in world space.
shader_type spatial;

uniform vec3 color_a : source_color = vec3(0.85, 0.62, 0.08);
uniform vec3 color_b : source_color = vec3(0.05, 0.05, 0.05);
uniform float stripe_width = 0.16;
uniform float wear : hint_range(0.0, 1.0) = 0.55;

varying vec3 w_pos;
varying vec3 w_nrm;

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

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(w_nrm);
	vec2 uv;
	if (an.y > an.x && an.y > an.z) {
		uv = w_pos.xz;
	} else if (an.x > an.z) {
		uv = w_pos.zy;
	} else {
		uv = w_pos.xy;
	}
	float s = fract((uv.x + uv.y) / (stripe_width * 2.0));
	float stripe = smoothstep(0.48, 0.52, s) * (1.0 - smoothstep(0.98, 1.0, s)) + (1.0 - smoothstep(0.0, 0.02, s));
	vec3 col = mix(color_a, color_b, clamp(stripe, 0.0, 1.0));
	float n = vnoise(uv * 9.0) * 0.6 + vnoise(uv * 31.0) * 0.4;
	float chipped = smoothstep(1.0 - wear * 0.55, 1.0, n);
	col = mix(col, vec3(0.2, 0.21, 0.22), chipped);
	col *= 0.8 + 0.3 * n;
	ALBEDO = col;
	METALLIC = mix(0.1, 0.7, chipped);
	ROUGHNESS = mix(0.75, 0.45, chipped);
}
