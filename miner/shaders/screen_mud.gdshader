shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float wipe : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	vec2 smear = vec2(
		sin(uv.y * 16.0 + t * 2.1),
		cos(uv.x * 13.0 - t * 1.5)
	) * (0.02 * amount);
	vec4 scene = texture(screen_texture, clamp(uv + smear, vec2(0.001), vec2(0.999)));
	float blot = 0.0;
	blot += smoothstep(0.38, 0.16, length(uv - vec2(0.20, 0.26) + 0.03 * vec2(sin(t), cos(t * 0.7))));
	blot += smoothstep(0.44, 0.18, length(uv - vec2(0.78, 0.20)));
	blot += smoothstep(0.40, 0.17, length(uv - vec2(0.58, 0.74) + 0.02 * vec2(cos(t * 0.9), sin(t))));
	blot += smoothstep(0.34, 0.14, length(uv - vec2(0.16, 0.70)));
	blot += smoothstep(0.36, 0.15, length(uv - vec2(0.88, 0.62)));
	blot += smoothstep(0.30, 0.12, length(uv - vec2(0.42, 0.48)));
	blot = clamp(blot, 0.0, 1.0) * amount;

	float ang = radians(30.0);
	vec2 along = vec2(cos(ang), sin(ang));
	vec2 across = vec2(-along.y, along.x);
	float along_n = dot(uv, along) / (along.x + along.y);
	float across_min = min(min(0.0, across.x), min(across.y, across.x + across.y));
	float across_max = max(max(0.0, across.x), max(across.y, across.x + across.y));
	float across_n = (dot(uv, across) - across_min) / max(across_max - across_min, 0.001);

	const float STROKES = 5.0;
	float band = clamp(across_n, 0.0, 0.999) * STROKES;
	float bi = floor(band);
	float w = wipe * STROKES;
	float cur = floor(w + 1e-5);
	float te = clamp(fract(w), 0.0, 1.0);
	if (wipe >= 0.999) {
		cur = STROKES;
		te = 1.0;
	}
	float streak = sin(band * 28.0) * 0.012;
	float front = te * 1.08 - 0.02 + streak;

	float mud_keep = 1.0;
	if (bi < cur) {
		mud_keep = 0.0;
	} else if (bi > cur) {
		mud_keep = 1.0;
	} else {
		mud_keep = smoothstep(front - 0.04, front + 0.03, along_n);
	}

	float ridge = 0.0;
	if (bi == cur && wipe > 0.01 && wipe < 0.99) {
		ridge = 1.0 - smoothstep(0.0, 0.055, abs(along_n - front));
		ridge *= smoothstep(0.0, 0.08, te) * (1.0 - smoothstep(0.92, 1.0, te));
	}

	vec3 mud = vec3(0.30, 0.18, 0.07);
	vec3 dirty = mix(scene.rgb * vec3(0.58, 0.44, 0.24), mud, 0.62);
	float cover = blot * 0.94 * mud_keep;
	vec3 col = mix(scene.rgb, dirty, cover);
	col *= mix(vec3(1.0), vec3(0.72, 0.58, 0.32), 0.28 * amount * mud_keep);
	col = mix(col, mix(col, mud * 1.2, 0.4), ridge * amount);
	COLOR = vec4(col, 1.0);
}
