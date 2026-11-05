// Boden zum Graben: oben Rasen, darunter Erdschichten in harten Comic-Stufen.
// Farbe pro Pixel aus der (lokalen) Höhe -> scharfe Rasenkante wie in "A Game About Digging a Hole".
// Auch für normalen Boden nutzbar (dann ist alles oben Rasen).
shader_type spatial;
render_mode cull_back;

uniform vec3 grass_color : source_color = vec3(0.45, 0.68, 0.18);
uniform float grass_thickness = 0.03;
uniform vec3 layer_0 : source_color = vec3(0.64, 0.38, 0.25);
uniform vec3 layer_1 : source_color = vec3(0.55, 0.31, 0.2);
uniform vec3 layer_2 : source_color = vec3(0.45, 0.25, 0.16);
uniform vec3 layer_3 : source_color = vec3(0.35, 0.19, 0.12);
uniform float layer_thickness = 0.35;
// Höhe der Rasenoberfläche im Objekt (lokal y).
uniform float surface_y = 0.0;
// Je tiefer, desto dunkler (falsche Umgebungsverdeckung).
uniform float depth_darken : hint_range(0.0, 1.0) = 0.45;
uniform float depth_darken_range = 1.2;
uniform float noise_scale = 1.6;
uniform float noise_strength : hint_range(0.0, 0.5) = 0.18;

varying vec3 lpos;
varying vec3 wpos;
varying vec3 lnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.6 + vnoise(p * 2.3 + 4.1) * 0.4; }

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(lnrm);
	float h = surface_y - lpos.y; // Tiefe unter der Oberfläche
	vec3 col;
	if (h < grass_thickness && n.y > 0.6) {
		col = grass_color;
	} else {
		int i = clamp(int(floor(h / layer_thickness)), 0, 3);
		col = i == 0 ? layer_0 : (i == 1 ? layer_1 : (i == 2 ? layer_2 : layer_3));
	}
	vec3 b = abs(n);
	b /= (b.x + b.y + b.z);
	vec3 p = wpos * noise_scale;
	float nz = fbm(p.yz) * b.x + fbm(p.xz) * b.y + fbm(p.xy) * b.z;
	col *= 1.0 - depth_darken * clamp(h / depth_darken_range, 0.0, 1.0);
	ALBEDO = col * (1.0 - noise_strength + noise_strength * nz * 1.2);
	ROUGHNESS = 1.0;
}
