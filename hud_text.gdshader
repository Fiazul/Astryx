shader_type canvas_item;
// Metallic linear-gradient fill for HUD glyphs — gives the readout text the same
// "lit metal" sheen as the ship hull (a bright highlight up top fading to the
// label's base hue at the bottom). Applied to a Label whose font_color is white;
// the actual colour comes from these uniforms.
//
// The same material draws the label's outline and drop-shadow passes too, so we
// keep any DARK incoming glyph (outline/shadow) untouched and only paint the
// bright fill — that preserves legibility over the starfield.

uniform vec4 top_color : source_color = vec4(1.0, 0.88, 0.55, 1.0);    // warm highlight
uniform vec4 bottom_color : source_color = vec4(0.45, 0.85, 1.0, 1.0); // base hue
uniform float grad_height = 18.0;   // glyph height in px the gradient spans

varying float v_y;

void vertex() {
	v_y = VERTEX.y / grad_height;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	float t = clamp(v_y, 0.0, 1.0);
	vec3 grad = mix(top_color.rgb, bottom_color.rgb, t);
	// Bright fill -> metallic gradient; dark outline/shadow -> left as-is.
	vec3 rgb = mix(COLOR.rgb, grad, step(0.4, lum));
	COLOR = vec4(rgb, tex.a * COLOR.a);
}
