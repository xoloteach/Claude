// IRONLINE — fake volumetric light shaft / haze card. Additive, unshaded, soft edges from UV, fades when
// seen edge-on or up close, gently animated dust noise. COLOR = shaft colour (a = intensity).
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, fog_disabled;

uniform sampler2D tex_macro : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float intensity = 1.0;
uniform float near_fade = 3.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	float facing = abs(dot(normalize(wnrm), V));
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	float len = smoothstep(0.0, 0.15, UV.y) * smoothstep(1.0, 0.55, UV.y);
	float n = texture(tex_macro, vec2(UV.x * 1.5 + TIME * 0.01, UV.y * 0.6 - TIME * 0.006) + wpos.xz * 0.02).r;
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	float nf = smoothstep(0.5, near_fade, dist);
	float a = edge * len * smoothstep(0.05, 0.5, facing) * (0.6 + n * 0.8) * nf * intensity * COLOR.a;
	ALBEDO = COLOR.rgb * a;
}
