// Gemeinsamer Wind-Code für Pflanzen (Bäume, Büsche, Gras).
// Bewegt nur Eckpunkte im Vertex-Shader -> läuft komplett auf der GPU, sehr günstig.
// Je höher ein Punkt über dem Fußpunkt des Objekts, desto stärker schwankt er.
// Ersetzt optisch das importierte StandardMaterial (Textur * Vertex-Farbe).
render_mode world_vertex_coords, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
#ifdef CUTOUT
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
#endif

group_uniforms Wind;
// Richtung (x/z, Welt) und Tempo.
uniform vec2 wind_direction = vec2(1.0, 0.3);
uniform float wind_speed = 1.0;
// Ausschlag (m) auf Höhe sway_height.
uniform float sway = 0.1;
// Ab dieser Höhe (m über Fußpunkt) voller Ausschlag.
uniform float sway_height = 1.0;
// Zusätzliches Zittern der Blätter (m).
uniform float flutter = 0.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y - origin.y, 0.0);
	float k = pow(min(h / max(sway_height, 0.001), 2.0), 1.6);
	vec2 d = normalize(wind_direction + vec2(0.0001));
	float t = TIME * wind_speed;
	// Welle läuft in Windrichtung über die Szene; jedes Objekt eigene Phase.
	float phase = dot(origin.xz, d) * 0.45 + origin.x * 0.21 + origin.z * 0.13;
	float gust = 0.65 + 0.35 * sin(t * 0.31 + dot(origin.xz, d) * 0.08);
	float s = (sin(t * 1.3 - phase) * 0.7 + sin(t * 2.9 - phase * 1.7) * 0.3) * gust;
	VERTEX.xz += d * s * sway * k;
	VERTEX.xz += vec2(-d.y, d.x) * sin(t * 1.1 - phase * 0.8) * sway * 0.3 * k;
	if (flutter > 0.0) {
		vec3 p = VERTEX * 3.0;
		VERTEX += flutter * k * vec3(sin(t * 7.0 + p.x + p.y), sin(t * 6.1 + p.z) * 0.6, cos(t * 6.7 + p.y + p.z));
	}
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 col = tex.rgb * albedo_color.rgb;
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	ALBEDO = col;
	ROUGHNESS = roughness;
#ifdef CUTOUT
	ALPHA = tex.a * albedo_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
#endif
}
