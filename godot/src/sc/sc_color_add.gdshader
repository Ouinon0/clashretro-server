// Composante additive des transformations de couleur .sc : couleur = texture × mul + add.
// Le « mul » passe par modulate (hérité des parents), « add » par cet uniform.
shader_type canvas_item;

uniform vec4 add_color = vec4(0.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(min(c.rgb + add_color.rgb, vec3(1.0)), c.a);
}
