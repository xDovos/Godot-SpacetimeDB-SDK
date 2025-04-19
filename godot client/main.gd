extends Node3D

@export var player_prefab: PackedScene

func _ready():
	SpacetimeDB.connect_db(
		"https://flametime.cfd/spacetime", #WARNING <--- replace it with your url
		"quickstart-chat", #WARNING <--- replace it with your database
		SpacetimeDBConnection.CompressionPreference.NONE,
		true #WARNING <--- one time token. New window = new token
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

func _on_spacetimedb_identity_received(identity_token: IdentityTokenData):
	print("Game: My Identity: 0x", identity_token.identity.hex_encode())

func _on_spacetimedb_database_initialized():
	print("Game: Local database initialized.")
