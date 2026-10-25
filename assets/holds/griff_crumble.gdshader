// Griff mit zweitem "Zerfalls"-Texturset (+ optionaler Maske) + Auflösen.
// Bildet die StandardMaterial3D-Werte von mat_griff.tres nach (Albedo, ORM, Normal, Emission)
// und blendet über `progress` (0..1) eine zweite Textur darüber. `dissolve` (0..1) lässt den
// Stein danach mit glühender Kante verschwinden.
// Die Parameter werden von griff_crumble.gd gesetzt – man muss hier normalerweise nichts anfassen.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms Basis;
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
// ORM: R = Occlusion, G = Roughness, B = Metallic (wie aus Substance exportiert)
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale = 1.0;
uniform sampler2D emission_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 emission_color : source_color = vec4(0.2745, 1.0, 0.0, 1.0);
uniform float emission_energy = 1.0;
uniform bool emission_add = false; // false = Multiply (wie in mat_griff.tres), true = Add
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

group_uniforms Zerfall;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 crumble_tint : source_color = vec4(0.35, 0.30, 0.28, 1.0); // nur ohne crumble_texture
uniform float crumble_roughness : hint_range(0.0, 1.0) = 1.0;
uniform vec4 crumble_emission_color : source_color = vec4(1.0, 0.15, 0.0, 1.0);
uniform float crumble_emission_energy = 1.0;
uniform float noise_scale = 3.0;                               // Größe der "Flecken"
uniform float spread_softness : hint_range(0.01, 0.5) = 0.15;  // 0.5 = fast gleichmäßiges Überblenden

group_uniforms Zweites_Texturset;
// Jede Textur ist optional. Fehlt eine, wird der passende Basis-Wert verwendet.
uniform bool use_crumble_texture = false;
uniform sampler2D crumble_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_crumble_orm = false;
uniform sampler2D crumble_orm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_crumble_normal = false;
uniform sampler2D crumble_normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_crumble_emission = false;
uniform sampler2D crumble_emission_texture : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;

group_uniforms Maske;
// Graustufen-Maske (R-Kanal) auf den UVs: schwarz = zerfällt zuerst, weiß = zuletzt.
uniform bool use_effect_mask = false;
uniform sampler2D effect_mask : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float mask_strength : hint_range(0.0, 1.0) = 1.0; // 1 = nur Maske, <1 = Maske + etwas Noise
uniform bool invert_mask = false;

group_uniforms Aufloesen;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.4, 0.0, 1.0);
uniform float edge_width : hint_range(0.0, 0.3) = 0.08;
uniform float edge_energy = 4.0;

group_uniforms Wackeln;
uniform float shake = 0.0;        // 0..1, wird vom Skript gesetzt
uniform float shake_size = 0.0;   // Ausschlag in Objekt-Einheiten
uniform float shake_speed = 70.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX; // Objekt-Raum -> Muster wandert nicht mit, keine UV-Nähte
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	if (shake > 0.0) {
		vec3 j = vec3(sin(TIME * shake_speed), sin(TIME * shake_speed * 1.37 + 1.7), sin(TIME * shake_speed * 0.83 + 4.1));
		VERTEX += j * shake * shake_size;
	}
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i + vec3(0.0, 0.0, 0.0)), hash3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v / 0.9375; // auf ~0..1 normieren
}

void fragment() {
	float n = fbm(local_pos * noise_scale);
	if (use_effect_mask) {
		float m = texture(effect_mask, UV).r;
		if (invert_mask) {
			m = 1.0 - m;
		}
		n = mix(n, m, mask_strength);
	}

	// --- Zerfall: zweites Texturset frisst sich über Maske / Noise hinein ---
	float s = spread_softness;
	float t = progress * (1.0 + 2.0 * s) - s;
	float blend = smoothstep(n - s, n + s, t);

	// Basis
	vec4 base = texture(albedo_texture, UV) * albedo_color;
	vec4 orm = texture(orm_texture, UV);
	vec3 nrm = texture(normal_texture, UV).rgb;
	vec3 em_tex = texture(emission_texture, UV).rgb;
	vec3 base_em = (emission_add ? (emission_color.rgb + em_tex) : (emission_color.rgb * em_tex)) * emission_energy;
	float base_rough = orm.g * roughness;
	float base_metal = orm.b * metallic;
	float base_ao = mix(1.0, orm.r, ao_strength);

	// Zweites Texturset (fehlende Teile fallen auf Basis-Werte zurück)
	vec3 c_albedo = use_crumble_texture
		? texture(crumble_texture, UV).rgb
		: base.rgb * crumble_tint.rgb;
	float c_rough = crumble_roughness;
	float c_metal = 0.0;
	float c_ao = base_ao;
	if (use_crumble_orm) {
		vec4 corm = texture(crumble_orm_texture, UV);
		c_rough = corm.g;
		c_metal = corm.b;
		c_ao = corm.r;
	}
	vec3 c_nrm = use_crumble_normal ? texture(crumble_normal_texture, UV).rgb : nrm;
	vec3 c_em = use_crumble_emission
		? texture(crumble_emission_texture, UV).rgb * crumble_emission_color.rgb
		: em_tex * crumble_emission_color.rgb;
	c_em *= crumble_emission_energy;

	ALBEDO = mix(base.rgb, c_albedo, blend);
	ROUGHNESS = mix(base_rough, c_rough, blend);
	METALLIC = mix(base_metal, c_metal, blend);
	AO = mix(base_ao, c_ao, blend);
	NORMAL_MAP = mix(nrm, c_nrm, blend);
	NORMAL_MAP_DEPTH = normal_scale;
	EMISSION = mix(base_em, c_em, blend);

	// --- Auflösen ---
	if (dissolve > 0.0) {
		float d = dissolve * (1.0 + edge_width);
		if (n < d - edge_width) {
			discard;
		}
		float edge = 1.0 - smoothstep(d - edge_width, d, n);
		EMISSION += edge_color.rgb * edge_energy * edge;
	}
}
