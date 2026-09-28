// IRONLINE — harbour water (Compatibility-safe: no depth/screen textures).
// Two scrolling normal maps + a large-scale swell, fresnel toward a sky tint, sun glitter from the directional
// light (low roughness), analytic "shoreline" foam against the quay wall and the moored ship hull.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D tex_n1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_macro : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 deep_color : source_color = vec4(0.008, 0.025, 0.03, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.02, 0.05, 0.05, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.55, 0.42, 0.36, 1.0);
uniform vec4 foam_color : source_color = vec4(0.75, 0.72, 0.66, 1.0);
uniform float wave_scale = 0.11;
uniform float wave_speed = 0.02;
uniform float normal_strength = 0.28;
uniform float quay_x = -56.0;
uniform float ship_x = -61.0;
uniform float ship_z_min = -140.0;
uniform float ship_z_max = -18.0;
uniform float foam_width = 1.6;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 nsample(vec2 uv) {
	vec3 t = texture(tex_n1, uv).xyz * 2.0 - 1.0;
	return t;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = wpos.xz;
	vec3 n1 = nsample(p * wave_scale + vec2(t, t * 0.6));
	vec3 n2 = nsample(p * wave_scale * 2.7 + vec2(-t * 1.3, t * 0.9));
	vec3 n3 = nsample(p * wave_scale * 0.23 + vec2(t * 0.2, -t * 0.35));
	vec2 d = (n1.xy * 0.55 + n2.xy * 0.4 + n3.xy * 0.25);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float fade = 1.0 / (1.0 + dist * 0.004);
	d *= normal_strength * fade;
	vec3 wn = normalize(vec3(d.x, 1.0, d.y));

	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	float fres = pow(1.0 - clamp(dot(wn, V), 0.0, 1.0), 4.0);
	fres = mix(0.04, 1.0, fres);

	// distance to walls for foam and a lighter band of stirred water
	float dq = wpos.x - quay_x;
	float ds = 1e5;
	if (wpos.z > ship_z_min && wpos.z < ship_z_max) {
		ds = ship_x - wpos.x;
	}
	float dwall = min(abs(dq), abs(ds));
	float fn = texture(tex_macro, p * 0.35 + vec2(t * 3.0, -t * 2.0)).r;
	float fn2 = texture(tex_macro, p * 1.4 - vec2(t * 5.0, t * 4.0)).r;
	float foam = (1.0 - smoothstep(0.0, foam_width * (0.5 + fn), dwall)) * smoothstep(0.35, 0.65, fn2);
	float stir = 1.0 - smoothstep(0.0, 9.0, dwall);

	vec3 base = mix(deep_color.rgb, shallow_color.rgb, stir * 0.6);
	vec3 col = mix(base, sky_tint.rgb * 0.5, fres * 0.5);
	col = mix(col, foam_color.rgb, foam * 0.8);

	ALBEDO = col;
	ROUGHNESS = mix(0.035, 0.12, 1.0 - fade) + foam * 0.6;
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.2, foam);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
