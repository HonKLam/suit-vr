// Stilisierte, animierte Lava: treibende Krustenplatten, leuchtende Risse, pulsierende Pools.
// Muster in Weltkoordinaten (X/Z) -> Box/Plane beliebig skalieren ohne Verzerrung.
// Unshaded (leuchtet selbst, kein Licht nötig) – günstig für Quest/Compatibility.
shader_type spatial;
render_mode unshaded, cull_back;

group_uniforms Farben;
uniform vec3 crust_color : source_color = vec3(0.10, 0.035, 0.04);
uniform vec3 crust_light : source_color = vec3(0.24, 0.07, 0.06);
uniform vec3 crust_heat : source_color = vec3(0.65, 0.12, 0.04);   // Schein am Krustenrand
uniform vec3 lava_deep : source_color = vec3(0.85, 0.12, 0.02);
uniform vec3 lava_mid : source_color = vec3(1.0, 0.42, 0.05);
uniform vec3 lava_hot : source_color = vec3(1.0, 0.88, 0.35);
uniform float glow : hint_range(1.0, 5.0) = 1.8;                 // >1 = bloomt mit Glow im Environment

group_uniforms Muster;
uniform float cell_scale = 0.55;                                    // Krustenplatten pro Meter
uniform float crack_width : hint_range(0.01, 0.4) = 0.12;
uniform float pool_amount : hint_range(0.0, 1.0) = 0.35;            // Anteil offener Lava-Pools
uniform int color_steps : hint_range(2, 8) = 4;                     // harte Farbstufen (Comic)
uniform float warp : hint_range(0.0, 3.0) = 1.1;                    // wie "zähflüssig" verzogen

group_uniforms Bewegung;
uniform vec2 flow = vec2(0.05, 0.025);                              // Drift der Platten (m/s)
uniform float churn_speed = 0.06;                                   // Brodeln / Verformen
uniform float pulse_speed = 1.4;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.18;
uniform float surface_bob = 0.03;                                   // leichtes Heben der Oberfläche (m)

varying vec3 wpos;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x, b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x, d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v / 0.875;
}

// Voronoi: x = Abstand nächste Zelle, y = zweitnächste, z = Zell-ID
vec3 voronoi(vec2 p, float t) {
	vec2 n = floor(p), f = fract(p);
	float d1 = 8.0, d2 = 8.0, id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(n + g);
			o = 0.5 + 0.35 * sin(t + 6.2831 * o); // Zellkerne wandern leicht
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1; d1 = d; id = hash2(n + g).y;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2, id);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (NORMAL.y > 0.5) {
		VERTEX.y += sin(wpos.x * 0.7 + TIME * 0.9) * cos(wpos.z * 0.6 + TIME * 0.7) * surface_bob;
	}
}

void fragment() {
	vec2 p = wpos.xz * cell_scale;
	// zähes Verziehen + Drift
	vec2 w = vec2(fbm(p * 0.45 + TIME * churn_speed), fbm(p * 0.45 + vec2(5.2, 1.3) - TIME * churn_speed));
	p += (w - 0.5) * warp + flow * TIME * cell_scale;

	vec3 v = voronoi(p, TIME * churn_speed * 6.0);
	float edge = v.y - v.x;                 // 0 an der Grenze zweier Platten
	float crack = 1.0 - smoothstep(crack_width * 0.4, crack_width, edge);
	float core = 1.0 - smoothstep(0.0, crack_width * 0.3, edge);   // heißer Kern mitten im Riss
	float bleed = 1.0 - smoothstep(crack_width, crack_width * 3.5, edge);

	// offene Pools: einzelne Platten "schmelzen" auf und zu
	float melt = sin(TIME * pulse_speed * 0.35 + v.z * 40.0) * 0.5 + 0.5;
	float pool = step(1.0 - pool_amount * 0.5, v.z) * smoothstep(0.55, 0.85, melt);
	pool *= 1.0 - smoothstep(0.25, 0.6, v.x);          // nur die Mitte der Platte

	float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed + v.z * 6.2831);
	float heat = clamp(max(max(crack * 0.55, core), pool) * pulse, 0.0, 1.0);
	heat = floor(heat * float(color_steps) + 0.5) / float(color_steps);   // Comic-Stufen

	// Kruste mit leichter Variation pro Platte und rotem Rand
	vec3 crust = mix(crust_color, crust_light, v.z * 0.6 + fbm(p * 2.5) * 0.4);
	float b = floor(bleed * 3.0) / 3.0;
	crust = mix(crust, crust_heat, b * 0.7);

	vec3 lava = heat < 0.5 ? mix(lava_deep, lava_mid, heat * 2.0) : mix(lava_mid, lava_hot, (heat - 0.5) * 2.0);
	vec3 col = mix(crust, lava * glow, step(0.01, heat));
	ALBEDO = col;
}
