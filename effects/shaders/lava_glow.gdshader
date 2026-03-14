// lava_glow.gdshader
// Animated lava pool / lava spread effect shader.
// Applied to MeshInstance3D spheres placed at disaster sites.
// Simulates flowing molten rock with animated noise and strong emission.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform float time_scale : hint_range(0.1, 4.0) = 1.0;
uniform float intensity  : hint_range(0.0, 5.0) = 3.0;
uniform float alpha      : hint_range(0.0, 1.0) = 1.0;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(dot(hash33(i + vec3(0,0,0)).x, 1.0),
		        dot(hash33(i + vec3(1,0,0)).x, 1.0), u.x),
		    mix(dot(hash33(i + vec3(0,1,0)).x, 1.0),
		        dot(hash33(i + vec3(1,1,0)).x, 1.0), u.x), u.y),
		mix(mix(dot(hash33(i + vec3(0,0,1)).x, 1.0),
		        dot(hash33(i + vec3(1,0,1)).x, 1.0), u.x),
		    mix(dot(hash33(i + vec3(0,1,1)).x, 1.0),
		        dot(hash33(i + vec3(1,1,1)).x, 1.0), u.x), u.y),
		u.z
	);
}

// ---------------------------------------------------------------------------
// Vertex — pass world-space position for noise sampling
// ---------------------------------------------------------------------------
varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// ---------------------------------------------------------------------------
// Fragment
// ---------------------------------------------------------------------------
void fragment() {
	float t = TIME * time_scale;

	// Two layers of flowing noise for lava movement
	float n1 = vnoise(v_world_pos * 2.0 + vec3(t * 0.4, -t * 0.3, t * 0.2));
	float n2 = vnoise(v_world_pos * 4.0 + vec3(-t * 0.2, t * 0.5, -t * 0.1));
	float n  = clamp(n1 * 0.6 + n2 * 0.4, 0.0, 1.0);

	// Colour: dark volcanic rock → bright orange-white lava
	vec3 rock   = vec3(0.10, 0.02, 0.01);
	vec3 lava1  = vec3(0.90, 0.20, 0.00);
	vec3 lava2  = vec3(1.00, 0.80, 0.20);

	vec3 col;
	if (n < 0.4) {
		col = mix(rock,  lava1, n / 0.4);
	} else {
		col = mix(lava1, lava2, (n - 0.4) / 0.6);
	}

	// Emission: bright where lava is hottest
	float emit_strength = pow(n, 1.5) * intensity;

	ALBEDO   = col;
	EMISSION = col * emit_strength;
	ALPHA    = alpha;
}
