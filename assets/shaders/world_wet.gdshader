// IRONLINE — lit, alpha-blended ground decal: puddles (dark, glossy, sky reflection), dirt/gravel patches
// (textured), dust. UV 0..1 over the quad, COLOR = tint (a = opacity), noisy round edge.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_macro : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float use_tex = 0.0;
uniform float tex_scale = 0.4;
uniform float roughness = 0.08;
uniform float specular = 0.6;
uniform float normal_flat = 0.9;
uniform float edge_noise = 0.6;
uniform float ripple = 0.0;
uniform float pull = 0.0014;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= (1.0 - pull);
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float nz = texture(tex_macro, wpos.xz * 0.35).r;
	float nz2 = texture(tex_macro, wpos.xz * 1.3).r;
	float d = length(q) + (nz - 0.5) * edge_noise + (nz2 - 0.5) * 0.15;
	float a = 1.0 - smoothstep(0.55, 1.0, d);
	if (a * COLOR.a < 0.02) discard;
	vec3 col = COLOR.rgb;
	vec3 tn = vec3(0.0, 0.0, 1.0);
	if (use_tex > 0.5) {
		col *= texture(tex_albedo, wpos.xz * tex_scale).rgb;
		tn = texture(tex_normal, wpos.xz * tex_scale).xyz * 2.0 - 1.0;
	} else {
		tn = texture(tex_normal, wpos.xz * 0.3).xyz * 2.0 - 1.0;
		tn.xy *= (1.0 - normal_flat);
		if (ripple > 0.0) {
			vec2 r1 = texture(tex_macro, wpos.xz * 2.1 + vec2(TIME * 0.03, TIME * 0.021)).rg;
			tn.xy += (r1 - 0.5) * ripple;
		}
	}
	ALBEDO = col;
	ALPHA = a * COLOR.a;
	float edge = smoothstep(0.35, 0.8, a);
	ROUGHNESS = mix(roughness, 0.85, 1.0 - edge);
	SPECULAR = specular;
	vec3 wn = normalize(vec3(tn.x, 1.0, -tn.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
