// Stilisierter Höhenverlauf für Level-Geometrie (Vulkan, Kletterwand).
// Unten dunkel (+ optionales Lava-Glühen), oben hell -> "da oben ist das Licht, da geht's hin".
// Platzhalter-Look, bis echte Texturen da sind. Läuft im Compatibility-Renderer (Quest).
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform vec3 bottom_color : source_color = vec3(0.16, 0.10, 0.12);
uniform vec3 top_color : source_color = vec3(0.62, 0.45, 0.38);
uniform float bottom_height = 0.0;   // Weltkoordinate Y: hier ist es ganz dunkel
uniform float top_height = 24.0;     // Weltkoordinate Y: hier ist es ganz hell
uniform float gradient_curve : hint_range(0.2, 4.0) = 1.4; // >1 = länger dunkel, schneller hell oben

uniform vec3 glow_color : source_color = vec3(1.0, 0.35, 0.08);
uniform float glow_height = 3.0;     // wie hoch das Glühen vom Boden reicht (0 = aus)
uniform float glow_energy = 1.5;

uniform float facet_strength : hint_range(0.0, 1.0) = 0.15; // leichte Helligkeitsvariation pro Fläche

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
	// Flächen leicht unterschiedlich hell (Low-Poly-Look), aus der Normalen
	col *= 1.0 - facet_strength * 0.5 + facet_strength * fract(dot(world_normal, vec3(12.9898, 78.233, 37.719)) * 0.5);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	if (glow_height > 0.0) {
		float g = 1.0 - smoothstep(bottom_height, bottom_height + glow_height, world_y);
		EMISSION = glow_color * g * g * glow_energy;
	}
}
