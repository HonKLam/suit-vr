// Stilisierter Himmel: Farbverlauf, Sonne (folgt dem DirectionalLight3D),
// Comic-Wolken und zwei Lagen Bergsilhouetten am Horizont.
// Bewusst ohne TIME -> der Himmel wird nur einmal berechnet (wichtig für VR / Quest).
shader_type sky;
render_mode use_debanding;

group_uniforms Himmel;
uniform vec3 top_color : source_color = vec3(0.27, 0.52, 0.92);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.83, 0.66);
uniform vec3 ground_color : source_color = vec3(0.33, 0.40, 0.52);
uniform float gradient_height : hint_range(0.05, 1.0) = 0.55;

group_uniforms Sonne;
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.78);
uniform float sun_size : hint_range(0.001, 0.1) = 0.012;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.6;

group_uniforms Wolken;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow_color : source_color = vec3(0.74, 0.79, 0.95);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.52;
uniform float cloud_scale = 1.4;
uniform float cloud_softness : hint_range(0.001, 0.2) = 0.02;
uniform vec2 cloud_offset = vec2(0.0, 0.0); // zum Verschieben der Wolken

group_uniforms Berge;
uniform vec3 mountain_far_color : source_color = vec3(0.70, 0.66, 0.84);
uniform vec3 mountain_near_color : source_color = vec3(0.47, 0.50, 0.72);
uniform float mountain_far_height : hint_range(0.0, 0.5) = 0.16;
uniform float mountain_near_height : hint_range(0.0, 0.5) = 0.09;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v / 0.9375;
}

// Silhouette um den Horizont herum, nahtlos (Kreis statt Winkel)
float ridge(vec3 d, float freq, float seed) {
	vec2 c = normalize(d.xz) * freq + vec2(seed, -seed);
	float n = fbm(c);
	return clamp(pow(n, 2.2) * 1.8, 0.05, 1.0); // spitzere Gipfel
}

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;

	// Verlauf
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, gradient_height, y));
	if (y < 0.0) {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.08, -y));
	}

	// Sonne
	if (LIGHT0_ENABLED) {
		float s = dot(d, LIGHT0_DIRECTION);
		float disk = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.6, s);
		float glow = pow(max(s, 0.0), 24.0) * 0.5 + pow(max(s, 0.0), 4.0) * 0.12;
		col = mix(col, sun_color * 1.6, disk);
		col += sun_color * glow * sun_glow;
	}

	// Wolken (flache Ebene über dem Spieler, harte Comic-Kante + Schattenseite)
	if (y > 0.0) {
		vec2 uv = d.xz / (y + 0.12) * cloud_scale * 0.35 + cloud_offset;
		float n = fbm(uv);
		float c = smoothstep(cloud_coverage, cloud_coverage + cloud_softness, n);
		float n2 = fbm(uv + vec2(0.06, 0.06));
		float shade = smoothstep(cloud_coverage + 0.06, cloud_coverage + 0.06 + cloud_softness, n2);
		vec3 cc = mix(cloud_shadow_color, cloud_color, shade);
		float fade = smoothstep(0.02, 0.25, y);
		col = mix(col, cc, c * fade);
	}

	// Berge: zwei Lagen, hinten heller (Luftperspektive)
	float hf = mountain_far_height * ridge(d, 3.0, 3.1);
	float hn = mountain_near_height * ridge(d, 5.0, 7.3);
	if (y < hf && y > -0.01) {
		col = mountain_far_color;
	}
	if (y < hn && y > -0.01) {
		col = mountain_near_color;
	}

	COLOR = col;
}
