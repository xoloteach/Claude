// IRONLINE — cheap distant backdrop (city blocks, industrial silhouettes). Flat-ish lit colour from vertex
// colour, procedural lit windows on vertical faces (COLOR.a = window density), relies on scene fog for depth.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

uniform vec4 window_color : source_color = vec4(1.0, 0.72, 0.4, 1.0);
uniform float window_energy = 2.2;
uniform float floor_h = 3.4;
uniform float bay_w = 2.6;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	float vert = 1.0 - abs(n.y);
	if (COLOR.a > 0.01 && vert > 0.5) {
		float along = abs(n.x) > abs(n.z) ? wpos.z : wpos.x;
		vec2 cell = vec2(floor(along / bay_w), floor(wpos.y / floor_h));
		vec2 f = vec2(fract(along / bay_w), fract(wpos.y / floor_h));
		float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.3, f.y) * step(f.y, 0.8);
		float lit = step(1.0 - COLOR.a, hash(cell + floor(wpos.xz * 0.01)));
		float warm = hash(cell * 1.7 + 3.1);
		vec3 wc = mix(window_color.rgb, vec3(0.75, 0.85, 1.0), step(0.75, warm));
		ALBEDO = mix(ALBEDO, ALBEDO * 0.5, win);
		EMISSION = wc * win * lit * window_energy * (0.5 + warm * 0.8);
	}
}
