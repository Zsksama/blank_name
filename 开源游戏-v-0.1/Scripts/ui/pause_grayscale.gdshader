shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_color : hint_screen_texture, filter_nearest, repeat_disable;

void fragment() {
	vec3 scene = texture(screen_color, SCREEN_UV).rgb;
	float luminance = dot(scene, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(vec3(luminance * 0.76), 1.0);
}
