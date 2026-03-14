## OrbitCamera.gd
## 3D orbit camera that rotates around the planet origin.
## Features: drag-to-rotate, scroll-to-zoom, surface click detection,
##           targeting reticle, and screen shake.
extends Camera3D
class_name OrbitCamera

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal planet_surface_clicked(world_pos: Vector3)
signal planet_surface_hovered(world_pos: Vector3)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
@export var target:           Node3D  ## Planet node to orbit around
@export var orbit_distance:   float = 28.0
@export var min_distance:     float = 14.0
@export var max_distance:     float = 55.0
@export var rotation_speed:   float = 0.4
@export var zoom_speed:       float = 3.0
@export var smooth_factor:    float = 8.0

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _yaw:           float = 0.0
var _pitch:         float = 20.0        ## degrees
var _current_dist:  float = 28.0
var _target_dist:   float = 28.0
var _is_dragging:   bool  = false
var _last_mouse:    Vector2 = Vector2.ZERO

# Shake state
var _shake_intensity: float = 0.0
var _shake_duration:  float = 0.0
var _shake_timer:     float = 0.0
var _shake_offset:    Vector3 = Vector3.ZERO

# Targeting reticle (3D sphere marker)
var _reticle:       MeshInstance3D
var _hover_pos:     Vector3 = Vector3.ZERO
var _planet_radius: float   = 10.0

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	_current_dist = orbit_distance
	_target_dist  = orbit_distance

	if target:
		_planet_radius = target.planet_radius if target.has_method("get") else 10.0

	_build_reticle()
	_update_camera_transform()

	GameManager.game_state_changed.connect(_on_game_state_changed)


func _build_reticle() -> void:
	_reticle      = MeshInstance3D.new()
	_reticle.name  = "TargetReticle"

	var sphere    := SphereMesh.new()
	sphere.radius  = 0.3
	sphere.height  = 0.6
	_reticle.mesh  = sphere

	var mat        := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.0, 0.7)
	mat.emission_enabled = true
	mat.emission   = Color(1.0, 0.5, 0.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_reticle.material_override = mat
	_reticle.visible = false

	# Attach to scene root (not camera, so it stays in world space)
	get_tree().root.call_deferred("add_child", _reticle)

# ---------------------------------------------------------------------------
# Per-Frame
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_process_shake(delta)
	_process_zoom(delta)

	if GameManager.current_state == GameManager.GameState.TARGETING:
		_process_hover_reticle()


func _process_zoom(delta: float) -> void:
	_current_dist = lerpf(_current_dist, _target_dist, smooth_factor * delta)
	_update_camera_transform()


func _process_shake(delta: float) -> void:
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var intensity := _shake_intensity * (_shake_timer / _shake_duration)
		_shake_offset  = Vector3(
			randf_range(-1.0, 1.0) * intensity,
			randf_range(-1.0, 1.0) * intensity,
			0.0
		)
	else:
		_shake_offset = Vector3.ZERO
		_shake_intensity = 0.0


func _process_hover_reticle() -> void:
	if not _reticle or not _reticle.is_inside_tree():
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var hit_pos   := _raycast_planet(mouse_pos)

	if hit_pos != Vector3.ZERO:
		_reticle.visible        = true
		_reticle.global_position = hit_pos + hit_pos.normalized() * 0.15
		_hover_pos               = hit_pos
		planet_surface_hovered.emit(hit_pos)
	else:
		_reticle.visible = false

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	# Right-click drag to orbit
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_dragging = mb.pressed
			_last_mouse  = mb.position

		# Scroll wheel zoom
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_dist = clampf(_target_dist - zoom_speed, min_distance, max_distance)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_dist = clampf(_target_dist + zoom_speed, min_distance, max_distance)

		# Left click — surface targeting or deselection
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_left_click(mb.position)

	elif event is InputEventMouseMotion and _is_dragging:
		var motion := (event as InputEventMouseMotion).relative
		_yaw   -= motion.x * rotation_speed
		_pitch  = clampf(_pitch - motion.y * rotation_speed, -85.0, 85.0)
		_update_camera_transform()

	# ESC cancels targeting
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			GameManager.cancel_targeting()


func _handle_left_click(screen_pos: Vector2) -> void:
	if GameManager.current_state == GameManager.GameState.TARGETING:
		var hit := _raycast_planet(screen_pos)
		if hit != Vector3.ZERO:
			GameManager.trigger_at_position(hit)
			planet_surface_clicked.emit(hit)
			if _reticle:
				_reticle.visible = false
	# If observing, just allow normal camera drag (handled via right-click)

# ---------------------------------------------------------------------------
# Transform
# ---------------------------------------------------------------------------
func _update_camera_transform() -> void:
	var yaw_rad   := deg_to_rad(_yaw)
	var pitch_rad := deg_to_rad(_pitch)

	# Spherical coordinates relative to target
	var offset := Vector3(
		cos(pitch_rad) * sin(yaw_rad),
		sin(pitch_rad),
		cos(pitch_rad) * cos(yaw_rad)
	) * _current_dist

	var target_pos := Vector3.ZERO
	if target:
		target_pos = target.global_position

	global_position = target_pos + offset + _shake_offset
	look_at(target_pos, Vector3.UP)

# ---------------------------------------------------------------------------
# Raycasting
# ---------------------------------------------------------------------------

## Returns the world-space hit position on the planet sphere, or Vector3.ZERO.
func _raycast_planet(screen_pos: Vector2) -> Vector3:
	var ray_origin := project_ray_origin(screen_pos)
	var ray_dir    := project_ray_normal(screen_pos)

	var planet_pos := Vector3.ZERO
	if target:
		planet_pos = target.global_position

	var radius := _planet_radius + 0.2
	return _intersect_sphere(ray_origin, ray_dir, planet_pos, radius)


## Analytic ray–sphere intersection. Returns hit point or Vector3.ZERO.
static func _intersect_sphere(ray_origin: Vector3, ray_dir: Vector3,
		center: Vector3, radius: float) -> Vector3:
	var oc  := ray_origin - center
	var a   := ray_dir.dot(ray_dir)
	var b   := 2.0 * oc.dot(ray_dir)
	var c   := oc.dot(oc) - radius * radius
	var disc := b * b - 4.0 * a * c

	if disc < 0.0:
		return Vector3.ZERO

	var t := (-b - sqrt(disc)) / (2.0 * a)
	if t < 0.01:
		t = (-b + sqrt(disc)) / (2.0 * a)
	if t < 0.01:
		return Vector3.ZERO

	return ray_origin + ray_dir * t

# ---------------------------------------------------------------------------
# Screen Shake
# ---------------------------------------------------------------------------
func trigger_shake(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_duration  = duration
	_shake_timer     = duration

# ---------------------------------------------------------------------------
# Game State Callback
# ---------------------------------------------------------------------------
func _on_game_state_changed(new_state: int) -> void:
	if new_state != GameManager.GameState.TARGETING and _reticle:
		_reticle.visible = false
