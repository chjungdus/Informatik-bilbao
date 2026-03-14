// city_pulse.gdshader
// Pulsing energy shader for city nodes — gives them a living "heartbeat" glow.
// The pulse speed increases with tech level.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4  city_color   : source_color = vec4(1.0, 0.95, 0.5, 1.0);
uniform float tech_level   : hint_range(1.0, 100.0) = 1.0;
uniform float pulse_offset : hint_range(0.0, 6.28) = 0.0;   // per-city phase
uniform float is_collapsed : hint_range(0.0, 1.0)  = 0.0;

void fragment() {
	float pulse_speed = 1.5 + tech_level * 0.03;
	float pulse       = sin(TIME * pulse_speed + pulse_offset) * 0.5 + 0.5;

	// Collapsed cities are dark and desaturated
	vec3 base_col = city_color.rgb;
	vec3 col_live = base_col * (0.5 + pulse * 0.6);
	vec3 col_dead = vec3(0.15, 0.03, 0.03);

	vec3 final_col = mix(col_live, col_dead, is_collapsed);

	float emit_strength = mix(pulse * 0.8 * (tech_level / 20.0), 0.0, is_collapsed);

	ALBEDO   = final_col;
	EMISSION = final_col * emit_strength;
	ROUGHNESS = 0.4;
	METALLIC  = mix(0.1, 0.0, is_collapsed);
}
