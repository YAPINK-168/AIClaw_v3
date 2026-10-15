shader_type canvas_item;

uniform float wave_amp : hint_range(0.0, 0.03) = 0.0055;
uniform float wave_speed : hint_range(0.0, 8.0) = 1.05;
uniform float wave_freq : hint_range(2.0, 40.0) = 14.0;
uniform float surface_end : hint_range(0.05, 0.6) = 0.23;

void fragment() {
	float mask = 1.0 - smoothstep(surface_end * 0.42, surface_end, UV.y);
	float t = TIME * wave_speed;
	vec2 uv = UV;
	uv.x += sin(UV.y * wave_freq + UV.x * 6.5 + t) * wave_amp * mask;
	uv.y += cos(UV.x * (wave_freq * 0.62) - t * 0.9) * wave_amp * 0.45 * mask;
	uv = clamp(uv, vec2(0.001), vec2(0.999));
	vec4 col = texture(TEXTURE, uv);
	float crest = 0.5 + 0.5 * sin(UV.x * 16.0 - t * 1.35 + UV.y * 7.0);
	col.rgb += vec3(0.045, 0.07, 0.09) * crest * mask * 0.42;
	COLOR = col;
}
