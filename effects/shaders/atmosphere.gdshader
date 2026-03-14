// atmosphere.gdshader
// Rim-lit translucent atmosphere shell rendered as an inverted cull_front sphere
// slightly larger than the planet. Alpha falls off toward the centre of the disc,
// giving a realistic limb-glow effect.
// Atmosphere colour and density are driven by uniform parameters set in Planet.gd.

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded, shadows_disabled;

// ---------------------------------------------------------------------------
// Uniforms — driven by Planet.gd
// ---------------------------------------------------------------------------
uniform float atmosphere_level : hint_range(0.0, 1.0) = 1.0;
uniform vec4  atmo_color : source_color = vec4(0.30, 0.60, 1.0, 0.30);

// ---------------------------------------------------------------------------
// Vertex — pass view-space normal for rim calculation
// ---------------------------------------------------------------------------
varying vec3 v_view_normal;

void vertex() {
	v_view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// ---------------------------------------------------------------------------
// Fragment
// ---------------------------------------------------------------------------
void fragment() {
	// Rim factor: 0 at surface centre, 1 at the limb (edge-on silhouette)
	float rim      = 1.0 - abs(dot(v_view_normal, vec3(0.0, 0.0, 1.0)));
	float rim_pow  = pow(rim, 2.8);

	// Base alpha from rim and atmosphere health
	float alpha    = rim_pow * atmosphere_level * atmo_color.a * 2.5;
	alpha          = clamp(alpha, 0.0, 0.75);

	// Colour slightly shifts toward red as atmosphere is depleted (pollution)
	float depletion = 1.0 - atmosphere_level;
	vec3  col       = mix(atmo_color.rgb,
	                      vec3(0.8, 0.3, 0.1),
	                      depletion * 0.6);

	ALBEDO = col;
	ALPHA  = alpha;
}
