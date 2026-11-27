shader_type canvas_item;
render_mode unshaded;

uniform sampler2D wave_profile : filter_linear, repeat_disable;
uniform vec2 water_origin;
uniform vec2 water_size;
uniform float sample_count;
uniform float water_clock;
uniform float swell_scale = 1.0;
uniform float detail_amount = 1.0;
uniform vec4 detail_tint : source_color = vec4(1.0);

// Profile row, waterline baseline, wave amplitude and wave speed.
instance uniform vec4 row_profile;
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (detail_amount > 0.0) {
		vec2 point = world_position - water_origin;
		float depth = clamp(point.y / max(water_size.y, 1.0), 0.0, 1.0);
		float x_drift = point.x - water_clock * mix(24.0, 43.0, depth);

		// Small ripples share one field across the whole sea, including the lane edges.
		float ripple_phase = point.y * (0.94 - 0.25 * depth) - water_clock * 1.65;
		ripple_phase += sin(x_drift * 0.024 - point.y * 0.037) * 0.92;
		ripple_phase += sin(x_drift * 0.067 + point.y * 0.048) * 0.39;
		float packets = sin(x_drift * mix(0.14, 0.055, depth) + point.y * 0.39) * 0.63;
		packets += sin(x_drift * 0.053 - point.y * 0.21) * 0.37;
		float ripple = sin(ripple_phase);
		float packet_mask = smoothstep(-0.10, 0.82, packets);
		float light = smoothstep(0.65, 0.99, ripple) * packet_mask * mix(0.065, 0.157, depth);
		float shade = smoothstep(0.67, 0.99, -ripple) * packet_mask * mix(0.016, 0.042, depth);

		float u = (point.x / max(water_size.x, 1.0) * (sample_count - 1.0) + 0.5) / sample_count;
		float crest_y = texture(wave_profile, vec2(u, row_profile.x)).r;
		float below_crest = world_position.y - crest_y;
		if (below_crest >= 0.0 && below_crest < 33.0) {
			// Highlights ride the same crests used to float ships and clip their reflections.
			float swell = (row_profile.y - crest_y) / max(row_profile.z * swell_scale, 0.6);
			float lift = smoothstep(-0.23, 0.60, swell);
			// 64.5 matches the main swell's 2.0 / 0.031 phase velocity.
			float moving_x = point.x - water_clock * row_profile.w * 64.5;
			float breaks = sin(moving_x * 0.071 + row_profile.x * 19.0) * 0.59;
			breaks += sin(moving_x * 0.191 - point.y * 0.056) * 0.26;
			breaks += sin(point.x * 0.041 - water_clock * 0.79) * 0.15;
			float crest_patch = smoothstep(-0.16, 0.70, breaks) * lift;
			float foam_center = mix(2.3, 4.1, depth) + sin(moving_x * 0.039 + water_clock) * 0.65;
			float foam_width = mix(1.45, 3.55, depth);
			float foam = 1.0 - smoothstep(0.21, foam_width, abs(below_crest - foam_center));
			float backwash_y = mix(5.5, 14.0, depth) + sin(moving_x * 0.048 + water_clock * 0.86) * 2.1;
			float backwash = 1.0 - smoothstep(0.1, 3.85, abs(below_crest - backwash_y));
			float shoulder = smoothstep(2.5, 8.0, below_crest) * (1.0 - smoothstep(10.0, 30.0, below_crest));
			float visibility = smoothstep(0.025, 0.30, depth);
			light += (foam * mix(0.27, 0.59, depth) + backwash * packet_mask * 0.17) * crest_patch * visibility;
			shade += shoulder * crest_patch * visibility * mix(0.035, 0.078, depth);
		}

		vec3 glint = vec3(0.65, 0.86, 0.93) * detail_tint.rgb;
		COLOR.rgb = mix(COLOR.rgb * (1.0 - shade * detail_amount), glint, light * detail_amount);
	}
}
