// Hull breach overlay: a ragged hole to open space ringed by scorched metal.
// `sectors` holds how far the sealant has closed in from the rim, per angular
// slice, so the player has to work their way around the wound.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

const int SECTORS = 12;

uniform float sectors[12];
uniform float heat = 0.0;
uniform float seed = 3.0;
uniform vec3 sealant_color : source_color = vec3(0.55, 0.5, 0.42);
uniform vec3 hot_color : source_color = vec3(1.0, 0.45, 0.08);

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

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	vec2 dir = vec2(cos(ang), sin(ang));

	// Ragged rim.
	float rim = 0.52 + 0.13 * vnoise(dir * 2.3 + seed) + 0.05 * vnoise(dir * 9.0 + seed * 2.0);
	float hole = 1.0 - smoothstep(rim - 0.015, rim + 0.015, r);
	float scorch = (1.0 - smoothstep(rim, 1.0, r)) * (0.75 + 0.25 * vnoise(p * 7.0 + seed));

	// Per-sector seal amount, interpolated around the circle.
	float fa = (ang / TAU + 0.5) * float(SECTORS);
	int i0 = int(floor(fa)) % SECTORS;
	int i1 = (i0 + 1) % SECTORS;
	float s = mix(sectors[i0], sectors[i1], smoothstep(0.0, 1.0, fract(fa)));

	float front = rim * (1.0 - s) + 0.03 * (vnoise(p * 11.0 + seed) - 0.5) * (1.0 - s);
	float sealed = hole * smoothstep(front - 0.02, front + 0.02, r);
	float open = hole * (1.0 - sealed);

	// Open space: black with a scatter of stars.
	vec2 sp = p * 34.0 + seed;
	float star = step(0.985, hash21(floor(sp))) * smoothstep(0.35, 0.0, length(fract(sp) - 0.5));
	vec3 space = vec3(0.004, 0.006, 0.012) + vec3(0.8, 0.88, 1.0) * star;

	// Cured sealant: lumpy and matte.
	float lump = vnoise(p * 9.0 + seed * 3.0) * 0.6 + vnoise(p * 23.0) * 0.4;
	vec3 seal_col = sealant_color * (0.7 + 0.5 * lump);

	vec3 scorch_col = vec3(0.015, 0.013, 0.012);
	vec3 col = mix(scorch_col, seal_col, sealed);
	col = mix(col, vec3(0.0), open);

	float glow = heat * hole * exp(-abs(r - front) * 16.0) * step(0.001, s) * step(s, 0.999);
	glow += heat * sealed * 0.12;

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.8, sealed);
	METALLIC = 0.0;
	SPECULAR = 0.1;
	EMISSION = space * open * 1.4 + hot_color * glow * 3.0;
	ALPHA = clamp(max(hole, scorch * 0.92), 0.0, 1.0);
}
