## DisasterManager.gd
## Routes disaster triggers from GameManager to specific disaster handlers.
## Also coordinates damage application to Planet and CivilizationManager.
extends Node
class_name DisasterManager

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal disaster_started(disaster_type: String, world_pos: Vector3)
signal disaster_ended(disaster_type: String)
signal screen_shake_requested(intensity: float, duration: float)

# ---------------------------------------------------------------------------
# References (set by Main.gd)
# ---------------------------------------------------------------------------
var planet:       Planet
var civ_manager:  CivilizationManager
var effects_mgr:  Node   ## EffectsManager

# ---------------------------------------------------------------------------
# Active disasters tracking
# ---------------------------------------------------------------------------
var _active_disasters: Array = []   ## Array[Node] — currently live disaster nodes

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	GameManager.disaster_triggered.connect(_on_disaster_triggered)


func initialize(planet_node: Planet, civ_mgr: CivilizationManager,
		effects_manager: Node) -> void:
	planet      = planet_node
	civ_manager = civ_mgr
	effects_mgr = effects_manager

# ---------------------------------------------------------------------------
# Main Dispatcher
# ---------------------------------------------------------------------------
func _on_disaster_triggered(disaster_type: String, world_pos: Vector3) -> void:
	print("DisasterManager: Triggering '%s' at %s" % [disaster_type, world_pos])
	disaster_started.emit(disaster_type, world_pos)

	var params: Dictionary = GameData.DISASTER_PARAMS.get(disaster_type, {})

	match disaster_type:
		"METEOR_STRIKE":      _trigger_meteor(world_pos, params)
		"VOLCANIC_ERUPTION":  _trigger_volcano(world_pos, params)
		"EARTHQUAKE":         _trigger_earthquake(world_pos, params)
		"CLIMATE_SHIFT":      _trigger_climate_shift(params)
		"ICE_AGE":            _trigger_ice_age(world_pos, params)
		"SOLAR_FLARE":        _trigger_solar_flare(params)
		"BLACK_HOLE":         _trigger_black_hole(world_pos, params)
		"PLANET_CRACK":       _trigger_planet_crack(world_pos, params)
		_:
			push_error("DisasterManager: Unknown disaster '%s'" % disaster_type)

# ---------------------------------------------------------------------------
# Meteor Strike
# ---------------------------------------------------------------------------
func _trigger_meteor(world_pos: Vector3, params: Dictionary) -> void:
	var impact_radius: float = params.get("impact_radius", 2.0)

	# Spawn meteor projectile above the planet
	var meteor := _create_meteor_node(world_pos)
	add_child(meteor)
	_active_disasters.append(meteor)

	# Apply immediate effects after travel time (simulated via timer)
	var travel_time := 2.5
	var timer       := get_tree().create_timer(travel_time)
	timer.timeout.connect(func() -> void:
		_apply_zone_damage("METEOR_STRIKE", world_pos, impact_radius, params)
		planet.apply_disaster_zone(world_pos, "METEOR_STRIKE", impact_radius)
		planet.add_crack_marker(world_pos)
		screen_shake_requested.emit(0.7, 0.8)
		if is_instance_valid(meteor):
			meteor.queue_free()
		disaster_ended.emit("METEOR_STRIKE")
	)


func _create_meteor_node(target: Vector3) -> Node3D:
	var node        := Node3D.new()
	node.name        = "Meteor"

	var mesh_inst   := MeshInstance3D.new()
	var sphere       := SphereMesh.new()
	sphere.radius    = 0.25
	sphere.height    = 0.5
	mesh_inst.mesh   = sphere
	var mat          := StandardMaterial3D.new()
	mat.albedo_color  = Color(0.7, 0.3, 0.1)
	mat.emission_enabled = true
	mat.emission     = Color(1.0, 0.5, 0.2)
	mat.emission_energy_multiplier = 2.0
	mesh_inst.material_override = mat
	node.add_child(mesh_inst)

	var light         := OmniLight3D.new()
	light.light_color  = Color(1.0, 0.5, 0.1)
	light.light_energy = 4.0
	light.omni_range   = 3.0
	node.add_child(light)

	# Start far above the planet surface
	var surface_dir := target.normalized()
	node.global_position = target + surface_dir * 25.0

	# Animate toward impact
	var tween := get_tree().create_tween()
	tween.tween_property(node, "global_position", target + surface_dir * 0.5, 2.5) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)

	return node

# ---------------------------------------------------------------------------
# Volcanic Eruption
# ---------------------------------------------------------------------------
func _trigger_volcano(world_pos: Vector3, params: Dictionary) -> void:
	var radius: float = params.get("impact_radius", 3.0)
	var duration: float = params.get("lava_duration", 45.0)

	_apply_zone_damage("VOLCANIC_ERUPTION", world_pos, radius, params)
	planet.apply_disaster_zone(world_pos, "VOLCANIC_ERUPTION", radius)
	planet.apply_atmosphere_damage(params.get("atmosphere_loss", 5.0))
	planet.apply_temperature_delta(params.get("temp_increase", 3.0))
	screen_shake_requested.emit(0.5, 1.5)
	disaster_ended.emit("VOLCANIC_ERUPTION")

# ---------------------------------------------------------------------------
# Earthquake
# ---------------------------------------------------------------------------
func _trigger_earthquake(world_pos: Vector3, params: Dictionary) -> void:
	var radius: float   = params.get("impact_radius", 4.0)
	var shake_dur: float = params.get("shake_duration", 3.0)

	_apply_zone_damage("EARTHQUAKE", world_pos, radius, params)
	planet.apply_disaster_zone(world_pos, "EARTHQUAKE", radius * 0.5)
	planet.apply_tectonic_stress(params.get("tectonic_boost", 15.0))
	screen_shake_requested.emit(1.0, shake_dur)
	disaster_ended.emit("EARTHQUAKE")

# ---------------------------------------------------------------------------
# Climate Shift
# ---------------------------------------------------------------------------
func _trigger_climate_shift(params: Dictionary) -> void:
	# Temperature goes up or down based on current game temperature
	var current_temp: float = planet.temperature
	var delta_t: float
	if current_temp > 20.0:
		delta_t = -params.get("temp_delta", 10.0)   # Cool it down
	else:
		delta_t = params.get("temp_delta", 10.0)    # Heat it up

	planet.apply_temperature_delta(delta_t)
	planet.apply_biosphere_damage(params.get("biosphere_loss", 5.0))
	planet.apply_health_damage(params.get("health_damage", 3.0))
	disaster_ended.emit("CLIMATE_SHIFT")

# ---------------------------------------------------------------------------
# Ice Age
# ---------------------------------------------------------------------------
func _trigger_ice_age(world_pos: Vector3, params: Dictionary) -> void:
	planet.apply_temperature_delta(params.get("temp_delta", -30.0))
	planet.apply_biosphere_damage(params.get("biosphere_loss", 30.0))
	planet.apply_health_damage(params.get("health_damage", 15.0))

	# Damage all cities globally
	var all_cities: Array = civ_manager.get_all_cities()
	for city: City in all_cities:
		city.on_disaster_hit("ICE_AGE", 0.0, 999.0)

	screen_shake_requested.emit(0.3, 0.5)
	disaster_ended.emit("ICE_AGE")

# ---------------------------------------------------------------------------
# Solar Flare
# ---------------------------------------------------------------------------
func _trigger_solar_flare(params: Dictionary) -> void:
	planet.apply_atmosphere_damage(params.get("atmosphere_loss", 10.0))
	planet.apply_biosphere_damage(params.get("biosphere_loss", 8.0))
	planet.apply_health_damage(params.get("health_damage", 5.0))

	# Only affects high-tech cities
	var all_cities: Array = civ_manager.get_all_cities()
	for city: City in all_cities:
		if city.tech_level > 10.0:
			city.on_disaster_hit("SOLAR_FLARE", 0.0, 999.0)

	disaster_ended.emit("SOLAR_FLARE")

# ---------------------------------------------------------------------------
# Black Hole
# ---------------------------------------------------------------------------
func _trigger_black_hole(world_pos: Vector3, params: Dictionary) -> void:
	var radius: float   = params.get("impact_radius", 5.0)
	var duration: float = params.get("duration", 10.0)

	# Create black hole visual node
	var bh := _create_black_hole_node(world_pos, duration)
	add_child(bh)
	_active_disasters.append(bh)

	# Gradually apply damage over duration
	var tick_interval := 1.0
	var ticks         := int(duration / tick_interval)

	for i in range(ticks):
		var t := get_tree().create_timer(float(i) * tick_interval)
		t.timeout.connect(func() -> void:
			if not is_instance_valid(planet):
				return
			_apply_zone_damage("BLACK_HOLE", world_pos, radius * 0.5,
				{"city_damage": 0.1, "impact_radius": radius})
			planet.apply_atmosphere_damage(1.5)
			planet.apply_health_damage(2.0)
		)

	var end_timer := get_tree().create_timer(duration)
	end_timer.timeout.connect(func() -> void:
		if is_instance_valid(bh):
			bh.queue_free()
		disaster_ended.emit("BLACK_HOLE")
	)


func _create_black_hole_node(pos: Vector3, duration: float) -> Node3D:
	var node        := Node3D.new()
	node.name        = "BlackHole"
	node.global_position = pos

	var light        := OmniLight3D.new()
	light.light_color = Color(0.3, 0.0, 0.8)
	light.light_energy = 12.0
	light.omni_range  = 8.0
	light.shadow_enabled = true
	node.add_child(light)

	# Pulsing animation
	var tween := get_tree().create_tween().set_loops()
	tween.tween_property(light, "light_energy", 16.0, 0.5)
	tween.tween_property(light, "light_energy", 8.0, 0.5)

	return node

# ---------------------------------------------------------------------------
# Planet Crack (Ultimate)
# ---------------------------------------------------------------------------
func _trigger_planet_crack(world_pos: Vector3, params: Dictionary) -> void:
	var radius: float = params.get("impact_radius", 20.0)

	# Mass destruction
	_apply_zone_damage("PLANET_CRACK", world_pos, radius, params)
	planet.apply_disaster_zone(world_pos, "PLANET_CRACK", radius)
	planet.apply_health_damage(params.get("health_damage", 60.0))
	planet.apply_atmosphere_damage(params.get("atmosphere_loss", 40.0))
	planet.apply_tectonic_stress(params.get("tectonic_boost", 50.0))
	planet.apply_biosphere_damage(30.0)
	planet.add_crack_marker(world_pos)
	planet.add_crack_marker(world_pos + Vector3(3, 0, 0))
	planet.add_crack_marker(world_pos + Vector3(-3, 0, 0))

	screen_shake_requested.emit(2.0, 4.0)
	disaster_ended.emit("PLANET_CRACK")

# ---------------------------------------------------------------------------
# Zone Damage Application
# ---------------------------------------------------------------------------

## Apply disaster damage to all cities within the impact radius.
func _apply_zone_damage(disaster_type: String, world_pos: Vector3,
		radius: float, params: Dictionary) -> void:
	var all_cities: Array = civ_manager.get_all_cities()

	for city: City in all_cities:
		var dist: float = city.global_position.distance_to(world_pos)
		if dist <= radius:
			city.on_disaster_hit(disaster_type, dist, radius)
			print("DisasterManager: %s hit '%s' (dist=%.2f)" % [
				disaster_type, city.city_name, dist])

	# Apply planet-level attribute damage
	planet.apply_health_damage(params.get("health_damage", 0.0))
