## Main.gd
## Root scene script — bootstraps all game systems in the correct order
## and wires up cross-system communication.
extends Node3D

# ---------------------------------------------------------------------------
# System nodes (built programmatically for maximum portability)
# ---------------------------------------------------------------------------
var _planet:       Planet
var _civ_manager:  CivilizationManager
var _dis_manager:  DisasterManager
var _effects_mgr:  EffectsManager
var _camera:       OrbitCamera
var _ui:           GameUI

# ---------------------------------------------------------------------------
# Scene Configuration
# ---------------------------------------------------------------------------
const PLANET_RADIUS: float = 10.0
const CAMERA_DIST:   float = 28.0

# ---------------------------------------------------------------------------
# Ready — system boot order matters!
# ---------------------------------------------------------------------------
func _ready() -> void:
	print("Main: Booting Planet Destroyer: God of Catastrophes")
	_setup_environment()
	_setup_lighting()
	_setup_planet()
	_setup_effects()       # before DisasterManager so it can receive signals
	_setup_disasters()
	_setup_civilization()
	_setup_camera()
	_setup_ui()
	_connect_systems()

	print("Main: All systems online.")

# ---------------------------------------------------------------------------
# Environment & Lighting
# ---------------------------------------------------------------------------
func _setup_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"

	var env := Environment.new()
	env.background_mode     = Environment.BG_COLOR
	env.background_color    = Color(0.005, 0.005, 0.02)

	# Ambient glow for the space feel
	env.glow_enabled        = true
	env.glow_intensity      = 0.6
	env.glow_strength       = 1.2
	env.glow_bloom          = 0.15
	env.glow_hdr_threshold  = 0.8

	# Tone mapping
	env.tonemap_mode        = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure    = 1.0
	env.tonemap_white       = 1.0

	# Ambient light (dim starfield)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.04, 0.04, 0.08)
	env.ambient_light_energy = 0.3

	world_env.environment   = env
	add_child(world_env)


func _setup_lighting() -> void:
	# Sun directional light
	var sun       := DirectionalLight3D.new()
	sun.name       = "Sun"
	sun.rotation_degrees = Vector3(-35.0, 45.0, 0.0)
	sun.light_color       = Color(1.0, 0.97, 0.90)
	sun.light_energy      = 1.8
	sun.shadow_enabled    = true
	add_child(sun)

	# Subtle fill light from opposite side
	var fill       := DirectionalLight3D.new()
	fill.name       = "FillLight"
	fill.rotation_degrees = Vector3(35.0, 225.0, 0.0)
	fill.light_color       = Color(0.15, 0.2, 0.3)
	fill.light_energy      = 0.3
	fill.shadow_enabled    = false
	add_child(fill)

	# Starfield point lights (ambient sparkle)
	for i in range(12):
		var star      := OmniLight3D.new()
		star.name      = "Star_%d" % i
		var angle      := TAU * float(i) / 12.0 + randf() * 0.5
		var dist       := randf_range(50.0, 80.0)
		star.position  = Vector3(cos(angle) * dist, randf_range(-20, 20), sin(angle) * dist)
		star.light_color  = Color(0.9 + randf() * 0.1, 0.9 + randf() * 0.1, 1.0)
		star.light_energy = randf_range(0.5, 2.5)
		star.omni_range   = randf_range(20.0, 40.0)
		add_child(star)

# ---------------------------------------------------------------------------
# Planet
# ---------------------------------------------------------------------------
func _setup_planet() -> void:
	_planet                = Planet.new()
	_planet.name           = "Planet"
	_planet.planet_radius  = PLANET_RADIUS
	_planet.rotation_speed = 0.015
	_planet.initial_seed   = randi()
	add_child(_planet)


# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------
func _setup_effects() -> void:
	_effects_mgr      = EffectsManager.new()
	_effects_mgr.name = "EffectsManager"
	add_child(_effects_mgr)


# ---------------------------------------------------------------------------
# Disasters
# ---------------------------------------------------------------------------
func _setup_disasters() -> void:
	_dis_manager      = DisasterManager.new()
	_dis_manager.name = "DisasterManager"
	add_child(_dis_manager)


# ---------------------------------------------------------------------------
# Civilization
# ---------------------------------------------------------------------------
func _setup_civilization() -> void:
	_civ_manager      = CivilizationManager.new()
	_civ_manager.name = "CivilizationManager"
	add_child(_civ_manager)
	_civ_manager.initialize(_planet)


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------
func _setup_camera() -> void:
	_camera                = OrbitCamera.new()
	_camera.name           = "OrbitCamera"
	_camera.target         = _planet
	_camera.orbit_distance = CAMERA_DIST
	_camera.min_distance   = 14.0
	_camera.max_distance   = 55.0
	_camera.fov            = 55.0
	add_child(_camera)


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
func _setup_ui() -> void:
	_ui      = GameUI.new()
	_ui.name = "GameUI"
	_ui.layer = 10
	add_child(_ui)
	_ui.initialize(_planet, _civ_manager)


# ---------------------------------------------------------------------------
# Cross-System Wiring
# ---------------------------------------------------------------------------
func _connect_systems() -> void:
	# DisasterManager needs planet, civ, and effects references
	_dis_manager.initialize(_planet, _civ_manager, _effects_mgr)

	# EffectsManager needs planet and camera references
	_effects_mgr.initialize(_planet, _camera)

	# Camera shake routed through DisasterManager
	_dis_manager.screen_shake_requested.connect(_camera.trigger_shake)

	# Civilization notifications → UI
	_civ_manager.city_spawned.connect(func(city: City) -> void:
		_ui.push_notification("New city founded: %s" % city.city_name,
			Color(0.5, 1.0, 0.5))
	)
	_civ_manager.city_lost.connect(func(city: City) -> void:
		_ui.push_notification("%s has collapsed!" % city.city_name,
			Color(1.0, 0.5, 0.2))
	)
	_civ_manager.civilization_extinct.connect(func() -> void:
		_ui.push_notification("ALL CIVILIZATIONS HAVE PERISHED.", Color(1.0, 0.0, 0.0))
	)
	_civ_manager.total_population_changed.connect(func(_pop: int) -> void:
		pass  # UI polls this in _update_stats
	)

	# Planet critical events → UI notifications
	_planet.planet_destroyed.connect(func() -> void:
		_ui.push_notification("THE PLANET IS DEAD.", Color(1.0, 0.0, 0.0))
	)

	# Disaster events → UI notifications
	_dis_manager.disaster_started.connect(func(dtype: String, _pos: Vector3) -> void:
		var ability = GameManager.ABILITIES.get(dtype, {})
		_ui.push_notification("UNLEASHING: %s" % ability.get("name", dtype),
			ability.get("color", Color.WHITE))
	)

	print("Main: All system connections established.")

# ---------------------------------------------------------------------------
# Input Handling (global shortcuts)
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed:
		return

	match key.keycode:
		KEY_1: GameManager.select_ability("METEOR_STRIKE")
		KEY_2: GameManager.select_ability("VOLCANIC_ERUPTION")
		KEY_3: GameManager.select_ability("EARTHQUAKE")
		KEY_4: GameManager.select_ability("CLIMATE_SHIFT")
		KEY_5: GameManager.select_ability("ICE_AGE")
		KEY_6: GameManager.select_ability("SOLAR_FLARE")
		KEY_7: GameManager.select_ability("BLACK_HOLE")
		KEY_8: GameManager.select_ability("PLANET_CRACK")
		KEY_SPACE: GameManager.toggle_pause()
		KEY_EQUAL: GameManager.set_game_speed(minf(GameManager.game_speed * 2.0, 8.0))
		KEY_MINUS: GameManager.set_game_speed(maxf(GameManager.game_speed * 0.5, 0.25))
