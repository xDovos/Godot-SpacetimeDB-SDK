
## Setup

1.  **Copy Addon:** Copy the `godot client/SpacetimeDB` directory into your Godot project'.

2.  **Create Schema Resources:**
    *   In the `res://schema` directory (or a path you configure in `SpacetimeDBClient`), create `.gd` scripts inheriting from `Resource` for **each table** in your SpacetimeDB module.
    *   Use `@export` for each field in the exact order they appear in your Rust struct definition.
    *   Use appropriate Godot types (`PackedByteArray` for `Identity`, `int` for `Timestamp`/`u64`/`i64`, `float` for `f32`, `String` for `String`, `bool` for `bool`).
    *   **Crucially:** Add metadata in the `_init()` function of each schema resource:
        *   `set_meta("primary_key", "your_pk_field_name")` - Specify the field name used as the primary key.
        *   `set_meta("bsatn_type_your_int_field", "u64")` (or `i64`, `u32`, etc.) - Specify the exact BSATN integer type for **all** `@export var field_name: int` properties.

    **Example (`schema/User.gd`):**
    ```gdscript
    extends Resource
    class_name User

    @export var identity: PackedByteArray
    @export var name: String
    @export var online: bool
    @export var last_position_x: float
    # ... other fields ...
    @export var last_update: int

    func _init():
        set_meta("primary_key", "identity")
        set_meta("bsatn_type_last_update", "i64") # Specify BSATN type for int field
    ```

## Usage

1.  **Add Client Node:** Add the `SpacetimeDBClient` node to your main scene (e.g., as a child of your root node or as an Autoload).
2.  **Configure Client:** In the Inspector, set the `Base Url`, `Database Name`, and optionally `Schema Path` and `Token Save Path`. Ensure `Auto Connect` is checked if desired.
3.  **Connect Signals:** In your main game script (`_ready()` function), connect to the signals provided by the `SpacetimeDBClient` instance:

    ```gdscript
    @onready var spacetimedb_client: SpacetimeDBClient = $SpacetimeDBClient # Get node reference

    func _ready():
        spacetimedb_client.connected.connect(_on_spacetimedb_connected)
        spacetimedb_client.disconnected.connect(_on_spacetimedb_disconnected)
        spacetimedb_client.connection_error.connect(_on_spacetimedb_connection_error)
        spacetimedb_client.identity_received.connect(_on_spacetimedb_identity_received)
        spacetimedb_client.database_initialized.connect(_on_spacetimedb_database_initialized)
        spacetimedb_client.transaction_update_received.connect(_on_transaction_update)
        # Local DB signals for direct UI/game state updates
        spacetimedb_client.row_inserted.connect(_on_spacetimedb_row_inserted)
        spacetimedb_client.row_updated.connect(_on_spacetimedb_row_updated)
        spacetimedb_client.row_deleted.connect(_on_spacetimedb_row_deleted)

        # Client will auto-connect if configured, otherwise call:
        # spacetimedb_client.connect()
    ```

4.  **Handle Connection & Initialization:** Implement the connected functions (`_on_spacetimedb_connected`, `_on_spacetimedb_identity_received`, `_on_spacetimedb_database_initialized`). Subscribe to tables after connecting:

    ```gdscript
    func _on_spacetimedb_connected():
        print("Game: Connected!")
        # Subscribe to desired tables
        spacetimedb_client.subscribe(["SELECT * FROM user", "SELECT * FROM message"])

    func _on_spacetimedb_identity_received(identity_token: IdentityTokenData):
        print("Game: My Identity: 0x", identity_token.identity.hex_encode())
        # Store identity if needed

    func _on_spacetimedb_database_initialized():
        print("Game: Local database ready.")
        # Initial game state setup using the local DB
        var db = spacetimedb_client.get_local_database()
        var initial_users = db.get_all_rows("user")
        print("Initial online users: ", initial_users.filter(func(u): return u.online).size())
        # ... spawn initial players ...
    ```

5.  **React to Data Changes:** Implement `_on_spacetimedb_row_inserted`, `_on_spacetimedb_row_updated`, `_on_spacetimedb_row_deleted` to update your game state (spawn/despawn entities, update UI, etc.) based on changes in the `LocalDatabase`.

    ```gdscript
    func _on_spacetimedb_row_inserted(table_name: String, row: Resource):
        if row is User and row.online:
            _spawn_player(row) # Your function to create a player node

    func _on_spacetimedb_row_updated(table_name: String, row: Resource):
         if row is User:
            _update_player(row) # Your function to update position, state, etc.

    func _on_spacetimedb_row_deleted(table_name: String, primary_key):
        if table_name == "user":
            _despawn_player(primary_key) # Your function to remove player node
    ```

6.  **Call Reducers:** Use `spacetimedb_client.call_reducer(reducer_name, args_dictionary)` to trigger server-side logic. Handle the response by listening to the `transaction_update_received` signal and matching the `request_id`.

    ```gdscript
    func send_player_input(direction: Vector2):
        if not spacetimedb_client.is_connected(): return

        # Call the 'move_user' reducer (using JSON for now)
        spacetimedb_client.call_reducer("move_user", {
            "direction_x": direction.x,
            "direction_z": direction.y # Map Y input to Z direction
        })
        # Note: Response handling via signals is needed for confirmation/errors
    ```

7.  **Query Local Database:** Access the cached data at any time:

    ```gdscript
    func get_player_name(identity_bytes: PackedByteArray) -> String:
        var db = spacetimedb_client.get_local_database()
        if db:
            var user_res = db.get_row("user", identity_bytes)
            if user_res is User:
                return user_res.name
        return "Unknown"
    ```

## Compression

*   **Gzip:** **NOT SUPPORTED for now, but planned.**
*   **Brotli:** **NOT SUPPORTED out-of-the-box.** If the server sends Brotli-compressed messages (tag `0x01`), the parser will report an error. To handle Brotli, you need to:
    1.  Obtain or create a GDExtension/GDNative module that wraps a C/C++ Brotli library.
    2.  Modify `SpacetimeDB/DataDecompressor.gd` to call your native decompression function in the `CompressionType.BROTLI` case.
    *Alternatively, configure your SpacetimeDB server to disable compression (disabled by default in client options for now).*

## TODO / Future Improvements

*   Implement BSATN **Serialization** for client messages (`Subscribe`, `CallReducer`, etc.) to replace the current JSON workaround.
*   Implement proper response handling (matching `request_id`) for `call_reducer`.
*   Add support for other `ServerMessage` types (`SubscribeApplied`, `SubscriptionError`, etc.).
*   Provide a working Brotli/GZip decompression solution (likely via GDExtension).
*   Add support for more BSATN types (arrays, sums, tuples) in the parser if needed.
*   Improve error handling and reporting.
*   Add configuration options for timeouts, reconnection attempts.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details (or state that it's MIT if no file is present).
