## EffectsManager.gd
## Manages all runtime visual effects: explosions, lava spread, ice overlay,
## radiation pulses, and particle-like mesh effects.
extends Node
class_name EffectsManager

# ---------------------------------------------------------------------------
# References (set by Main.gd)
# ---------------------------------------------------------------------------
var planet:      Planet
var camera:      OrbitCamera

# ---------------------------------------------------------------------------
# Active effect tracking
# ---------------------------------------------------------------------------
var _active_effects: Array = []   ## Array[Dictionary] of {node, timer, type}

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	pass


func initialize(planet_node: Planet, camera_node: OrbitCamera) -> void:
	planet = planet_node
	camera = camera_node

	# Connect to disaster manager signals (routed through DisasterManager)
	# We subscribe to GameManager for now
	GameManager.disaster_triggered.connect(_on_disaster_triggered)

# ---------------------------------------------------------------------------
# Per-Frame
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	var dt := delta * GameManager.game_speed
	_tick_effects(dt)


func _tick_effects(dt: float) -> void:
	var to_remove: Array = []
	for effect in _active_effects:
		effect["timer"] -= dt
		if effect["timer"] <= 0.0:
			if is_instance_valid(effect["node"]):
				effect["node"].queue_free()
			to_remove.append(effect)
	for e in to_remove:
		_active_effects.erase(e)

# ---------------------------------------------------------------------------
# Disaster Callbacks
# ---------------------------------------------------------------------------
func _on_disaster_triggered(disaster_type: String, world_pos: Vector3) -> void:
	match disaster_type:
		"METEOR_STRIKE":
			# Explosion flash + crater ring
			_spawn_explosion(world_pos, 3.0, 1.5, Color(1.0, 0.5, 0.1))
			_spawn_expanding_ring(world_pos, 0.2, 3.0, 2.0, Color(1.0, 0.4, 0.0))
			_spawn_smoke_column(world_pos, 8.0)

		"VOLCANIC_ERUPTION":
			_spawn_lava_pool(world_pos, 2.5, 40.0)
			_spawn_explosion(world_pos, 2.0, 1.0, Color(1.0, 0.2, 0.0))
			_spawn_fire_pillars(world_pos, 4)

		"EARTHQUAKE":
			_spawn_ground_shockwave(world_pos, 8.0, 3.0)

		"ICE_AGE":
			_spawn_ice_overlay(60.0)

		"SOLAR_FLARE":
			_spawn_solar_pulse(15.0)

		"BLACK_HOLE":
			_spawn_gravity_distortion(world_pos, 10.0)

		"PLANET_CRACK":
			_spawn_planet_crack_effect(world_pos)
			_spawn_explosion(world_pos, 8.0, 3.0, Color(1.0, 0.0, 0.0))

# ---------------------------------------------------------------------------
# Effect Spawners
# ---------------------------------------------------------------------------

func _spawn_explosion(pos: Vector3, radius: float, duration: float,
		color: Color) -> void:
	var node         := Node3D.new()
	node.global_position = pos

	# Flash sphere
	var mesh_inst    := MeshInstance3D.new()
	var sphere       := SphereMesh.new()
	sphere.radius    = radius * 0.3
	sphere.height    = radius * 0.6
	mesh_inst.mesh   = sphere

	var mat          := StandardMaterial3D.new()
	mat.albedo_color  = color
	mat.emission_enabled = true
	mat.emission     = color
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override = mat
	node.add_child(mesh_inst)

	var light        := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 10.0
	light.omni_range  = radius * 2.5
	node.add_child(light)

	get_parent().add_child(node)

	# Scale up then fade
	var tween := get_tree().create_tween()
	tween.tween_property(mesh_inst, "scale",
		Vector3.ONE * radius, duration * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.6)
	tween.tween_callback(node.queue_free)

	_track_effect(node, duration)


func _spawn_expanding_ring(pos: Vector3, inner_r: float, outer_r: float,
		duration: float, color: Color) -> void:
	var node       := Node3D.new()
	node.global_position = pos
	# Orient ring to face outward from planet center
	node.look_at(pos + pos.normalized(), Vector3.UP)

	var mesh_inst  := MeshInstance3D.new()
	var torus      := TorusMesh.new()
	torus.inner_radius = inner_r
	torus.outer_radius = inner_r + 0.1
	mesh_inst.mesh = torus

	var mat        := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission    = color
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override = mat
	node.add_child(mesh_inst)

	get_parent().add_child(node)

	var tween := get_tree().create_tween()
	tween.tween_property(mesh_inst, "scale",
		Vector3.ONE * (outer_r / inner_r), duration).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.tween_callback(node.queue_free)

	_track_effect(node, duration)


func _spawn_smoke_column(pos: Vector3, duration: float) -> void:
	# Simplified smoke: dark rising spheres
	for i in range(6):
		var node         := Node3D.new()
		var dir           := pos.normalized()
		node.global_position = pos + dir * float(i) * 1.2

		var mesh_inst    := MeshInstance3D.new()
		var sphere       := SphereMesh.new()
		sphere.radius    = 0.5 + float(i) * 0.2
		sphere.height    = 1.0 + float(i) * 0.4
		mesh_inst.mesh   = sphere

		var mat          := StandardMaterial3D.new()
		var darkness      := 0.3 - float(i) * 0.04
		mat.albedo_color  = Color(darkness, darkness, darkness, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_inst.material_override = mat
		node.add_child(mesh_inst)

		get_parent().add_child(node)

		var delay := float(i) * 0.3
		var tween  := get_tree().create_tween()
		tween.tween_interval(delay)
		tween.tween_property(node, "global_position",
			pos + dir * (float(i) * 1.8 + 2.0), duration - delay)
		tween.parallel().tween_property(mat, "albedo_color:a", 0.0, duration - delay)
		tween.tween_callback(node.queue_free)
		_track_effect(node, duration)


func _spawn_lava_pool(pos: Vector3, radius: float, duration: float) -> void:
	var node         := Node3D.new()
	node.global_position = pos

	var mesh_inst    := MeshInstance3D.new()
	var sphere       := SphereMesh.new()
	sphere.radius    = radius
	sphere.height    = radius * 2.0
	sphere.radial_segments = 24
	sphere.rings     = 12
	mesh_inst.mesh   = sphere

	var mat          := StandardMaterial3D.new()
	mat.albedo_color  = Color(1.0, 0.15, 0.0)
	mat.emission_enabled = true
	mat.emission     = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 3.0
	mesh_inst.material_override = mat
	node.add_child(mesh_inst)

	var light        := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.0)
	light.light_energy = 5.0
	light.omni_range  = radius * 3.0
	node.add_child(light)

	get_parent().add_child(node)

	var tween := get_tree().create_tween()
	tween.tween_interval(duration * 0.8)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.2)
	tween.tween_callback(node.queue_free)

	_track_effect(node, duration)


func _spawn_fire_pillars(pos: Vector3, count: int) -> void:
	for i in range(count):
		var angle   := TAU * float(i) / float(count)
		var offset   := Vector3(cos(angle), 0, sin(angle)) * 1.5
		var pillar_pos := pos + offset

		var node     := Node3D.new()
		node.global_position = pillar_pos

		var light    := OmniLight3D.new()
		light.light_color  = Color(1.0, 0.4, 0.0)
		light.light_energy = 6.0
		light.omni_range   = 4.0
		node.add_child(light)

		get_parent().add_child(node)

		var duration := randf_range(5.0, 12.0)
		var tween    := get_tree().create_tween().set_loops(int(duration * 2))
		tween.tween_property(light, "light_energy", 3.0, 0.3)
		tween.tween_property(light, "light_energy", 8.0, 0.3)

		var end_t := get_tree().create_timer(duration)
		end_t.timeout.connect(func() -> void:
			if is_instance_valid(node):
				node.queue_free()
		)
		_track_effect(node, duration)


func _spawn_ground_shockwave(pos: Vector3, radius: float, duration: float) -> void:
	_spawn_expanding_ring(pos, 0.5, radius, duration, Color(0.8, 0.6, 0.2))
	_spawn_expanding_ring(pos, 0.5, radius * 0.6, duration * 0.7,
		Color(0.9, 0.7, 0.3))


func _spawn_ice_overlay(duration: float) -> void:
	# Tint entire atmosphere blue-white
	if not is_instance_valid(planet):
		return
	var atmo: MeshInstance3D = planet.get_node_or_null("AtmosphereMesh") as MeshInstance3D
	if not atmo:
		return

	var mat: ShaderMaterial = atmo.material_override as ShaderMaterial
	if mat:
		var tween := get_tree().create_tween()
		tween.tween_method(
			func(v: Color) -> void: mat.set_shader_parameter("atmo_color", v),
			Color(0.3, 0.6, 1.0, 0.3),
			Color(0.7, 0.9, 1.0, 0.6),
			3.0
		)
		tween.tween_interval(duration - 6.0)
		tween.tween_method(
			func(v: Color) -> void: mat.set_shader_parameter("atmo_color", v),
			Color(0.7, 0.9, 1.0, 0.6),
			Color(0.3, 0.6, 1.0, 0.3),
			3.0
		)


func _spawn_solar_pulse(duration: float) -> void:
	# Flash the scene with yellow-white
	var node         := Node3D.new()
	node.global_position = Vector3.ZERO

	var light        := OmniLight3D.new()
	light.light_color = Color(1.0, 0.95, 0.7)
	light.light_energy = 0.0
	light.omni_range  = 100.0
	node.add_child(light)

	get_parent().add_child(node)

	var tween := get_tree().create_tween()
	tween.tween_property(light, "light_energy", 8.0, 1.5)
	tween.tween_interval(duration - 4.0)
	tween.tween_property(light, "light_energy", 0.0, 2.5)
	tween.tween_callback(node.queue_free)

	_track_effect(node, duration)


func _spawn_gravity_distortion(pos: Vector3, duration: float) -> void:
	var node         := Node3D.new()
	node.global_position = pos

	var light        := OmniLight3D.new()
	light.light_color = Color(0.3, 0.0, 0.8)
	light.light_energy = 12.0
	light.omni_range  = 10.0
	node.add_child(light)

	get_parent().add_child(node)

	var tween := get_tree().create_tween().set_loops(int(duration * 1.5))
	tween.tween_property(light, "light_energy", 18.0, 0.5)
	tween.tween_property(light, "light_energy", 8.0,  0.5)

	var end_t := get_tree().create_timer(duration)
	end_t.timeout.connect(func() -> void:
		if is_instance_valid(node):
			node.queue_free()
	)
	_track_effect(node, duration)


func _spawn_planet_crack_effect(pos: Vector3) -> void:
	# Multiple intense explosions in a line
	for i in range(8):
		var offset   := randf_range(-8.0, 8.0)
		var crack_pt  := pos + Vector3(offset, 0, randf_range(-4.0, 4.0))
		var delay     := float(i) * 0.4

		var t := get_tree().create_timer(delay)
		t.timeout.connect(func() -> void:
			_spawn_explosion(crack_pt, 2.5, 4.0, Color(1.0, 0.1, 0.0))
			_spawn_lava_pool(crack_pt, 1.5, 30.0)
		)

# ---------------------------------------------------------------------------
# Effect Tracking
# ---------------------------------------------------------------------------
func _track_effect(node: Node3D, duration: float) -> void:
	_active_effects.append({"node": node, "timer": duration})


func clear_all_effects() -> void:
	for effect in _active_effects:
		if is_instance_valid(effect["node"]):
			effect["node"].queue_free()
	_active_effects.clear()
