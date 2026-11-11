// Procedural hull plating. Projected in world space so every box in the ship
// shares one continuous panel grid without needing UV work.
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.4, 0.42, 0.44);
uniform vec2 panel_size = vec2(1.0, 1.0);
uniform float seam_width = 0.012;
uniform float wear : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.55;
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
uniform float tint_variation : hint_range(0.0, 0.5) = 0.08;
uniform float rivets : hint_range(0.0, 1.0) = 1.0;

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
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
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

	vec2 g = uv / panel_size;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	vec2 d = min(f, 1.0 - f) * panel_size;
	float seam_d = min(d.x, d.y);
	float seam = 1.0 - smoothstep(seam_width * 0.5, seam_width, seam_d);
	float bevel = 1.0 - smoothstep(seam_width, seam_width * 5.0, seam_d);

	// Rivets near panel corners.
	vec2 rd = d - vec2(0.06);
	float rivet = (1.0 - smoothstep(0.012, 0.018, length(rd))) * rivets;

	float n = fbm(uv * 2.7);
	float streak = vnoise(vec2(uv.x * 46.0, uv.y * 1.6)) * vnoise(uv * 5.0);
	float tint = (hash21(cell) - 0.5) * tint_variation * 2.0;

	vec3 col = base_color * (1.0 + tint);
	col *= mix(1.0, 0.72 + 0.56 * n, wear);
	col = mix(col, col * 1.35 + 0.03, streak * wear * 0.35);
	col *= 1.0 - bevel * 0.18;
	col = mix(col, col * 0.2, seam);
	col = mix(col, col * 1.25 + 0.02, rivet);

	ALBEDO = col;
	METALLIC = metallic;
	ROUGHNESS = clamp(roughness + (n - 0.5) * 0.35 * wear + seam * 0.3 - streak * 0.15 * wear, 0.08, 1.0);
}
