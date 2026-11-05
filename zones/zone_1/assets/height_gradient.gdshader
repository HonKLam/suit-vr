// Stylized height gradient for level geometry (volcano, climbing wall).
// Dark at the bottom (+ optional lava glow), bright at the top: "the light is up there, go that way".
// Placeholder look until real textures exist. Runs in the Compatibility renderer (Quest).
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform vec3 bottom_color : source_color = vec3(0.16, 0.10, 0.12);
uniform vec3 top_color : source_color = vec3(0.62, 0.45, 0.38);
uniform float bottom_height = 0.0;   // world coordinate Y: fully dark here
uniform float top_height = 24.0;     // world coordinate Y: fully bright here
uniform float gradient_curve : hint_range(0.2, 4.0) = 1.4; // >1 = dark for longer, bright faster at the top

uniform vec3 glow_color : source_color = vec3(1.0, 0.35, 0.08);
uniform float glow_height = 3.0;     // how high the glow reaches from the ground (0 = off)
uniform float glow_energy = 1.5;

uniform float facet_strength : hint_range(0.0, 1.0) = 0.15; // slight brightness variation per face

varying float world_y;
varying vec3 world_normal;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float t = clamp((world_y - bottom_height) / max(top_height - bottom_height, 0.001), 0.0, 1.0);
	t = pow(t, gradient_curve);
	vec3 col = mix(bottom_color, top_color, t);
	// Faces slightly differ in brightness (low-poly look), from the normal
	col *= 1.0 - facet_strength * 0.5 + facet_strength * fract(dot(world_normal, vec3(12.9898, 78.233, 37.719)) * 0.5);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	if (glow_height > 0.0) {
		float g = 1.0 - smoothstep(bottom_height, bottom_height + glow_height, world_y);
		EMISSION = glow_color * g * g * glow_energy;
	}
}
