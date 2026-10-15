shader_type canvas_item;

uniform float water_bottom_y : hint_range(300.0, 450.0) = 375.0;
uniform float salvage_clear_y : hint_range(350.0, 500.0) = 398.0;
uniform float surface_uv_y : hint_range(0.0, 1.0) = 0.552;
uniform float blood : hint_range(0.0, 1.0) = 0.0;

varying float v_world_y;

void vertex() {
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float a = 1.0;
	if (v_world_y >= salvage_clear_y) {
		a = 0.0;
	} else if (v_world_y > water_bottom_y) {
		a = 1.0 - smoothstep(water_bottom_y, salvage_clear_y, v_world_y);
	}
	float below = smoothstep(surface_uv_y - 0.012, surface_uv_y + 0.028, UV.y);
	float luma = dot(col.rgb, vec3(0.30, 0.50, 0.20));
	vec3 blood_rgb = vec3(0.94, 0.32, 0.48) * (0.40 + luma * 1.2);
	col.rgb = mix(col.rgb, blood_rgb, blood * below * 0.82);
	col.a *= a;
	COLOR = col;
}
