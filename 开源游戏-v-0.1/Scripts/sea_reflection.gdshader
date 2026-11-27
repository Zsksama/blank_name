shader_type canvas_item;
render_mode unshaded;

uniform sampler2D wave_profile : filter_linear, repeat_disable;
uniform vec2 water_x;
uniform float sample_count;
uniform float profile_row;
uniform vec4 water_tint : source_color;
instance uniform vec4 hidden_sail_uv = vec4(0.0);
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float x = (world_position.x - water_x.x) / (water_x.y - water_x.x);
	float u = (x * (sample_count - 1.0) + 0.5) / sample_count;
	vec2 limits = texture(wave_profile, vec2(u, profile_row)).rg;
	float depth = world_position.y - limits.x;
	if (x < 0.0 || x > 1.0 || depth < 0.0 || world_position.y >= limits.y) {
		discard;
	}
	if (all(greaterThanEqual(UV, hidden_sail_uv.xy)) && all(lessThan(UV, hidden_sail_uv.zw))) {
		discard;
	}
	COLOR.rgb = mix(COLOR.rgb, water_tint.rgb, 0.42);
	COLOR.a *= smoothstep(0.0, 1.4, depth) * (1.0 - smoothstep(10.0, 67.0, depth));
}
