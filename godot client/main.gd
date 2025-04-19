# In your main game script (e.g., Main.gd)
extends Node3D

@export var player_prefab: PackedScene

var local_identity_bytes: PackedByteArray
var spawned_players: Dictionary = {}
var local_player_node: RigidBody3D = null

# --- Godot Lifecycle ---

func _ready():
	SpacetimeDB.connect_db(
		"https://flametime.cfd/spacetime",
		"quickstart-chat",
		0,
		true
		)

	SpacetimeDB.connected.connect(_on_spacetimedb_connected)
	SpacetimeDB.disconnected.connect(_on_spacetimedb_disconnected)
	SpacetimeDB.connection_error.connect(_on_spacetimedb_connection_error)
	SpacetimeDB.identity_received.connect(_on_spacetimedb_identity_received)

func _on_spacetimedb_connected():
	print("Game: Connected to SpacetimeDB!")
	var sub_req_id = SpacetimeDB.subscribe(["SELECT * FROM user", "SELECT * FROM user_data"])
	if sub_req_id < 0:
		printerr("Game: Failed to send subscription request.")
	else:
		print("Game: Subscription request sent (Req ID: %d)." % sub_req_id)

func _on_spacetimedb_disconnected():
	print("Game: Disconnected from SpacetimeDB.")

func _on_spacetimedb_connection_error(code, reason):
	printerr("Game: SpacetimeDB Connection Error: ", reason)
	# Show error message to user? Retry connection?

func _on_spacetimedb_identity_received(identity_token: IdentityTokenData):
	print("Game: My Identity: 0x", identity_token.identity.hex_encode())

func _on_spacetimedb_database_initialized():
	print("Game: Local database initialized.")
