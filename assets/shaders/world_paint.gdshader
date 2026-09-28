// IRONLINE — painted ground markings (lane lines, hatch zones, bay boxes). Opaque + discard for worn paint,
// pulled slightly toward the camera to avoid z-fighting with the ground. COLOR.rgb = paint colour,
// UV2.x = pattern (0 solid, 1 diagonal hatch), UV2.y = wear amount bias.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_macro : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wear = 0.42;
uniform float hatch_freq = 0.9;
uniform float pull = 0.0012;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= (1.0 - pull);
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	float pattern = UV2.x;
	if (pattern > 0.5) {
		float s = fract((wpos.x + wpos.z) * hatch_freq);
		if (s > 0.5) discard;
	}
	float n1 = texture(tex_macro, wpos.xz * 0.9).r;
	float n2 = texture(tex_macro, wpos.xz * 0.13 + vec2(0.3, 0.7)).r;
	float wv = n1 * 0.55 + n2 * 0.45;
	if (wv < wear + UV2.y) discard;
	float dirt = smoothstep(wear + UV2.y, wear + UV2.y + 0.25, wv);
	ALBEDO = COLOR.rgb * mix(0.55, 1.0, dirt);
	ROUGHNESS = 0.75;
	SPECULAR = 0.4;
	vec3 t = texture(tex_normal, wpos.xz * 0.35).xyz * 2.0 - 1.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(t.x * 0.4, 1.0, -t.y * 0.4)), 0.0)).xyz);
}
