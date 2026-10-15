shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME * 2.35;
	float amp = 0.038 * amount;
	uv.x += sin(uv.y * 22.0 + t) * amp;
	uv.y += cos(uv.x * 18.0 - t * 1.12) * amp;
	uv += vec2(sin(t + uv.y * 9.0), cos(t * 0.82 + uv.x * 10.0)) * amp * 0.42;
	vec2 uvc = clamp(uv, vec2(0.002), vec2(0.998));
	float ca = 0.004 * amount;
	float r = texture(screen_texture, uvc + vec2(ca, 0.0)).r;
	float g = texture(screen_texture, uvc).g;
	float b = texture(screen_texture, uvc - vec2(ca, 0.0)).b;
	COLOR = vec4(r, g, b, 1.0);
}
