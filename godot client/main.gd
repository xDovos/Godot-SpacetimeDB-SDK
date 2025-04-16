# In your main game script (e.g., Main.gd)
extends Node

@onready var spacetimedb_client: SpacetimeDBClient = $SpacetimeDBClient
@export var player_prefab: PackedScene

# Store local identity info when received
var local_identity_bytes: PackedByteArray
# Dictionary to map player identity (bytes) to their Node instance
var spawned_players: Dictionary = {}
# Store the local player node for easy access
var local_player_node: RigidBody3D = null

# --- Godot Lifecycle ---

func _ready():
	# Connect to signals from the client
	spacetimedb_client.connected.connect(_on_spacetimedb_connected)
	spacetimedb_client.disconnected.connect(_on_spacetimedb_disconnected)
	spacetimedb_client.connection_error.connect(_on_spacetimedb_connection_error)
	spacetimedb_client.identity_received.connect(_on_spacetimedb_identity_received)
	spacetimedb_client.database_initialized.connect(_on_spacetimedb_database_initialized)
	# Connect to row signals for managing players
	spacetimedb_client.row_inserted.connect(_on_spacetimedb_row_inserted)
	spacetimedb_client.row_updated.connect(_on_spacetimedb_row_updated)
	spacetimedb_client.row_deleted.connect(_on_spacetimedb_row_deleted)

# --- SpacetimeDB Signal Handlers ---

func _on_spacetimedb_connected():
	print("Game: Connected to SpacetimeDB!")
	# Subscribe after connection
	var sub_req_id = spacetimedb_client.subscribe(["SELECT * FROM message", "SELECT * FROM user"])
	if sub_req_id < 0:
		printerr("Game: Failed to send subscription request.")
	else:
		print("Game: Subscription request sent (Req ID: %d)." % sub_req_id)

func _on_spacetimedb_disconnected():
	print("Game: Disconnected from SpacetimeDB.")
	# Despawn all players on disconnect
	for identity_bytes in spawned_players.keys():
		_despawn_player(identity_bytes)
	local_player_node = null
	# Handle reconnection logic? UI update?

func _on_spacetimedb_connection_error(code, reason):
	printerr("Game: SpacetimeDB Connection Error: ", reason)
	# Show error message to user? Retry connection?

func _on_spacetimedb_identity_received(identity_token: IdentityTokenData):
	print("Game: My Identity: 0x", identity_token.identity.hex_encode())
	local_identity_bytes = identity_token.identity
	# If local player already exists (e.g., from previous session data), mark it
	if spawned_players.has(local_identity_bytes):
		var player_node = spawned_players[local_identity_bytes]
		if is_instance_valid(player_node):
			player_node.set_meta("local", true)
			local_player_node = player_node
			print("Game: Marked existing player as local.")

func _on_spacetimedb_database_initialized():
	print("Game: Local database initialized.")
	# Spawn all initially online players from the local DB
	var db = spacetimedb_client.get_local_database()
	if not db: return
	var initial_users: Array[Resource] = db.get_all_rows("user")
	print("Game: Spawning initial players from DB. Count: ", initial_users.size())
	for user_res in initial_users:
		if user_res is User:
			_handle_user_update(user_res) # Use the update handler for spawning

# --- Row Change Handlers (Insert/Update/Delete) ---

func _on_spacetimedb_row_inserted(table_name: String, row: Resource):
	#print("Game: Row inserted into '", table_name, "'")
	if row is User:
		_handle_user_update(row) # Handle insert like an update
	elif row is Message:
		# Handle new message display if needed
		print("Game: New message received: ", row.text)

func _on_spacetimedb_row_updated(table_name: String, row: Resource):
	#print("Game: Row updated in '", table_name, "'")
	if row is User:
		_handle_user_update(row)

func _on_spacetimedb_row_deleted(table_name: String, primary_key):
	#print("Game: Row deleted from '", table_name, "' PK: ", primary_key)
	if table_name == "user":
		# primary_key for user is identity (PackedByteArray)
		if primary_key is PackedByteArray:
			_despawn_player(primary_key)
		else:
			printerr("Game: Received user deletion with unexpected PK type: ", typeof(primary_key))

# --- Player Management Logic ---

# Handles both inserts and updates for User rows
func _handle_user_update(user_data: User):
	var identity_bytes := user_data.identity
	var is_spawned := spawned_players.has(identity_bytes)
	var player_node = spawned_players.get(identity_bytes) # Might be null or invalid

	if user_data.online:
		# --- Player should be online ---
		if not is_spawned or not is_instance_valid(player_node):
			# Spawn new player
			_spawn_player(user_data)
		else:
			# Player already exists, update its state (position, direction)
			# Only update non-local players directly. Local player updates itself mostly.
			if player_node != local_player_node:
				# TODO: Implement smooth interpolation/extrapolation here
				# For now, just teleport for simplicity:
				player_node.global_position = Vector3(user_data.last_position_x, user_data.last_position_y, user_data.last_position_z)
				# Update visual rotation based on direction
				var dir := Vector3(user_data.direction_x, 0, user_data.direction_y) # Assuming Y is up
				if dir.length_squared() > 0.01:
					# Look towards the direction (adjust based on your model's forward axis)
					player_node.look_at(player_node.global_position + dir, Vector3.UP)
			else:
				# --- Correction for Local Player ---
				# If local player is NOT currently providing input, gently correct its position
				# towards the server state to prevent drift.
				if local_player_node and local_player_node.get_movement_input().is_zero_approx():
					var server_pos = Vector3(user_data.last_position_x, user_data.last_position_y, user_data.last_position_z)
					var current_pos = local_player_node.global_position
					if not current_pos.is_equal_approx(server_pos):
						# Lerp towards server position (adjust alpha for smoothness)
						local_player_node.global_position = current_pos.lerp(server_pos, 0.1)
						print("Game: Correcting local player position.")


	else:
		# --- Player should be offline ---
		if is_spawned and is_instance_valid(player_node):
			# Despawn existing player
			_despawn_player(identity_bytes)

func _spawn_player(user_data: User):
	if not player_prefab:
		#printerr("Game: Player prefab not set!")
		return
	if spawned_players.has(user_data.identity):
		#printerr("Game: Trying to spawn player that already exists: ", user_data.identity.hex_encode())
		return

	#print("Game: Spawning player: ", user_data.name, " (", user_data.identity.hex_encode().left(8),"...)")
	var player_node: RigidBody3D = player_prefab.instantiate()
	add_child(player_node) # Add to the scene

	# Set initial state
	player_node.global_position = Vector3(user_data.last_position_x, user_data.last_position_y, user_data.last_position_z)
	# Set initial rotation based on direction (if needed)
	var dir := Vector3(user_data.direction_x, 0, user_data.direction_y)
	if dir.length_squared() > 0.01:
		player_node.look_at(player_node.global_position + dir, Vector3.UP)

	# Store reference and mark if local
	spawned_players[user_data.identity] = player_node
	player_node.set_meta("identity_bytes", user_data.identity) # Store identity in node meta

	if local_identity_bytes and user_data.identity == local_identity_bytes:
		player_node.set_meta("local", true)
		local_player_node = player_node
		# Connect signal from local player to send input updates
		player_node.movement_input_changed.connect(_on_local_player_input_changed)
		#print("Game: Spawned LOCAL player.")
	else:
		player_node.set_meta("local", false)
		#print("Game: Spawned REMOTE player.")

func _despawn_player(identity_bytes: PackedByteArray):
	if spawned_players.has(identity_bytes):
		var player_node = spawned_players[identity_bytes]
		#print("Game: Despawning player: ", identity_bytes.hex_encode().left(8),"...")
		if is_instance_valid(player_node):
			# Disconnect signals if it was the local player
			if player_node == local_player_node:
				if player_node.is_connected("movement_input_changed", Callable(self, "_on_local_player_input_changed")):
					player_node.movement_input_changed.disconnect(_on_local_player_input_changed)
				local_player_node = null
			player_node.queue_free() # Remove from scene
		spawned_players.erase(identity_bytes) # Remove from dictionary
	else:
		print("Game: Tried to despawn player that doesn't exist: ", identity_bytes.hex_encode().left(8),"...")

# --- Local Player Input Handling ---

# Called when the local player's input vector changes
func _on_local_player_input_changed(new_input: Vector2):
	if not spacetimedb_client or not spacetimedb_client.is_connected_db():
		return # Don't send if not connected

	#print("Game: Local input changed: ", new_input, ". Sending move reducer call.")
	# Call the 'move' reducer with the new direction (input vector)
	# The server will calculate the position based on its last known state.
	spacetimedb_client.call_reducer("move_user", {
		"direction_x": new_input.x,
		"direction_z": new_input.y # Assuming Y in Vector2 maps to Z in 3D world for direction
		# We DO NOT send position from the client anymore
	})
	# Note: We don't wait for the response here. The update will come via row_updated.
