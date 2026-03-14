## GameUI.gd
## Full game HUD: planet stats panel, ability buttons with cooldowns,
## civilization summary, targeting cursor, and notification feed.
extends CanvasLayer
class_name GameUI

# ---------------------------------------------------------------------------
# References
# ---------------------------------------------------------------------------
var planet:      Planet
var civ_manager: CivilizationManager

# ---------------------------------------------------------------------------
# UI Node References (built programmatically)
# ---------------------------------------------------------------------------
var _stats_panel:       PanelContainer
var _ability_panel:     PanelContainer
var _notification_panel: PanelContainer
var _speed_panel:       PanelContainer
var _targeting_label:   Label

var _health_bar:        ProgressBar
var _atmo_bar:          ProgressBar
var _bio_bar:           ProgressBar
var _energy_bar:        ProgressBar

var _stat_labels: Dictionary = {}
var _ability_buttons: Dictionary = {}
var _ability_cooldown_bars: Dictionary = {}

var _notifications: Array = []   ## Array[Dictionary] {label, timer}

const NOTIF_DURATION := 4.0
const ABILITY_ICON_SIZE := Vector2(72, 72)

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_hud()


func initialize(planet_node: Planet, civ_mgr: CivilizationManager) -> void:
	planet      = planet_node
	civ_manager = civ_mgr

	# Connect to planet signals
	planet.planet_health_changed.connect(_on_health_changed)
	planet.atmosphere_changed.connect(_on_atmo_changed)
	planet.biosphere_changed.connect(_on_bio_changed)
	planet.temperature_changed.connect(_on_temp_changed)
	planet.planet_destroyed.connect(_on_planet_destroyed)

	# Connect to game manager signals
	GameManager.energy_changed.connect(_on_energy_changed)
	GameManager.game_state_changed.connect(_on_game_state_changed)
	GameManager.disaster_selected.connect(_on_disaster_selected)
	GameManager.game_speed_changed.connect(_on_speed_changed)

# ---------------------------------------------------------------------------
# Per-Frame
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_update_stats()
	_update_ability_cooldowns()
	_tick_notifications(delta)


func _update_stats() -> void:
	if not is_instance_valid(planet):
		return

	_health_bar.value = planet.planet_health
	_atmo_bar.value   = planet.atmosphere_level
	_bio_bar.value    = planet.biosphere_level
	_energy_bar.value = GameManager.cosmic_energy

	# Temperature with color coding
	var temp_label: Label = _stat_labels.get("temperature")
	if temp_label:
		var t := planet.temperature
		temp_label.text = "TEMP: %.1f°C" % t
		if t > 50.0:
			temp_label.modulate = Color(1.0, 0.3, 0.1)
		elif t < -10.0:
			temp_label.modulate = Color(0.6, 0.9, 1.0)
		else:
			temp_label.modulate = Color(1.0, 1.0, 1.0)

	# Civilization stats
	if is_instance_valid(civ_manager):
		var pop_label: Label = _stat_labels.get("population")
		if pop_label:
			pop_label.text = "POP: %s" % _format_number(civ_manager.get_total_population())
		var city_label: Label = _stat_labels.get("cities")
		if city_label:
			city_label.text = "CITIES: %d / %d" % [
				civ_manager.get_active_city_count(),
				civ_manager.get_city_count()
			]
		var tech_label: Label = _stat_labels.get("avg_tech")
		if tech_label:
			tech_label.text = "AVG TECH: %.1f" % civ_manager.get_average_tech_level()


func _update_ability_cooldowns() -> void:
	for key: String in _ability_cooldown_bars.keys():
		var bar: ProgressBar = _ability_cooldown_bars[key]
		bar.value = GameManager.get_cooldown_fraction(key) * 100.0

		var btn: Button = _ability_buttons.get(key)
		if btn:
			btn.disabled = not GameManager.can_use_ability(key)

# ---------------------------------------------------------------------------
# HUD Construction
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	_build_stats_panel()
	_build_ability_panel()
	_build_notification_panel()
	_build_speed_controls()
	_build_targeting_label()
	_build_help_label()


func _build_stats_panel() -> void:
	_stats_panel = PanelContainer.new()
	_stats_panel.name = "StatsPanel"
	_stats_panel.anchors_preset = Control.PRESET_TOP_LEFT
	_stats_panel.position       = Vector2(10, 10)
	_stats_panel.custom_minimum_size = Vector2(230, 0)

	var style := StyleBoxFlat.new()
	style.bg_color        = Color(0.0, 0.0, 0.1, 0.82)
	style.border_width_left   = 2
	style.border_width_top    = 2
	style.border_width_right  = 2
	style.border_width_bottom = 2
	style.border_color        = Color(0.3, 0.6, 1.0, 0.8)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	_stats_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_stats_panel.add_child(vbox)

	# Title
	var title := _make_label("PLANET STATUS", Color(0.5, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_make_separator())

	# Planet bars
	_health_bar = _add_bar(vbox, "PLANET HEALTH", Color(0.2, 0.9, 0.3))
	_atmo_bar   = _add_bar(vbox, "ATMOSPHERE",    Color(0.4, 0.7, 1.0))
	_bio_bar    = _add_bar(vbox, "BIOSPHERE",     Color(0.1, 0.8, 0.4))

	vbox.add_child(_make_separator())

	# Text stats
	_stat_labels["temperature"] = _add_stat_label(vbox, "TEMP: 15.0°C")
	_stat_labels["population"]  = _add_stat_label(vbox, "POP: 0")
	_stat_labels["cities"]      = _add_stat_label(vbox, "CITIES: 0 / 0")
	_stat_labels["avg_tech"]    = _add_stat_label(vbox, "AVG TECH: 1.0")

	vbox.add_child(_make_separator())

	# Cosmic energy bar
	_energy_bar = _add_bar(vbox, "COSMIC ENERGY", Color(0.8, 0.4, 1.0))
	_energy_bar.max_value = GameManager.max_cosmic_energy

	add_child(_stats_panel)


func _add_bar(parent: VBoxContainer, label_text: String, color: Color) -> ProgressBar:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)

	var lbl  := Label.new()
	lbl.text  = label_text
	lbl.custom_minimum_size = Vector2(130, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	hbox.add_child(lbl)

	var bar           := ProgressBar.new()
	bar.min_value      = 0.0
	bar.max_value      = 100.0
	bar.value          = 100.0
	bar.custom_minimum_size = Vector2(80, 14)
	bar.show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1)
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)

	hbox.add_child(bar)
	return bar


func _add_stat_label(parent: VBoxContainer, text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	parent.add_child(lbl)
	return lbl


func _build_ability_panel() -> void:
	_ability_panel = PanelContainer.new()
	_ability_panel.name = "AbilityPanel"
	_ability_panel.anchors_preset = Control.PRESET_BOTTOM_LEFT
	_ability_panel.anchor_top     = 1.0
	_ability_panel.anchor_bottom  = 1.0
	_ability_panel.offset_top     = -180
	_ability_panel.offset_bottom  = -10
	_ability_panel.offset_left    = 10
	_ability_panel.offset_right   = 10
	_ability_panel.grow_vertical  = Control.GROW_DIRECTION_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color    = Color(0.0, 0.0, 0.12, 0.88)
	style.border_color = Color(0.5, 0.3, 0.8, 0.8)
	style.border_width_left   = 2
	style.border_width_top    = 2
	style.border_width_right  = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	_ability_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	_ability_panel.add_child(vbox)

	var title := _make_label("COSMIC POWERS", Color(0.7, 0.5, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_make_separator())

	# Row of ability buttons
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	vbox.add_child(hbox)

	for key: String in GameManager.ABILITIES.keys():
		var ability   = GameManager.ABILITIES[key]
		var vbox2     := VBoxContainer.new()
		vbox2.add_theme_constant_override("separation", 2)
		hbox.add_child(vbox2)

		var btn        := Button.new()
		btn.text       = ability["icon"] + "\n" + _short_name(ability["name"])
		btn.custom_minimum_size = ABILITY_ICON_SIZE
		btn.tooltip_text = "%s\nCost: %.0f energy\nCooldown: %.1fs\n\n%s" % [
			ability["name"],
			ability["energy_cost"],
			ability["cooldown"],
			ability["description"]
		]

		# Button styling
		var btn_style      := StyleBoxFlat.new()
		btn_style.bg_color  = Color(ability["color"].r * 0.3, ability["color"].g * 0.3,
								 ability["color"].b * 0.3, 0.9)
		btn_style.border_color = ability["color"]
		btn_style.border_width_left   = 2
		btn_style.border_width_top    = 2
		btn_style.border_width_right  = 2
		btn_style.border_width_bottom = 2
		btn_style.corner_radius_top_left     = 5
		btn_style.corner_radius_top_right    = 5
		btn_style.corner_radius_bottom_left  = 5
		btn_style.corner_radius_bottom_right = 5
		btn.add_theme_stylebox_override("normal", btn_style)

		# Hover style
		var hover_style      := btn_style.duplicate()
		hover_style.bg_color  = Color(ability["color"].r * 0.5, ability["color"].g * 0.5,
								   ability["color"].b * 0.5, 0.95)
		btn.add_theme_stylebox_override("hover", hover_style)

		var captured_key := key
		btn.pressed.connect(func() -> void: GameManager.select_ability(captured_key))

		_ability_buttons[key] = btn
		vbox2.add_child(btn)

		# Cooldown bar below button
		var cd_bar := ProgressBar.new()
		cd_bar.min_value = 0.0
		cd_bar.max_value = 100.0
		cd_bar.value     = 100.0
		cd_bar.custom_minimum_size = Vector2(ABILITY_ICON_SIZE.x, 6)
		cd_bar.show_percentage = false

		var cd_bg         := StyleBoxFlat.new()
		cd_bg.bg_color     = Color(0.1, 0.1, 0.1)
		cd_bar.add_theme_stylebox_override("background", cd_bg)

		var cd_fill       := StyleBoxFlat.new()
		cd_fill.bg_color   = ability["color"]
		cd_bar.add_theme_stylebox_override("fill", cd_fill)

		_ability_cooldown_bars[key] = cd_bar
		vbox2.add_child(cd_bar)

	add_child(_ability_panel)


func _build_notification_panel() -> void:
	_notification_panel = PanelContainer.new()
	_notification_panel.name = "NotificationPanel"
	_notification_panel.anchors_preset = Control.PRESET_TOP_RIGHT
	_notification_panel.anchor_left    = 1.0
	_notification_panel.anchor_right   = 1.0
	_notification_panel.offset_left    = -310
	_notification_panel.offset_top     = 10
	_notification_panel.offset_right   = -10
	_notification_panel.offset_bottom  = 200
	_notification_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var style       := StyleBoxFlat.new()
	style.bg_color   = Color(0, 0, 0, 0)
	_notification_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "NotifVBox"
	vbox.add_theme_constant_override("separation", 4)
	_notification_panel.add_child(vbox)
	add_child(_notification_panel)


func _build_speed_controls() -> void:
	_speed_panel = PanelContainer.new()
	_speed_panel.name = "SpeedPanel"
	_speed_panel.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	_speed_panel.anchor_top     = 1.0
	_speed_panel.anchor_bottom  = 1.0
	_speed_panel.anchor_left    = 1.0
	_speed_panel.anchor_right   = 1.0
	_speed_panel.offset_top     = -60
	_speed_panel.offset_left    = -260
	_speed_panel.offset_bottom  = -10
	_speed_panel.offset_right   = -10
	_speed_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed_panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN

	var style        := StyleBoxFlat.new()
	style.bg_color    = Color(0.0, 0.0, 0.1, 0.82)
	style.border_color = Color(0.3, 0.6, 1.0, 0.6)
	style.border_width_left   = 1
	style.border_width_top    = 1
	style.border_width_right  = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left     = 5
	style.corner_radius_top_right    = 5
	style.corner_radius_bottom_left  = 5
	style.corner_radius_bottom_right = 5
	_speed_panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	_speed_panel.add_child(hbox)

	var lbl    := _make_label("SPEED:", Color(0.7, 0.7, 0.9))
	lbl.add_theme_font_size_override("font_size", 11)
	hbox.add_child(lbl)

	for speed_val: float in [0.5, 1.0, 2.0, 4.0]:
		var btn          := Button.new()
		btn.text          = "x%.0f" % speed_val if speed_val >= 1.0 else "x%.1f" % speed_val
		btn.custom_minimum_size = Vector2(36, 28)
		btn.add_theme_font_size_override("font_size", 11)
		var captured_speed := speed_val
		btn.pressed.connect(func() -> void: GameManager.set_game_speed(captured_speed))
		hbox.add_child(btn)

	var pause_btn      := Button.new()
	pause_btn.text      = "PAUSE"
	pause_btn.custom_minimum_size = Vector2(52, 28)
	pause_btn.add_theme_font_size_override("font_size", 11)
	pause_btn.pressed.connect(func() -> void: GameManager.toggle_pause())
	hbox.add_child(pause_btn)

	add_child(_speed_panel)


func _build_targeting_label() -> void:
	_targeting_label = Label.new()
	_targeting_label.name = "TargetingLabel"
	_targeting_label.text = "TARGETING — Left-click planet to strike  |  ESC to cancel"
	_targeting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_targeting_label.anchors_preset = Control.PRESET_TOP_WIDE
	_targeting_label.offset_top     = 12
	_targeting_label.offset_bottom  = 40
	_targeting_label.add_theme_font_size_override("font_size", 15)
	_targeting_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.1))
	_targeting_label.visible = false
	add_child(_targeting_label)


func _build_help_label() -> void:
	var help := Label.new()
	help.name = "HelpLabel"
	help.text = "Right-drag: Rotate  |  Scroll: Zoom  |  Click ability then click planet to strike"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.anchors_preset = Control.PRESET_BOTTOM_WIDE
	help.anchor_top     = 1.0
	help.anchor_bottom  = 1.0
	help.offset_top     = -30
	help.offset_bottom  = -10
	help.add_theme_font_size_override("font_size", 10)
	help.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	add_child(help)

# ---------------------------------------------------------------------------
# Notifications
# ---------------------------------------------------------------------------
func push_notification(message: String, color: Color = Color.WHITE) -> void:
	var vbox: VBoxContainer = _notification_panel.get_node_or_null("NotifVBox")
	if not vbox:
		return

	var lbl := Label.new()
	lbl.text = "> " + message
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)

	# Background for readability
	var panel      := PanelContainer.new()
	var style       := StyleBoxFlat.new()
	style.bg_color  = Color(0.0, 0.0, 0.0, 0.7)
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(lbl)
	vbox.add_child(panel)

	_notifications.append({"panel": panel, "timer": NOTIF_DURATION})

	# Limit visible notifications
	if vbox.get_child_count() > 6:
		vbox.get_child(0).queue_free()


func _tick_notifications(delta: float) -> void:
	var to_remove: Array = []
	for notif: Dictionary in _notifications:
		notif["timer"] -= delta
		if notif["timer"] <= 0.0:
			if is_instance_valid(notif["panel"]):
				notif["panel"].queue_free()
			to_remove.append(notif)
	for n in to_remove:
		_notifications.erase(n)

# ---------------------------------------------------------------------------
# Signal Callbacks
# ---------------------------------------------------------------------------
func _on_health_changed(new_health: float) -> void:
	_health_bar.value = new_health
	if new_health < 30.0:
		push_notification("PLANET CRITICAL — Health at %.0f%%!" % new_health,
			Color(1.0, 0.2, 0.2))


func _on_atmo_changed(new_level: float) -> void:
	_atmo_bar.value = new_level
	if new_level < 20.0:
		push_notification("ATMOSPHERE FAILING — Biosphere at risk!", Color(0.6, 0.8, 1.0))


func _on_bio_changed(new_level: float) -> void:
	_bio_bar.value = new_level


func _on_temp_changed(new_temp: float) -> void:
	pass  # Handled in _update_stats()


func _on_energy_changed(current: float, _maximum: float) -> void:
	_energy_bar.value = current


func _on_game_state_changed(new_state: int) -> void:
	_targeting_label.visible = (new_state == GameManager.GameState.TARGETING)


func _on_disaster_selected(ability_type: String) -> void:
	var name_str := GameManager.ABILITIES[ability_type]["name"]
	push_notification("Targeting: %s — Click planet to fire!" % name_str,
		GameManager.ABILITIES[ability_type]["color"])


func _on_speed_changed(new_speed: float) -> void:
	if new_speed == 0.0:
		push_notification("PAUSED", Color(0.8, 0.8, 0.0))


func _on_planet_destroyed() -> void:
	push_notification("PLANET DESTROYED!", Color(1.0, 0.0, 0.0))
	var doom_label := Label.new()
	doom_label.text = "THE PLANET HAS BEEN DESTROYED"
	doom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	doom_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	doom_label.anchors_preset       = Control.PRESET_CENTER
	doom_label.add_theme_font_size_override("font_size", 36)
	doom_label.add_theme_color_override("font_color", Color(1.0, 0.1, 0.0))
	add_child(doom_label)

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------
func _make_label(text: String, color: Color = Color.WHITE) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.5, 1.0, 0.4)
	sep.add_theme_stylebox_override("separator", style)
	return sep


static func _format_number(n: int) -> String:
	if n >= 1_000_000_000:
		return "%.1fB" % (float(n) / 1_000_000_000.0)
	elif n >= 1_000_000:
		return "%.1fM" % (float(n) / 1_000_000.0)
	elif n >= 1000:
		return "%.1fK" % (float(n) / 1000.0)
	return str(n)


static func _short_name(name: String) -> String:
	var parts := name.split(" ")
	if parts.size() >= 2:
		return parts[0].left(6) + "\n" + parts[1].left(6)
	return name.left(10)
