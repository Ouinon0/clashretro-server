shader_type spatial;
// Unités de l'équipe adverse : les teintes bleues de la texture (habits, bannières) passent au rouge,
// comme dans le jeu (les modèles de la 16.4 n'existent qu'en bleu).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform float roughness = 0.8;
uniform float metallic = 0.0;
uniform bool enemy = false;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 color = tex.rgb;
	if (enemy) {
		vec3 hsv = rgb2hsv(color);
		// Bleus (teinte 0,5 à 0,72) assez saturés → rouges, en gardant la luminosité.
		float blue = smoothstep(0.47, 0.52, hsv.x) * (1.0 - smoothstep(0.70, 0.75, hsv.x))
				* smoothstep(0.18, 0.3, hsv.y);
		vec3 red = hsv2rgb(vec3(fract(hsv.x + 0.47), min(1.0, hsv.y * 1.05), hsv.z * 0.95));
		color = mix(color, red, blue);
	}
	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
