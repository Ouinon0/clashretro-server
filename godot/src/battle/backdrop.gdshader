shader_type spatial;
// Décor 2D du combat au fond de la scène 3D : couleur telle quelle (ni lumière, ni tonemapping).
render_mode unshaded, fog_disabled, depth_draw_never, cull_disabled;

uniform sampler2D tex : source_color, filter_linear;

void fragment() {
	ALBEDO = texture(tex, UV).rgb;
}
