// IRONLINE — world surface shader (Compatibility-safe).
// World-space triplanar PBR with: macro variation (breaks tiling), vertex-colour tint, fake contact AO and
// grime near the ground (or per container stack level), rust streaks from top edges, interior darkening.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_ao : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_macro : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 tint : source_color = vec4(1.0);
uniform float scale = 0.5;
uniform float normal_strength = 1.0;
uniform float rough_mul = 1.0;
uniform float rough_add = 0.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform float macro_strength = 0.22;
uniform float ground_ao = 0.5;
uniform float ground_ao_height = 0.8;
uniform float grime = 0.35;
uniform vec4 grime_color : source_color = vec4(0.23, 0.2, 0.16, 1.0);
uniform float grime_height = 1.1;
uniform float stack_h = 0.0;
uniform float streaks = 0.0;
uniform vec4 streak_color : source_color = vec4(0.32, 0.17, 0.08, 1.0);
uniform float use_vcolor = 1.0;
uniform float blend_sharp = 5.0;
uniform float ao_light_affect = 0.5;
uniform float emission_from_vcolor_alpha = 0.0;
uniform vec4 emission_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform float emission_energy = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack_n(vec4 t) {
	vec3 n = t.xyz * 2.0 - 1.0;
	n.xy *= normal_strength;
	return n;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(blend_sharp));
	w /= (w.x + w.y + w.z);
	vec3 p = wpos * scale;
	vec2 uvx = vec2(p.z, -p.y);
	vec2 uvy = vec2(p.x, p.z);
	vec2 uvz = vec2(p.x, -p.y);

	vec3 alb = vec3(0.0);
	float rough = 0.0;
	float ao = 0.0;
	vec3 wn = vec3(0.0);
	if (w.x > 0.02) {
		alb += texture(tex_albedo, uvx).rgb * w.x;
		rough += texture(tex_rough, uvx).g * w.x;
		ao += texture(tex_ao, uvx).g * w.x;
		vec3 t = unpack_n(texture(tex_normal, uvx));
		vec3 a = vec3(t.x + n.z, t.y + n.y, abs(t.z) * n.x);
		wn += a.zyx * w.x;
	}
	if (w.y > 0.02) {
		alb += texture(tex_albedo, uvy).rgb * w.y;
		rough += texture(tex_rough, uvy).g * w.y;
		ao += texture(tex_ao, uvy).g * w.y;
		vec3 t = unpack_n(texture(tex_normal, uvy));
		t.y = -t.y;
		vec3 a = vec3(t.x + n.x, t.y + n.z, abs(t.z) * n.y);
		wn += a.xzy * w.y;
	}
	if (w.z > 0.02) {
		alb += texture(tex_albedo, uvz).rgb * w.z;
		rough += texture(tex_rough, uvz).g * w.z;
		ao += texture(tex_ao, uvz).g * w.z;
		vec3 t = unpack_n(texture(tex_normal, uvz));
		vec3 a = vec3(t.x + n.x, t.y + n.y, abs(t.z) * n.z);
		wn += a * w.z;
	}
	float wsum = (w.x > 0.02 ? w.x : 0.0) + (w.y > 0.02 ? w.y : 0.0) + (w.z > 0.02 ? w.z : 0.0);
	alb /= wsum;
	rough /= wsum;
	ao /= wsum;
	wn = normalize(wn + n * 0.001);

	// macro variation
	float m = texture(tex_macro, wpos.xz * 0.031 + vec2(wpos.y * 0.017)).r;
	float m2 = texture(tex_macro, wpos.xz * 0.0071 + vec2(0.37, 0.11)).r;
	alb *= mix(1.0 - macro_strength, 1.0 + macro_strength * 0.6, m * 0.6 + m2 * 0.4);

	vec3 vc = mix(vec3(1.0), COLOR.rgb, use_vcolor);
	alb *= tint.rgb * vc;

	// height above the "ground" of this surface (container stacks repeat every stack_h)
	float base = 0.0;
	if (stack_h > 0.0) {
		base = floor((wpos.y + 0.02) / stack_h) * stack_h;
	}
	float h = wpos.y - base;
	float vert = 1.0 - abs(n.y);
	float cao = mix(1.0 - ground_ao, 1.0, smoothstep(0.0, ground_ao_height, h));
	cao = mix(1.0, cao, vert);
	float gn = texture(tex_macro, vec2(wpos.x + wpos.z, wpos.y * 2.0) * 0.21).r;
	float gmask = (1.0 - smoothstep(0.0, grime_height * (0.6 + gn * 0.8), h)) * grime * vert;
	alb = mix(alb, alb * grime_color.rgb * 2.2, clamp(gmask, 0.0, 1.0));

	if (streaks > 0.0 && stack_h > 0.0) {
		float top = stack_h - h;
		float along = (abs(n.x) > abs(n.z)) ? wpos.z : wpos.x;
		float s = texture(tex_macro, vec2(along * 0.9, wpos.y * 0.035 + along * 0.013)).r;
		float sm = smoothstep(0.52, 0.78, s) * exp(-top * 0.55) * vert * streaks;
		alb = mix(alb, streak_color.rgb, clamp(sm, 0.0, 0.85));
		rough = mix(rough, 1.0, sm);
	}

	ALBEDO = alb * mix(1.0, cao, 0.55);
	ROUGHNESS = clamp(rough * rough_mul + rough_add, 0.03, 1.0);
	METALLIC = metallic;
	SPECULAR = specular;
	AO = ao * cao;
	AO_LIGHT_AFFECT = ao_light_affect;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	if (emission_energy > 0.0) {
		EMISSION = emission_color.rgb * emission_energy * mix(1.0, COLOR.a, emission_from_vcolor_alpha);
	}
}
