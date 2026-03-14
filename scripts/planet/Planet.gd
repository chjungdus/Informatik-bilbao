## Planet.gd
## Core planet Node3D — manages all planet attributes, visuals, and regions.
## Children: PlanetMesh, AtmosphereMesh, CitiesContainer, EffectMarkers.
extends Node3D
class_name Planet

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal planet_health_changed(new_health: float)
signal atmosphere_changed(new_level: float)
signal temperature_changed(new_temp: float)
signal biosphere_changed(new_level: float)
signal planet_destroyed()
signal region_hit(region: PlanetRegion, disaster_type: String)

# ---------------------------------------------------------------------------
# Exported configuration
# ---------------------------------------------------------------------------
@export var planet_radius: float    = 10.0
@export var rotation_speed: float   = 0.015   ## radians per second
@export var initial_seed: int       = 0        ## 0 = random

# ---------------------------------------------------------------------------
# Planet attributes (0–100 unless noted)
# ---------------------------------------------------------------------------
var planet_health:      float = 100.0
var atmosphere_level:   float = 100.0
var temperature:        float = 15.0    ## Celsius
var tectonic_activity:  float = 20.0
var biosphere_level:    float = 75.0
var is_destroyed:       bool  = false

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------
var _regions:           Array = []       ## Array[PlanetRegion]
var _generator:         PlanetGenerator
var _planet_mesh:       MeshInstance3D
var _atmosphere_mesh:   MeshInstance3D
var _cities_container:  Node3D
var _crack_markers:     Array = []       ## OmniLight3D for cracks/lava
var _surface_material:  ShaderMaterial
var _atmo_material:     ShaderMaterial
var _recovery_timer:    float = 0.0
var _crack_count:       int   = 0

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	_generator = PlanetGenerator.new(planet_radius, initial_seed)
	_build_visual_mesh()
	_build_atmosphere()
	_build_cities_container()
	_generate_regions()
	print("Planet: Initialized with %d regions." % _regions.size())


func _build_visual_mesh() -> void:
	_planet_mesh = MeshInstance3D.new()
	_planet_mesh.name = "PlanetMesh"

	var sphere    := SphereMesh.new()
	sphere.radius  = planet_radius
	sphere.height  = planet_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings           = 32
	_planet_mesh.mesh = sphere

	# Load or create surface shader material
	_surface_material = _create_surface_material()
	_planet_mesh.material_override = _surface_material

	add_child(_planet_mesh)


func _build_atmosphere() -> void:
	_atmosphere_mesh = MeshInstance3D.new()
	_atmosphere_mesh.name = "AtmosphereMesh"

	var sphere    := SphereMesh.new()
	sphere.radius  = planet_radius * 1.06
	sphere.height  = planet_radius * 2.12
	sphere.radial_segments = 48
	sphere.rings           = 24
	_atmosphere_mesh.mesh = sphere

	_atmo_material = _create_atmosphere_material()
	_atmosphere_mesh.material_override = _atmo_material

	add_child(_atmosphere_mesh)


func _build_cities_container() -> void:
	_cities_container      = Node3D.new()
	_cities_container.name = "CitiesContainer"
	add_child(_cities_container)


func _generate_regions() -> void:
	_regions = _generator.generate_regions()

# ---------------------------------------------------------------------------
# Per-Frame
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if is_destroyed:
		return

	# Slow planetary rotation
	rotate_y(rotation_speed * delta * GameManager.game_speed)

	# Region natural recovery
	_recovery_timer += delta * GameManager.game_speed
	if _recovery_timer >= 1.0:
		_recovery_timer = 0.0
		_tick_region_recovery(1.0)

	# Keep atmosphere shader in sync
	_atmo_material.set_shader_parameter("atmosphere_level",
		atmosphere_level / 100.0)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func get_regions() -> Array:
	return _regions


func get_city_spawn_positions() -> Array:
	return _generator.get_city_spawn_candidates(_regions)


## Returns the world-space position on the surface closest to the given world point.
func project_to_surface(world_point: Vector3) -> Vector3:
	var local_pt: Vector3 = to_local(world_point)
	return to_global(local_pt.normalized() * planet_radius)


## Returns all regions whose influence area overlaps the given world point.
func get_regions_at(world_pos: Vector3) -> Array:
	var local_pt := to_local(world_pos)
	var hits: Array = []
	for reg: PlanetRegion in _regions:
		if reg.contains_point(local_pt):
			hits.append(reg)
	return hits


## Returns the single nearest region to the given local position.
func get_nearest_region(local_pos: Vector3) -> PlanetRegion:
	var best: PlanetRegion = null
	var best_dist := INF
	for reg: PlanetRegion in _regions:
		var d := reg.surface_position.distance_to(local_pos)
		if d < best_dist:
			best_dist = d
			best      = reg
	return best

# ---------------------------------------------------------------------------
# Attribute Mutations (called by DisasterManager)
# ---------------------------------------------------------------------------

func apply_health_damage(amount: float) -> void:
	if is_destroyed:
		return
	planet_health = maxf(0.0, planet_health - amount)
	planet_health_changed.emit(planet_health)
	_update_health_visuals()
	if planet_health <= 0.0:
		_trigger_destruction()


func apply_atmosphere_damage(amount: float) -> void:
	atmosphere_level = maxf(0.0, atmosphere_level - amount)
	atmosphere_changed.emit(atmosphere_level)


func apply_temperature_delta(delta_t: float) -> void:
	temperature = clampf(temperature + delta_t, -100.0, 100.0)
	temperature_changed.emit(temperature)


func apply_biosphere_damage(amount: float) -> void:
	biosphere_level = maxf(0.0, biosphere_level - amount)
	biosphere_changed.emit(biosphere_level)


func apply_tectonic_stress(amount: float) -> void:
	tectonic_activity = clampf(tectonic_activity + amount, 0.0, 100.0)


## Mark a surface area as a disaster zone (visual + region state update).
func apply_disaster_zone(world_pos: Vector3, disaster_type: String,
		radius: float) -> void:
	var local_pos := to_local(world_pos)
	for reg: PlanetRegion in _regions:
		if reg.surface_position.distance_to(local_pos) <= radius:
			_apply_region_effect(reg, disaster_type)
			region_hit.emit(reg, disaster_type)

	_spawn_effect_light(world_pos, disaster_type)


## Add a visible crack / lava glow at the given world position.
func add_crack_marker(world_pos: Vector3) -> void:
	_crack_count += 1
	var light        := OmniLight3D.new()
	light.position    = to_local(world_pos) * 1.02
	light.light_color = Color(1.0, 0.15, 0.0)
	light.light_energy = 3.0
	light.omni_range  = 3.0
	add_child(light)
	_crack_markers.append(light)

	# Update shader to show more cracking as health decreases
	_surface_material.set_shader_parameter("crack_count",
		float(_crack_count))

# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------

func _update_health_visuals() -> void:
	var health_frac := planet_health / 100.0
	_surface_material.set_shader_parameter("health_level", health_frac)

	# Tint the planet redder as it takes more damage
	var damage_tint := Color(1.0, health_frac, health_frac * 0.8)
	_surface_material.set_shader_parameter("damage_tint", damage_tint)


func _apply_region_effect(reg: PlanetRegion, disaster_type: String) -> void:
	match disaster_type:
		"METEOR_STRIKE":     reg.apply_fire()
		"VOLCANIC_ERUPTION": reg.apply_lava()
		"ICE_AGE":           reg.apply_freeze()
		"SOLAR_FLARE":       reg.apply_radiation(40.0)
		"BLACK_HOLE":        reg.apply_fire(); reg.apply_radiation(20.0)
		"PLANET_CRACK":      reg.apply_lava()


func _spawn_effect_light(world_pos: Vector3, disaster_type: String) -> void:
	var light      := OmniLight3D.new()
	light.position  = to_local(world_pos)

	match disaster_type:
		"METEOR_STRIKE":
			light.light_color  = Color(1.0, 0.5, 0.1)
			light.light_energy = 8.0
			light.omni_range   = 5.0
		"VOLCANIC_ERUPTION":
			light.light_color  = Color(1.0, 0.2, 0.0)
			light.light_energy = 6.0
			light.omni_range   = 6.0
		"ICE_AGE":
			light.light_color  = Color(0.6, 0.9, 1.0)
			light.light_energy = 3.0
			light.omni_range   = 8.0
		"BLACK_HOLE":
			light.light_color  = Color(0.3, 0.0, 0.8)
			light.light_energy = 10.0
			light.omni_range   = 7.0
		_:
			light.light_color  = Color(1.0, 1.0, 0.5)
			light.light_energy = 4.0
			light.omni_range   = 4.0

	add_child(light)

	# Auto-remove the effect light after a short time
	var timer := get_tree().create_timer(6.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(light):
			light.queue_free()
	)


func _tick_region_recovery(dt: float) -> void:
	for reg: PlanetRegion in _regions:
		reg.tick_recovery(dt)


func _trigger_destruction() -> void:
	is_destroyed = true

	# Dramatic colour change
	_surface_material.set_shader_parameter("health_level",   0.0)
	_surface_material.set_shader_parameter("damage_tint",    Color(0.6, 0.0, 0.0))
	_surface_material.set_shader_parameter("crack_count",    999.0)

	print("Planet: DESTROYED!")
	planet_destroyed.emit()

# ---------------------------------------------------------------------------
# Material Factories
# ---------------------------------------------------------------------------

func _create_surface_material() -> ShaderMaterial:
	var mat    := ShaderMaterial.new()
	var shader := load("res://effects/shaders/planet_surface.gdshader")
	if shader:
		mat.shader = shader
	else:
		# Fallback: simple StandardMaterial3D disguised as ShaderMaterial
		mat = _fallback_surface_material()
		return mat

	mat.set_shader_parameter("health_level",  1.0)
	mat.set_shader_parameter("damage_tint",   Color(1.0, 1.0, 1.0))
	mat.set_shader_parameter("crack_count",   0.0)
	mat.set_shader_parameter("noise_seed",    float(initial_seed))
	return mat


func _create_atmosphere_material() -> ShaderMaterial:
	var mat    := ShaderMaterial.new()
	var shader := load("res://effects/shaders/atmosphere.gdshader")
	if shader:
		mat.shader = shader
	else:
		mat = _fallback_atmosphere_material()
		return mat

	mat.set_shader_parameter("atmosphere_level", 1.0)
	mat.set_shader_parameter("atmo_color",       Color(0.3, 0.6, 1.0, 0.3))
	return mat


## Procedural StandardMaterial3D used when the custom shader file isn't found.
func _fallback_surface_material() -> ShaderMaterial:
	# Return a ShaderMaterial wrapping a minimal inline shader
	var mat    := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;
uniform float health_level : hint_range(0.0, 1.0) = 1.0;
uniform vec4 damage_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float crack_count = 0.0;
uniform float noise_seed = 0.0;

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
	         dot(p, vec3(269.5, 183.3, 246.1)),
	         dot(p, vec3(113.5, 271.9, 124.6)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float simplex3(vec3 p) {
	vec3 i  = floor(p + dot(p, vec3(1.0/3.0)));
	vec3 x0 = p - i + dot(i, vec3(1.0/6.0));
	vec3 g  = step(x0.yzx, x0.xyz);
	vec3 l  = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);
	vec3 x1 = x0 - i1 + 1.0/6.0;
	vec3 x2 = x0 - i2 + 1.0/3.0;
	vec3 x3 = x0 - 0.5;
	vec4 w  = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
	vec4 d  = vec4(dot(hash3(i),        x0),
	               dot(hash3(i + i1),   x1),
	               dot(hash3(i + i2),   x2),
	               dot(hash3(i + vec3(1.0)), x3));
	return dot(w*w*w*w, d) * 52.0;
}

void fragment() {
	vec3 n = NORMAL;
	float lat = n.y;
	float h   = simplex3(n * 2.5 + vec3(noise_seed * 0.01));
	float t   = clamp((h + 1.0) * 0.5, 0.0, 1.0);

	// Base terrain colours
	vec3 ocean    = vec3(0.08, 0.25, 0.65);
	vec3 land     = vec3(0.22, 0.55, 0.18);
	vec3 mountain = vec3(0.50, 0.45, 0.38);
	vec3 ice      = vec3(0.85, 0.95, 1.00);
	vec3 desert   = vec3(0.85, 0.73, 0.38);
	vec3 lava     = vec3(1.00, 0.20, 0.00);

	vec3 col;
	float abs_lat = abs(lat);

	if (abs_lat > 0.75) {
		col = ice;
	} else if (t < 0.38) {
		col = ocean;
	} else if (abs_lat < 0.15 && t > 0.55) {
		col = desert;
	} else if (t < 0.62) {
		col = land;
	} else if (t < 0.78) {
		col = mountain;
	} else {
		col = mix(mountain, lava, smoothstep(0.78, 0.95, t));
	}

	// Health-based cracking/darkening
	float damage = 1.0 - health_level;
	float crack  = step(1.0 - damage * 0.8,
	                    simplex3(n * 8.0 + vec3(crack_count * 0.1)) * 0.5 + 0.5);
	col = mix(col, vec3(0.1, 0.0, 0.0), crack * damage);
	col *= damage_tint.rgb;

	ALBEDO = col;
	ROUGHNESS = 0.85;
	METALLIC  = 0.05;
}
"""
	mat.shader = shader
	mat.set_shader_parameter("health_level", 1.0)
	mat.set_shader_parameter("damage_tint",  Color(1.0, 1.0, 1.0))
	mat.set_shader_parameter("crack_count",  0.0)
	mat.set_shader_parameter("noise_seed",   float(initial_seed))
	return mat


func _fallback_atmosphere_material() -> ShaderMaterial:
	var mat    := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded;
uniform float atmosphere_level : hint_range(0.0, 1.0) = 1.0;
uniform vec4 atmo_color : source_color = vec4(0.3, 0.6, 1.0, 0.3);

void fragment() {
	float rim    = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float alpha  = pow(rim, 3.0) * atmosphere_level * 0.7;
	ALBEDO       = atmo_color.rgb;
	ALPHA        = alpha;
}
"""
	mat.shader = shader
	mat.set_shader_parameter("atmosphere_level", 1.0)
	mat.set_shader_parameter("atmo_color", Color(0.3, 0.6, 1.0, 0.3))
	return mat
