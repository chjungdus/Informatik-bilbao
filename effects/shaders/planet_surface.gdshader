// planet_surface.gdshader
// Procedural terrain shader for the planet surface.
// Uses layered simplex noise to generate:
//   - Ocean, land, desert, forest, mountain, volcanic zones
//   - Ice caps at poles
//   - Dynamic damage cracking as health_level decreases
//   - Lava glow in crack zones

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back,
            diffuse_lambert, specular_schlick_ggx;

// ---------------------------------------------------------------------------
// Uniforms — controlled by Planet.gd
// ---------------------------------------------------------------------------
uniform float health_level : hint_range(0.0, 1.0) = 1.0;
uniform vec4  damage_tint  : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float crack_count  = 0.0;
uniform float noise_seed   = 0.0;

// ---------------------------------------------------------------------------
// Simplex-style hash
// ---------------------------------------------------------------------------
vec3 hash33(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7,  74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

// Gradient noise (value noise approximation, cheap & good-looking)
float vnoise(vec3 p) {
	vec3 i  = floor(p);
	vec3 f  = fract(p);
	vec3 u  = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(mix(dot(hash33(i + vec3(0,0,0)), f - vec3(0,0,0)),
		        dot(hash33(i + vec3(1,0,0)), f - vec3(1,0,0)), u.x),
		    mix(dot(hash33(i + vec3(0,1,0)), f - vec3(0,1,0)),
		        dot(hash33(i + vec3(1,1,0)), f - vec3(1,1,0)), u.x), u.y),
		mix(mix(dot(hash33(i + vec3(0,0,1)), f - vec3(0,0,1)),
		        dot(hash33(i + vec3(1,0,1)), f - vec3(1,0,1)), u.x),
		    mix(dot(hash33(i + vec3(0,1,1)), f - vec3(0,1,1)),
		        dot(hash33(i + vec3(1,1,1)), f - vec3(1,1,1)), u.x), u.y),
		u.z
	);
}

// Fractal Brownian Motion — stacks noise octaves
float fbm(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	float s = 1.0;
	for (int i = 0; i < octaves; i++) {
		v += a * vnoise(p * s);
		s *= 2.1;
		a *= 0.48;
	}
	return v;
}

// ---------------------------------------------------------------------------
// Terrain colour function
// ---------------------------------------------------------------------------
vec3 terrain_color(vec3 normal, float seed) {
	// Offset normal by seed to make each planet unique
	vec3 p    = normal * 2.2 + vec3(seed * 0.013, seed * 0.007, seed * 0.019);
	float h   = fbm(p, 5);              // –1..1
	float t   = clamp((h + 1.0) * 0.5, 0.0, 1.0);  // remap to 0..1
	float lat = normal.y;              // –1 (S-pole) .. 1 (N-pole)
	float abs_lat = abs(lat);

	// Biome colours
	vec3 deep_ocean = vec3(0.04, 0.14, 0.50);
	vec3 ocean      = vec3(0.08, 0.25, 0.65);
	vec3 shore      = vec3(0.72, 0.68, 0.45);
	vec3 grass      = vec3(0.22, 0.55, 0.18);
	vec3 forest     = vec3(0.08, 0.38, 0.10);
	vec3 desert     = vec3(0.85, 0.73, 0.38);
	vec3 mountain   = vec3(0.50, 0.45, 0.38);
	vec3 snow_cap   = vec3(0.90, 0.95, 1.00);
	vec3 ice_sheet  = vec3(0.75, 0.88, 1.00);
	vec3 lava_rock  = vec3(0.25, 0.05, 0.02);
	vec3 lava_glow  = vec3(1.00, 0.22, 0.00);

	vec3 col;

	// Polar ice caps
	if (abs_lat > 0.82) {
		col = snow_cap;
	} else if (abs_lat > 0.70) {
		col = mix(ice_sheet, snow_cap, smoothstep(0.70, 0.82, abs_lat));
	}
	// Ocean depths
	else if (t < 0.32) {
		col = mix(deep_ocean, ocean, smoothstep(0.18, 0.32, t));
	}
	// Shoreline
	else if (t < 0.36) {
		col = mix(ocean, shore, smoothstep(0.32, 0.36, t));
	}
	// Equatorial desert belt
	else if (abs_lat < 0.18 && t < 0.60) {
		col = mix(shore, desert, smoothstep(0.36, 0.56, t));
	}
	// Grassland / forest transition
	else if (t < 0.52) {
		col = mix(grass, forest, smoothstep(0.40, 0.52, t));
	}
	// Mountain foothills
	else if (t < 0.68) {
		col = mix(forest, mountain, smoothstep(0.52, 0.68, t));
	}
	// High peaks → snow
	else if (t < 0.78) {
		col = mix(mountain, snow_cap, smoothstep(0.68, 0.78, t));
	}
	// Volcanic hot spots (extreme peaks)
	else {
		float lava_t = smoothstep(0.78, 1.0, t);
		col = mix(lava_rock, lava_glow, pow(lava_t, 2.0));
	}

	return col;
}

// ---------------------------------------------------------------------------
// Fragment Shader
// ---------------------------------------------------------------------------
void fragment() {
	vec3  n      = NORMAL;
	float seed   = noise_seed;
	float damage = 1.0 - health_level;

	// Base terrain
	vec3 col = terrain_color(n, seed);

	// ---------- Damage effects ----------
	if (damage > 0.01) {
		// Cracks: high-frequency noise thresholded by damage level
		float crack_noise = vnoise(n * 10.0 + vec3(crack_count * 0.17));
		crack_noise = clamp((crack_noise + 1.0) * 0.5, 0.0, 1.0);

		float crack_threshold = 1.0 - damage * 0.75;
		float crack_factor    = smoothstep(crack_threshold, crack_threshold - 0.06, crack_noise);

		// Lava in cracks
		vec3 lava_col = mix(vec3(0.5, 0.02, 0.0), vec3(1.0, 0.25, 0.0), crack_noise);
		col = mix(col, lava_col, crack_factor * damage);

		// Overall darkening/reddening
		col = mix(col, vec3(0.08, 0.00, 0.00), damage * 0.45);
	}

	// Apply damage tint from Planet.gd
	col *= damage_tint.rgb;

	// Subtle surface roughness variation
	float roughness_noise = clamp(vnoise(n * 5.0) * 0.15 + 0.80, 0.6, 1.0);

	ALBEDO    = col;
	ROUGHNESS = roughness_noise;
	METALLIC  = 0.02;
	SPECULAR  = 0.15;

	// Lava/crack emission in damaged zones
	if (damage > 0.15) {
		float emit_noise = vnoise(n * 9.0 + vec3(crack_count * 0.2));
		emit_noise = clamp((emit_noise + 1.0) * 0.5, 0.0, 1.0);
		float emit_t = smoothstep(1.0 - damage * 0.6, 1.0 - damage * 0.65, emit_noise);
		EMISSION = vec3(1.0, 0.2, 0.0) * emit_t * damage * 2.5;
	}
}
