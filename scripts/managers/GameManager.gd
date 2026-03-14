## GameManager.gd
## Autoload Singleton — Central orchestrator for all game systems.
## Manages game state, player energy, ability selection, and cooldowns.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal disaster_selected(ability_type: String)
signal disaster_triggered(ability_type: String, world_pos: Vector3)
signal game_state_changed(new_state: int)
signal energy_changed(current: float, maximum: float)
signal game_speed_changed(new_speed: float)

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------
enum GameState {
	OBSERVING,   ## Player watches the planet freely
	TARGETING,   ## Player has selected a power and is aiming
	PAUSED       ## Game paused
}

# ---------------------------------------------------------------------------
# Ability Definitions — single source of truth for all player powers
# ---------------------------------------------------------------------------
const ABILITIES: Dictionary = {
	"METEOR_STRIKE": {
		"name":         "Meteor Strike",
		"description":  "Hurl a massive meteor at the planet surface.",
		"cooldown":     5.0,
		"energy_cost":  20.0,
		"color":        Color(1.0, 0.4, 0.1),
		"icon":         "☄"
	},
	"VOLCANIC_ERUPTION": {
		"name":         "Volcanic Eruption",
		"description":  "Trigger catastrophic volcanic activity.",
		"cooldown":     8.0,
		"energy_cost":  30.0,
		"color":        Color(1.0, 0.2, 0.0),
		"icon":         "V"
	},
	"EARTHQUAKE": {
		"name":         "Earthquake",
		"description":  "Shatter tectonic plates and destroy cities.",
		"cooldown":     6.0,
		"energy_cost":  25.0,
		"color":        Color(0.8, 0.6, 0.2),
		"icon":         "E"
	},
	"CLIMATE_SHIFT": {
		"name":         "Climate Manipulation",
		"description":  "Drastically alter planetary temperature.",
		"cooldown":     12.0,
		"energy_cost":  35.0,
		"color":        Color(0.2, 0.8, 1.0),
		"icon":         "C"
	},
	"ICE_AGE": {
		"name":         "Ice Age",
		"description":  "Plunge the world into glacial darkness.",
		"cooldown":     25.0,
		"energy_cost":  60.0,
		"color":        Color(0.7, 0.9, 1.0),
		"icon":         "I"
	},
	"SOLAR_FLARE": {
		"name":         "Solar Flare",
		"description":  "Unleash radiation that cripples advanced tech.",
		"cooldown":     15.0,
		"energy_cost":  45.0,
		"color":        Color(1.0, 0.9, 0.2),
		"icon":         "S"
	},
	"BLACK_HOLE": {
		"name":         "Black Hole",
		"description":  "Spawn a gravitational singularity.",
		"cooldown":     30.0,
		"energy_cost":  80.0,
		"color":        Color(0.4, 0.0, 0.8),
		"icon":         "B"
	},
	"PLANET_CRACK": {
		"name":         "Planet Crack",
		"description":  "ULTIMATE — Tear the planet asunder.",
		"cooldown":     120.0,
		"energy_cost":  200.0,
		"color":        Color(1.0, 0.0, 0.0),
		"icon":         "!"
	}
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var current_state: int           = GameState.OBSERVING
var selected_ability: String     = ""
var cosmic_energy: float         = 100.0
var max_cosmic_energy: float     = 100.0
var energy_regen_rate: float     = 4.0        # energy per second
var ability_cooldowns: Dictionary = {}

var game_time: float             = 0.0        # total elapsed seconds
var game_speed: float            = 1.0
var is_paused: bool              = false

# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------
func _ready() -> void:
	for key in ABILITIES.keys():
		ability_cooldowns[key] = 0.0

# ---------------------------------------------------------------------------
# Per-Frame Update
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if is_paused:
		return

	var dt: float = delta * game_speed
	game_time += dt

	# Regenerate cosmic energy
	var old_energy := cosmic_energy
	cosmic_energy = minf(cosmic_energy + energy_regen_rate * dt, max_cosmic_energy)
	if cosmic_energy != old_energy:
		energy_changed.emit(cosmic_energy, max_cosmic_energy)

	# Tick down all ability cooldowns
	for key in ability_cooldowns.keys():
		if ability_cooldowns[key] > 0.0:
			ability_cooldowns[key] = maxf(0.0, ability_cooldowns[key] - dt)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func select_ability(ability_type: String) -> void:
	if not ABILITIES.has(ability_type):
		push_error("GameManager: Unknown ability '%s'" % ability_type)
		return
	if not can_use_ability(ability_type):
		print("GameManager: Cannot use '%s' — not enough energy or on cooldown." % ability_type)
		return

	selected_ability = ability_type
	_set_state(GameState.TARGETING)
	disaster_selected.emit(ability_type)


func trigger_at_position(world_pos: Vector3) -> void:
	if current_state != GameState.TARGETING or selected_ability.is_empty():
		return

	var ability: Dictionary = ABILITIES[selected_ability]
	cosmic_energy          -= ability["energy_cost"]
	ability_cooldowns[selected_ability] = ability["cooldown"]

	energy_changed.emit(cosmic_energy, max_cosmic_energy)
	disaster_triggered.emit(selected_ability, world_pos)

	var fired := selected_ability
	selected_ability = ""
	_set_state(GameState.OBSERVING)
	print("GameManager: Triggered '%s' at %s" % [fired, world_pos])


func cancel_targeting() -> void:
	if current_state == GameState.TARGETING:
		selected_ability = ""
		_set_state(GameState.OBSERVING)


func can_use_ability(ability_type: String) -> bool:
	if not ABILITIES.has(ability_type):
		return false
	if cosmic_energy < ABILITIES[ability_type]["energy_cost"]:
		return false
	if ability_cooldowns.get(ability_type, 0.0) > 0.0:
		return false
	return true


func set_game_speed(speed: float) -> void:
	game_speed = clampf(speed, 0.0, 5.0)
	game_speed_changed.emit(game_speed)


func toggle_pause() -> void:
	is_paused = !is_paused
	game_speed_changed.emit(0.0 if is_paused else game_speed)


## Returns fraction 0..1 — 1 means ability is ready, 0 means full cooldown.
func get_cooldown_fraction(ability_type: String) -> float:
	var remaining: float = ability_cooldowns.get(ability_type, 0.0)
	var total: float     = ABILITIES.get(ability_type, {}).get("cooldown", 1.0)
	if total <= 0.0:
		return 1.0
	return 1.0 - (remaining / total)


func get_cooldown_remaining(ability_type: String) -> float:
	return ability_cooldowns.get(ability_type, 0.0)

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------
func _set_state(new_state: int) -> void:
	if current_state == new_state:
		return
	current_state = new_state
	game_state_changed.emit(new_state)
