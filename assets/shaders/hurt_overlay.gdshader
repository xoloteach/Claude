shader_type canvas_item;
// Damage feedback: red edge vignette + blood-vein noise + desaturation at low health.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform float low_health : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float a = hash(i), b = hash(i + vec2(1.0, 0.0)), c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float k = max(hurt, low_health);
	if (k < 0.002) {
		COLOR = vec4(0.0);
	} else {
		vec3 scene = textureLod(screen_tex, uv, 0.0).rgb;
		vec2 p = uv - 0.5;
		p.x *= 1.6;
		float d = length(p);
		float pulse = 0.85 + 0.15 * sin(time * 8.0);
		float n = noise(uv * 9.0 + time * 0.05) * 0.6 + noise(uv * 23.0) * 0.4;
		float edge = smoothstep(0.35, 0.95, d + n * 0.18);
		float amount = clamp(hurt * 0.9 + low_health * 0.75 * pulse, 0.0, 1.0);
		float lum = dot(scene, vec3(0.299, 0.587, 0.114));
		vec3 desat = mix(scene, vec3(lum) * vec3(1.05, 0.95, 0.95), low_health * 0.65);
		vec3 blood = vec3(0.35, 0.0, 0.0) * (0.6 + 0.4 * n);
		vec3 col = mix(desat, blood, edge * amount * 0.9);
		col = mix(col, col * vec3(1.0, 0.8, 0.8), hurt * 0.3);
		COLOR = vec4(col, 1.0);
	}
}
