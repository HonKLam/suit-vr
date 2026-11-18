shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;

// Fills clockwise from the top, faces the camera.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.75, 0.2, 1.0);
uniform vec4 empty_color : source_color = vec4(1.0, 1.0, 1.0, 0.3);
// relative to the radius
uniform float ring_width : hint_range(0.05, 1.0) = 0.25;

void vertex() {
	// billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 from_center = UV * 2.0 - 1.0;
	float distance_to_center = length(from_center);
	float edge_softness = fwidth(distance_to_center);
	float inside_ring = smoothstep(1.0, 1.0 - edge_softness, distance_to_center)
		* smoothstep(1.0 - ring_width - edge_softness, 1.0 - ring_width, distance_to_center);

	float angle = atan(from_center.x, -from_center.y);
	float ring_position = angle < 0.0 ? angle / TAU + 1.0 : angle / TAU;

	vec4 color = ring_position < progress ? fill_color : empty_color;
	ALBEDO = color.rgb;
	ALPHA = color.a * inside_ring;
}
