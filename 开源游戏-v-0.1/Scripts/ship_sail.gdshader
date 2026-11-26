shader_type canvas_item;

uniform vec4 sail_region;
uniform bool sail_destroyed = false;

void fragment() {
	if (sail_destroyed && all(greaterThanEqual(UV, sail_region.xy)) && all(lessThan(UV, sail_region.zw))) {
		COLOR.a = 0.0;
	}
}
