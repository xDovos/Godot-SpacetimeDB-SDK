extends RigidBody3D

@export var jump_height : float = 2.5
@export var jump_time_to_peak : float = 0.4
@export var jump_time_to_descent : float = 0.35

@onready var jump_velocity : float = ((2.0 * jump_height) / jump_time_to_peak) * -1.0
@onready var jump_gravity : float = ((-2.0 * jump_height) / (jump_time_to_peak * jump_time_to_peak)) * -1.0
@onready var fall_gravity : float = ((-2.0 * jump_height) / (jump_time_to_descent * jump_time_to_descent)) * -1.0

@export var base_speed = 4.5
@export var run_speed = 8.0

@onready var visual_root = %VisualRoot
@onready var godot_plush_skin = $VisualRoot/GodotPlushSkin
@onready var movement_dust = %MovementDust
@onready var foot_step_audio = %FootStepAudio
@onready var impact_audio = %ImpactAudio
@onready var wave_audio = %WaveAudio
@onready var collision_shape_3d = %CollisionShape3D

const JUMP_PARTICLES_SCENE = preload("./vfx/jump_particles.tscn")
const LAND_PARTICLES_SCENE = preload("./vfx/land_particles.tscn")
signal movement_input_changed(new_input_vector: Vector2)
var last_sent_movement_input : Vector2 = Vector2.ZERO
var movement_input : Vector2 = Vector2.ZERO
var target_angle : float = 0.0
var last_movement_input : Vector2 = Vector2.ZERO

var ragdoll : bool = false : set = _set_ragdoll

var _is_on_floor : bool = false
var _was_on_floor : bool = false

# The “_integrate_forces” method is a quick translation of the integration of the character's body movements.
# This code is not optimal; perhaps “move_and_collide” should be used to check is_on_floor.

func _set_ragdoll(value : bool) -> void:
	ragdoll = value
	collision_shape_3d.set_deferred("disabled", ragdoll)
	godot_plush_skin.ragdoll = ragdoll
	linear_velocity = Vector3.ZERO

func _ready():
	godot_plush_skin.waved.connect(wave_audio.play)
	godot_plush_skin.footstep.connect(func(intensity : float = 1.0):
		foot_step_audio.volume_db = linear_to_db(intensity)
		foot_step_audio.play()
		)

func _input(event: InputEvent) -> void:
	# Only handle non-movement input here if it's local
	if get_meta("local", false):
		if event.is_action_pressed("ragdoll"):
			ragdoll = !ragdoll

		if (event.is_action_pressed("wave")
			&& _is_on_floor
			&& !godot_plush_skin.is_waving()):
			godot_plush_skin.wave()
func _integrate_forces(state : PhysicsDirectBodyState3D):
	# --- LOCAL PLAYER LOGIC ---
	if get_meta("local", false):
		if ragdoll: return # Skip if ragdolled

		var camera : Camera3D = get_viewport().get_camera_3d()
		if camera == null: return

		var is_waving : bool = godot_plush_skin.is_waving()

		# Get current input
		var current_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		# Rotate input based on camera only if there IS input
		if not current_input.is_zero_approx():
			current_input = current_input.rotated(-camera.global_rotation.y)

		# --- Detect Input Change and Emit Signal ---
		# Compare with the *last sent* input, emit signal if different
		if not current_input.is_equal_approx(last_sent_movement_input):
			emit_signal("movement_input_changed", current_input)
			last_sent_movement_input = current_input # Update last sent input

		# --- Apply Local Movement (Prediction) ---
		# We still apply movement locally for responsiveness,
		# but it might be corrected by the server state later.
		movement_input = current_input # Use the current frame's input for local physics

		var is_running : bool = Input.is_action_pressed("run")
		var vel_2d = Vector2(state.linear_velocity.x, state.linear_velocity.z)
		var is_moving : bool = movement_input != Vector2.ZERO && !is_waving

		if is_moving:
			godot_plush_skin.set_state("run" if is_running else "walk")
			var speed = run_speed if is_running else base_speed
			# Apply acceleration based movement
			vel_2d = vel_2d.move_toward(movement_input * speed, speed * 8.0 * state.step) # Use move_toward for acceleration feel
			state.linear_velocity.x = vel_2d.x
			state.linear_velocity.z = vel_2d.y
			target_angle = -movement_input.angle() # Use angle directly for rotation target
		else:
			godot_plush_skin.set_state("idle")
			# Apply friction/damping when not moving
			vel_2d = vel_2d.move_toward(Vector2.ZERO, base_speed * 4.0 * state.step) # Stronger damping/friction
			state.linear_velocity.x = vel_2d.x
			state.linear_velocity.z = vel_2d.y


		# --- Visual Rotation ---
		visual_root.rotation.y = rotate_toward(visual_root.rotation.y, target_angle, 10.0 * state.step) # Faster rotation
		var angle_diff = angle_difference(visual_root.rotation.y, target_angle)
		godot_plush_skin.tilt = move_toward(godot_plush_skin.tilt, angle_diff * 0.5, 4.0 * state.step) # Adjust tilt effect

		# --- Floor Check & Particles ---
		_is_on_floor = _get_is_on_floor(state)
		movement_dust.emitting = is_moving && is_running && _is_on_floor

		# --- Jump Logic ---
		if _is_on_floor:
			if Input.is_action_just_pressed("jump") && !is_waving:
				godot_plush_skin.set_state("jump")
				state.linear_velocity.y = jump_velocity # Use jump_velocity directly (it's likely positive now based on calculation)

				var jump_particles = JUMP_PARTICLES_SCENE.instantiate()
				add_sibling(jump_particles)
				jump_particles.global_position = global_position # Use current global_position

				do_squash_and_stretch(1.2, 0.1)
		else:
			# Only set fall state if not jumping (avoids overriding jump animation immediately)
			if state.linear_velocity.y <= 0.1: # Check if moving downwards or slightly upwards
				godot_plush_skin.set_state("fall")

		# --- Gravity ---
		# Apply different gravity based on vertical velocity direction
		var gravity = fall_gravity if state.linear_velocity.y < 0.0 else jump_gravity
		state.apply_central_force(Vector3.UP * -gravity * mass) # Apply gravity as force

		# --- Landing ---
		if !_was_on_floor && _is_on_floor:
			_on_hit_floor(state.linear_velocity.y)
		_was_on_floor = _is_on_floor

	# --- REMOTE PLAYER LOGIC ---
	else:
		# Remote players are moved by the Main script based on server updates.
		# We might want basic physics simulation here too (gravity),
		# or disable physics processing entirely for remote players if Main handles everything.
		# For now, let's just apply gravity.
		var gravity = fall_gravity if state.linear_velocity.y < 0.0 else jump_gravity
		state.apply_central_force(Vector3.UP * -gravity * mass)
		# We might need to update visual state based on server data too (e.g., running animation)
		# This would require passing more state or deriving it.
	
func _get_is_on_floor(state : PhysicsDirectBodyState3D) -> bool:
	for col_idx in state.get_contact_count():
		var col_normal = state.get_contact_local_normal(col_idx)
		return col_normal.dot(Vector3.UP) > -0.5
	return false
func get_movement_input() -> Vector2:
	return movement_input # Return the locally calculated input for this frame
func _on_hit_floor(y_vel : float):
	y_vel = clamp(abs(y_vel), 0.0, fall_gravity)
	var floor_impact_percent : float = y_vel / fall_gravity
	impact_audio.volume_db = linear_to_db(remap(floor_impact_percent, 0.0, 1.0, 0.5, 2.0))
	impact_audio.play()
	var land_particles = LAND_PARTICLES_SCENE.instantiate()
	add_sibling(land_particles)
	land_particles.global_transform = global_transform
	do_squash_and_stretch(0.7, 0.08)

func do_squash_and_stretch(value : float, timing : float = 0.1):
	var t = create_tween()
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(godot_plush_skin, "squash_and_stretch", value, timing)
	t.tween_property(godot_plush_skin, "squash_and_stretch", 1.0, timing * 1.8)
