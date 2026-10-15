shader_type canvas_item;

uniform float phase : hint_range(0.0, 100.0) = 0.0;
uniform float wag_speed : hint_range(1.0, 20.0) = 7.2;
uniform float wag_amp : hint_range(0.0, 0.08) = 0.016;
uniform float tail_start : hint_range(0.0, 1.0) = 0.44;

void fragment() {
	vec2 uv = UV;
	float tail = smoothstep(tail_start, tail_start + 0.12, uv.x);
	tail *= tail;
	float wave = sin(TIME * wag_speed + phase) * wag_amp * tail;
	uv.y += wave;
	COLOR = texture(TEXTURE, uv);
}
