## City.gd
## Individual city simulation node placed on the planet surface.
## Handles growth, disaster response, defense building, and visual feedback.
extends Node3D
class_name City

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal city_destroyed(city: City)
signal city_rebuilt(city: City)
signal population_changed(city: City, new_pop: int)
signal tech_level_changed(city: City, new_level: float)

# ---------------------------------------------------------------------------
# City Attributes
# ---------------------------------------------------------------------------
@export var city_name:       String = "City"
@export var population:      int    = 1000
@export var tech_level:      float  = 1.0
@export var defense_level:   float  = 1.0
@export var culture_level:   float  = 1.0
@export var region_type:     int    = GameData.RegionType.LAND

# Growth rates (per game-second)
@export var pop_growth_rate:     float = 0.018
@export var tech_growth_rate:    float = 0.0008
@export var defense_growth_rate: float = 0.0004
@export var culture_growth_rate: float = 0.0006

# State
var is_collapsed:   bool  = false
var rebuild_timer:  float = 0.0
var rebuild_time:   float = 35.0
var is_evacuating:  bool  = false
var evacuation_pop: int   = 0

# Planetary defenses unlocked at tech thresholds
var has_shield:     bool  = false
var has_satellite:  bool  = false
var has_defense_gun: bool = false

# Surface normal (outward from planet center)
var surface_normal: Vector3 = Vector3.UP
var planet_radius:  float   = 10.0

# ---------------------------------------------------------------------------
# Visual nodes
# ---------------------------------------------------------------------------
var _body_mesh:     MeshInstance3D
var _light:         OmniLight3D
var _shield_mesh:   MeshInstance3D
var _label:         Label3D
var _tick_timer:    float = 0.0
var _pulse_time:    float = 0.0

# City size tiers: 0=village, 1=town, 2=city, 3=metropolis
const POP_TIERS: Array = [5000, 50000, 500000, 5000000]
const TIER_SCALE: Array = [0.10, 0.16, 0.22, 0.30]
const TIER_COLORS: Array = [
	Color(0.8, 0.9, 0.6),
	Color(0.9, 0.9, 0.5),
	Color(1.0, 0.95, 0.3),
	Color(1.0, 1.0, 0.8)
]

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_visuals()
	_update_visuals()


func _build_visuals() -> void:
	# Main city body (box mesh)
	_body_mesh          = MeshInstance3D.new()
	_body_mesh.name     = "CityBody"
	var box             := BoxMesh.new()
	box.size            = Vector3(0.18, 0.18, 0.18)
	_body_mesh.mesh     = box
	_body_mesh.material_override = _make_city_material()
	add_child(_body_mesh)

	# Point light glow
	_light              = OmniLight3D.new()
	_light.name         = "CityLight"
	_light.light_color  = Color(1.0, 0.95, 0.6)
	_light.light_energy = 1.5
	_light.omni_range   = 1.5
	add_child(_light)

	# City name label
	_label              = Label3D.new()
	_label.name         = "CityLabel"
	_label.text         = city_name
	_label.font_size    = 8
	_label.modulate     = Color(1.0, 1.0, 1.0, 0.85)
	_label.position     = Vector3(0, 0.25, 0)
	_label.billboard    = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	add_child(_label)


func _make_city_material() -> StandardMaterial3D:
	var mat             := StandardMaterial3D.new()
	mat.albedo_color     = TIER_COLORS[0]
	mat.emission_enabled = true
	mat.emission         = TIER_COLORS[0]
	mat.emission_energy_multiplier = 0.5
	return mat

# ---------------------------------------------------------------------------
# Per-Frame
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	var dt := delta * GameManager.game_speed

	_pulse_time += dt
	_tick_timer  += dt

	# Pulsing glow effect
	_light.light_energy = 1.2 + sin(_pulse_time * 2.0) * 0.3

	if is_collapsed:
		_process_rebuild(dt)
		return

	if _tick_timer >= 1.0:
		_tick_timer = 0.0
		_tick_growth(1.0)
		_check_tech_milestones()
		_update_visuals()


func _process_rebuild(dt: float) -> void:
	rebuild_timer += dt
	if rebuild_timer >= rebuild_time:
		_complete_rebuild()


func _tick_growth(dt: float) -> void:
	if population <= 0:
		return

	# Growth is influenced by region fertility and global biosphere
	var growth_mult := 1.0
	if region_type == GameData.RegionType.DESERT:
		growth_mult = 0.5
	elif region_type == GameData.RegionType.FOREST:
		growth_mult = 1.3

	# Tech growth
	tech_level    = minf(tech_level    + tech_growth_rate    * dt, 100.0)
	defense_level = minf(defense_level + defense_growth_rate * dt, 100.0)
	culture_level = minf(culture_level + culture_growth_rate * dt, 100.0)

	# Population growth (exponential, capped softly)
	var old_pop := population
	population   = int(float(population) * (1.0 + pop_growth_rate * growth_mult * dt))
	population   = mini(population, 100_000_000)   # hard cap

	if population != old_pop:
		population_changed.emit(self, population)

# ---------------------------------------------------------------------------
# Disaster Response
# ---------------------------------------------------------------------------

## Called by DisasterManager when a disaster hits nearby.
func on_disaster_hit(disaster_type: String, distance: float,
		disaster_radius: float) -> void:
	if is_collapsed:
		return

	var intensity := 1.0 - clampf(distance / disaster_radius, 0.0, 1.0)
	var params     = GameData.DISASTER_PARAMS.get(disaster_type, {})
	var base_dmg  := params.get("city_damage", 0.3) as float

	# Defense reduces incoming damage
	var defense_reduction := clampf(defense_level / 100.0, 0.0, 0.8)
	if has_shield:
		defense_reduction = minf(defense_reduction + 0.25, 0.95)

	var effective_dmg := base_dmg * intensity * (1.0 - defense_reduction)

	# Apply population loss
	var killed := int(float(population) * effective_dmg)
	population  = maxi(0, population - killed)
	population_changed.emit(self, population)

	# Special effects per disaster type
	match disaster_type:
		"SOLAR_FLARE":
			tech_level = maxf(1.0, tech_level * (1.0 - params.get("city_tech_loss", 0.3)))
			tech_level_changed.emit(self, tech_level)
			has_satellite = false   # Satellites get fried
		"ICE_AGE":
			pop_growth_rate = maxf(0.001, pop_growth_rate * 0.3)
		"VOLCANIC_ERUPTION":
			if effective_dmg > 0.4:
				_trigger_collapse()
				return

	# Collapse if population hits zero or massive damage
	if population <= 0 or effective_dmg > 0.85:
		_trigger_collapse()
	elif effective_dmg > 0.3:
		_begin_evacuation(int(float(population) * 0.4))


func _begin_evacuation(evac_pop: int) -> void:
	is_evacuating  = true
	evacuation_pop = evac_pop
	population    -= evac_pop
	print("%s: Evacuating %d citizens." % [city_name, evac_pop])


func _trigger_collapse() -> void:
	is_collapsed   = true
	rebuild_timer  = 0.0
	population     = 0
	has_shield     = false
	has_defense_gun = false

	# Visual feedback: city goes dark and red
	var mat: StandardMaterial3D = _body_mesh.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.4, 0.0, 0.0)
		mat.emission     = Color(0.2, 0.0, 0.0)
	_light.light_color  = Color(0.5, 0.0, 0.0)
	_light.light_energy = 0.4
	if _label:
		_label.modulate = Color(0.5, 0.2, 0.2, 0.6)

	print("%s: COLLAPSED." % city_name)
	city_destroyed.emit(self)


func _complete_rebuild() -> void:
	is_collapsed   = false
	rebuild_timer  = 0.0
	population     = maxi(100, evacuation_pop / 2 + 50)
	evacuation_pop = 0
	is_evacuating  = false
	tech_level     = maxf(1.0, tech_level * 0.5)
	pop_growth_rate = 0.018   # reset growth rate

	_update_visuals()
	print("%s: Rebuilt with population %d." % [city_name, population])
	city_rebuilt.emit(self)

# ---------------------------------------------------------------------------
# Tech Milestones
# ---------------------------------------------------------------------------
func _check_tech_milestones() -> void:
	if tech_level >= 20.0 and population > 10_000 and not has_satellite:
		has_satellite = true
		print("%s: Built orbital satellite!" % city_name)

	if tech_level >= 35.0 and population > 50_000 and not has_shield:
		has_shield = true
		_build_shield_visual()
		print("%s: Activated planetary shield!" % city_name)

	if tech_level >= 50.0 and population > 100_000 and not has_defense_gun:
		has_defense_gun = true
		print("%s: Constructed defense cannon!" % city_name)

# ---------------------------------------------------------------------------
# Visual Updates
# ---------------------------------------------------------------------------
func _update_visuals() -> void:
	var tier  := _get_tier()
	var scale := TIER_SCALE[tier]
	_body_mesh.scale = Vector3.ONE * scale

	var mat: StandardMaterial3D = _body_mesh.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = TIER_COLORS[tier]
		mat.emission     = TIER_COLORS[tier]
		mat.emission_energy_multiplier = 0.5 + float(tier) * 0.3

	_light.light_color  = TIER_COLORS[tier]
	_light.light_energy = 1.0 + float(tier) * 0.8
	_light.omni_range   = 1.0 + float(tier) * 0.8

	if _label:
		_label.text = "%s\n%s" % [city_name, _format_pop(population)]


func _build_shield_visual() -> void:
	if _shield_mesh:
		return
	_shield_mesh = MeshInstance3D.new()
	var sphere   := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.70
	_shield_mesh.mesh = sphere

	var mat                := StandardMaterial3D.new()
	mat.albedo_color        = Color(0.3, 0.7, 1.0, 0.15)
	mat.emission_enabled    = true
	mat.emission            = Color(0.3, 0.7, 1.0)
	mat.emission_energy_multiplier = 0.4
	mat.transparency        = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_mesh.material_override = mat
	add_child(_shield_mesh)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _get_tier() -> int:
	for i in range(POP_TIERS.size() - 1, -1, -1):
		if population >= POP_TIERS[i]:
			return i
	return 0


static func _format_pop(pop: int) -> String:
	if pop >= 1_000_000:
		return "%.1fM" % (float(pop) / 1_000_000.0)
	elif pop >= 1000:
		return "%.1fK" % (float(pop) / 1000.0)
	return str(pop)


func get_stats() -> Dictionary:
	return {
		"name":         city_name,
		"population":   population,
		"tech_level":   tech_level,
		"defense_level": defense_level,
		"culture_level": culture_level,
		"is_collapsed": is_collapsed,
		"has_shield":   has_shield,
		"has_satellite": has_satellite
	}
