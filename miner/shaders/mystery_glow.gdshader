shader_type canvas_item;

uniform float glow_speed : hint_range(0.4, 4.0) = 1.35;
uniform float glow_amp : hint_range(0.0, 1.2) = 0.72;
uniform float gem_amp : hint_range(0.0, 1.5) = 0.95;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (col.a >= 0.04) {
	float mx = max(col.r, max(col.g, col.b));
	float mn = min(col.r, min(col.g, col.b));
	float sat = mx - mn;
	float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	float breath = 0.5 + 0.5 * sin(TIME * glow_speed);
	float breath2 = 0.5 + 0.5 * sin(TIME * glow_speed * 1.37 + 1.7);

	float yellow = smoothstep(0.08, 0.0, abs(col.r - col.g)) * smoothstep(0.18, 0.42, col.r - col.b);
	float gold = yellow * smoothstep(0.55, 0.82, lum);
	float white_hot = smoothstep(0.78, 0.96, lum) * (1.0 - sat * 0.35);
	float mark = clamp(gold * 1.15 + white_hot, 0.0, 1.0);

	float cyan = smoothstep(0.12, 0.0, abs(col.g - col.b)) * smoothstep(0.08, 0.28, col.b - col.r);
	float purple = smoothstep(0.08, 0.28, col.b - col.g) * smoothstep(0.05, 0.22, col.r - col.g * 0.4);
	float gem = clamp((cyan + purple) * smoothstep(0.32, 0.62, lum) * smoothstep(0.12, 0.35, sat), 0.0, 1.0);

	vec3 gold_add = vec3(1.15, 0.92, 0.38) * mark * (0.18 + glow_amp * breath);
	vec3 gem_add = vec3(0.55, 0.85, 1.15) * gem * (0.22 + gem_amp * breath2);
	col.rgb += gold_add + gem_add;
	col.rgb += vec3(0.18, 0.12, 0.05) * mark * breath * 0.22;
	}
	COLOR = col;
}
