// IRONLINE — multiplicative darkening decal (fake contact AO, oil stains, scorch). Unshaded blend_mul, so it
// darkens whatever is below it without affecting lighting. UV in 0..1 over the quad; COLOR.a = strength,
// UV2.x = shape (0 = soft rectangle, 1 = round blob with noisy edge), UV2.y = edge softness.
shader_type spatial;
render_mode blend_mul, depth_draw_never, cull_back, unshaded, fog_disabled;

uniform sampler2D tex_macro : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float pull = 0.0016;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= (1.0 - pull);
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float soft = max(UV2.y, 0.05);
	float d;
	if (UV2.x > 0.5) {
		float nz = texture(tex_macro, wpos.xz * 0.45).r;
		d = length(q) + (nz - 0.5) * 0.55;
	} else {
		vec2 a = abs(q);
		d = max(a.x, a.y);
	}
	float k = 1.0 - smoothstep(1.0 - soft, 1.0, d);
	float s = clamp(k * COLOR.a, 0.0, 1.0);
	ALBEDO = mix(vec3(1.0), COLOR.rgb, s);
}
