# SpacetimeDB Godot SDK

## TESTED WITH: `GODOT 4.4.1` and `SpacetimeDB 1.1.0`

This SDK provides the necessary tools to integrate your Godot Engine project with a SpacetimeDB backend, enabling real-time data synchronization and server interaction directly from your Godot client.

## Quick Start / Setup & Usage

Follow these steps to get your Godot project connected to SpacetimeDB:

1.  **Copy Addon:** Download the `SpacetimeDB` folder and copy it into your Godot project's `addons/` directory. Create the `addons/` directory at the root of your project if it doesn't exist.
    ```
    YourGodotProject/
    ├── addons/
    │   └── SpacetimeDB/
    │       ├── plugin.cfg
    │       └── ... (SDK files)
    ├── project.godot
    └── ... (your game files)
    ```

2.  **Enable Plugin:**
    *   Open your Godot project.
    *   Go to `Project -> Project Settings -> Plugins`.
    *   Find "SpacetimeDB" and check "Enable".
    *   This registers `SpacetimeDB` as an **Autoload Singleton**, making it globally accessible via the name `SpacetimeDB`.

3.  **Create Schema Resources:**
    *   In a dedicated directory (e.g., `res://schema/`), create `.gd` scripts inheriting from `Resource` for **each table** in your SpacetimeDB module. Use `class_name` for easier referencing.
    *   Use `@export` for each field, ensuring the **name and order** exactly match your Rust struct definition.
    *   Use appropriate Godot types (`PackedByteArray` for `Identity`, `int` for numbers, `float` for floats, `String`, `bool`, `Vector2`, `Vector3`, `Color`, `Quaternion`, `Array[Type]`).
    *   **Crucially:** Add metadata in the `_init()` function of each schema resource using `set_meta()`:
        *   `set_meta("table_name", "YourTableName")` - *(Optional)* Defaults to the script's filename if omitted. Helps ensure the correct table name is used internally.
        *   `set_meta("primary_key", "your_pk_field_name")` - **Required.** Specify the `@export`ed field name used as the primary key.
        *   `set_meta("bsatn_type_your_int_field", "u32")` (or `i8`, `u8`, `i16`, `u16`, `i32`, `u64`, `i64`) - **Required for non-i64 integers.** Specify the exact BSATN integer type for **all** `@export var field_name: int` properties that *are not* `i64` on the server.
        *   `set_meta("bsatn_type_your_float_field", "f64")` - **Required for f64 floats.** Specify if a field uses `f64` instead of the default `f32`.

    **Example (`res://schema/player_data.gd`):**
    ```gdscript
    # Assumes Rust struct:
    # #[spacetimedb(table)]
    # pub struct PlayerData {
    #     #[primarykey]
    #     identity: Identity,
    #     name: String,
    #     health: u32,
    #     ammo: i16,
    #     last_seen: Timestamp, // i64
    #     pos: Vector2, // f32, f32
    # }
    extends Resource
    class_name PlayerData

    @export var identity: PackedByteArray # SpacetimeDB Identity (32 bytes)
    @export var name: String
    @export var health: int # Represents u32 on server
    @export var ammo: int   # Represents i16 on server
    @export var last_seen: int # Represents i64 (Timestamp) on server
    @export var pos: Vector2

    func _init():
        set_meta("table_name", "PlayerData") # Good practice
        set_meta("primary_key", "identity") # REQUIRED
        # REQUIRED for non-i64 integers:
        set_meta("bsatn_type_health", "u32")
        set_meta("bsatn_type_ammo", "i16")
        # Not required for last_seen as int defaults to i64
        # Not required for pos as Vector2 defaults to f32
    ```
    **!!! IMPORTANT: Every table MUST have a primary key defined via `set_meta("primary_key", ...)` for the local database and deserialization to work correctly !!!**

4.  **Configure & Connect:**
    *   *(Optional)* Configure default connection settings via the Editor: `Project -> Project Settings -> Autoload`, select `SpacetimeDB`. Set `Base Url`, `Database Name`, `Schema Path`, etc. Check `Auto Connect` if desired.
    *   Connect programmatically (if not using Auto Connect or need dynamic connection) and listen to signals in a main script (e.g., `_ready()`):

    ```gdscript
    # In your main scene script or another Autoload

    func _ready():
        # Connect to signals BEFORE connecting to the DB
        SpacetimeDB.connected.connect(_on_spacetimedb_connected)
        SpacetimeDB.disconnected.connect(_on_spacetimedb_disconnected)
        SpacetimeDB.connection_error.connect(_on_spacetimedb_connection_error)
        SpacetimeDB.identity_received.connect(_on_spacetimedb_identity_received)
        SpacetimeDB.database_initialized.connect(_on_spacetimedb_database_initialized)
        SpacetimeDB.transaction_update_received.connect(_on_transaction_update) # For reducer results

        # --- Choose ONE connection method ---
        # A) If Auto Connect is enabled in Autoload settings, it will connect automatically.
        # B) Connect manually:
        var options = SpacetimeDBConnectionOptions.new()
        options.compression = SpacetimeDBConnection.CompressionPreference.NONE
        options.one_time_token = true
        options.debug_mode = false
        options.inbound_buffer_size = 1024 * 1024 * 2 # 2MB
        options.outbound_buffer_size = 1024 * 1024 * 2 # 2MB

        SpacetimeDB.connect_db(
            "http://127.0.0.1:3000", # Base HTTP URL
            "my_game_database",     # Database Name
            options
        )
        # ------------------------------------

    func _on_spacetimedb_connected():
        print("Game: Connected to SpacetimeDB!")
        # Good place to subscribe to initial data
        var queries = ["SELECT * FROM PlayerData", "SELECT * FROM GameState"]
        var req_id = SpacetimeDB.subscribe(queries)
        if req_id < 0: printerr("Subscription failed!")

    func _on_spacetimedb_identity_received(identity_token: IdentityTokenData):
        print("Game: My Identity: 0x%s" % identity_token.identity.hex_encode())
        # Store identity if needed, e.g., var my_identity = identity_token.identity

    func _on_spacetimedb_database_initialized():
        print("Game: Local database cache initialized.")
        # Safe to query the local DB for initially subscribed data
        var db = SpacetimeDB.get_local_database()
        var initial_players = db.get_all_rows("PlayerData")
        print("Initial players found: %d" % initial_players.size())
        # ... setup initial game state ...

    func _on_spacetimedb_disconnected():
        print("Game: Disconnected.")

    func _on_spacetimedb_connection_error(code, reason):
        printerr("Game: Connection Error (Code: %d): %s" % [code, reason])

    func _on_transaction_update(update: TransactionUpdateData):
        # Handle results/errors from reducer calls
        if update.status.status_type == UpdateStatusData.StatusType.FAILED:
            printerr("Reducer call (ReqID: %d) failed: %s" % [update.reducer_call.request_id, update.status.failure_message])
        elif update.status.status_type == UpdateStatusData.StatusType.COMMITTED:
            print("Reducer call (ReqID: %d) committed." % update.reducer_call.request_id)
            # Optionally inspect update.status.committed_update for DB changes
    ```

5.  **React to Data Changes:** You have two main ways:

    *   **A) Using `RowReceiver` Node (Recommended for specific tables):**
        1.  Add a `RowReceiver` node to your scene.
        2.  In the Inspector, set `Data To Receive` to your schema resource (e.g., `PlayerData.tres` or `.gd`).
        3.  Connect to its `insert(row)`, `update(row, previous)` and `delete(row)` signals.

        ```gdscript
        # Script needing player updates
        @export var player_receiver: RowReceiver # Assign in editor

        func _ready():
            if player_receiver:
                player_receiver.insert.connect(_on_player_receiver_insert)
                # Optionally, if you want to process inserts the same way as updates, you could do:
                # player_receiver.insert.connect(on_player_receiver_update.bind(null))
                player_receiver.update.connect(_on_player_receiver_update)
                player_receiver.delete.connect(_on_player_receiver_delete)
            else:
                printerr("Player receiver not set!")

        func _on_player_receiver_insert(player: PlayerData):
            # Player inserted
            print("Receiver Insert: Player %s Health: %d" % [player.name, player.health])
            # ... spawn player visual ...

        func _on_player_receiver_update(previous_row: PlayerData, player: PlayerData):
            # Player updated
            print("Receiver Update: Player %s Health: %d" % [player.name, player.health])
            print("Receiver Previous Value: Player %s Health: %d" % [previous_row.name, previous_row.health])
            # ... update player visual ...

        func _on_player_receiver_delete(player: PlayerData):
            # Player deleted
            print("Receiver Delete: Player %s" % player.name)
            # ... despawn player visual ...
        ```

    *   **B) Using Global `SpacetimeDB` Signals:** Connect directly to the singleton's signals for broader updates across all tables.

        ```gdscript
        # In your main script's _ready() or where signals are connected:
        SpacetimeDB.row_inserted.connect(_on_global_row_inserted)
        SpacetimeDB.row_updated.connect(_on_global_row_updated)
        SpacetimeDB.row_deleted_key.connect(_on_global_row_deleted) # Passes PK, not full row

        func _on_global_row_inserted(table_name: String, row: Resource):
            if row is PlayerData: # Check the type of the inserted row
                print("Global Insert: New PlayerData row!")
                _spawn_player(row) # Your function
            elif row is GameState:
                print("Global Insert: GameState updated!")
                # ... update game state UI ...

        func _on_global_row_updated(table_name: String, row: Resource):
             if row is PlayerData:
                print("Global Update: PlayerData updated!")
                _update_player(row) # Your function

        func _on_global_row_deleted(table_name: String, primary_key):
            # Note: This signal provides the primary key, not the full row data
            if table_name == "PlayerData":
                print("Global Delete: PlayerData with PK %s deleted!" % str(primary_key))
                _despawn_player(primary_key) # Your function needs to handle lookup by PK
        ```

6.  **Call Reducers:** Use `SpacetimeDB.call_reducer(reducer_name, args_array, types_array)` to trigger server-side logic.

    ```gdscript
    func move_player(direction: Vector2):
        if not SpacetimeDB.is_connected_db(): return
        var req_id = SpacetimeDB.call_reducer("move", [direction])
        if req_id < 0:
            printerr("Failed to call 'move' reducer.")
        # Response/errors handled via the 'transaction_update_received' signal connection

    func send_chat(message: String):
         if not SpacetimeDB.is_connected_db(): return
         var req_id = SpacetimeDB.call_reducer("send_message", [message])
         var req_id_2 = SpacetimeDB.call_reducer("send_u8", [1], ["u8"])
         # ... handle potential errors via signal ...
    ```

7.  **Query Local Database:** Access the cached data synchronously at any time.

    ```gdscript
    func get_player_health(identity: PackedByteArray) -> int:
        var db = SpacetimeDB.get_local_database()
        if db:
            # Use table name (from schema or metadata) and primary key
            var player: PlayerData = db.get_row("PlayerData", identity)
            if player:
                return player.health
        return -1 # Indicate not found or error

    func get_all_cached_players() -> Array[PlayerData]:
        var db = SpacetimeDB.get_local_database()
        if db:
            return db.get_all_rows("PlayerData") # Returns Array[Resource], cast if needed
        return []
    ```

## Technical Details

### Type System & Serialization

The SDK handles serialization between Godot types and SpacetimeDB's BSATN format based on your schema Resources.

*   **Default Mappings:**
    *   `bool` <-> `bool`
    *   `int` <-> `i64` (Signed 64-bit integer)
    *   `float` <-> `f32` (Single-precision float)
    *   `String` <-> `String` (UTF-8)
    *   `Vector2`/`Vector3`/`Color`/`Quaternion` <-> Matching server struct (f32 fields)
    *   `PackedByteArray` <-> `Vec<u8>` (Default) OR `Identity` 
    *   `Array[T]` <-> `Vec<T>` (Requires typed array hint, e.g., `@export var scores: Array[int]`)
    *   Nested `Resource` <-> `struct` (Fields serialized inline)

*   **Metadata for Specific Types:** Use `set_meta("bsatn_type_fieldname", "type_string")` in your schema's `_init()` for:
    *   Integers other than `i64` (e.g., `"u8"`, `"i16"`, `"u32"`).
    *   Floats that are `f64` (use `"f64"`).

*   **Reducer Type Hints:** The `types` array in `call_reducer` helps serialize arguments correctly, especially important for non-default integer/float types.

### Supported Data Types

*   **Primitives:** `bool`, `int` (maps to `i8`-`i64`, `u8`-`u64` via metadata/hints), `float` (maps to `f32`, `f64` via metadata/hints), `String`
*   **Godot Types:** `Vector2`, `Vector3`, `Color`, `Quaternion` (require compatible server structs)
*   **Byte Arrays:** `PackedByteArray` (maps to `Vec<u8>` or `Identity`)
*   **Collections:** `Array[T]` (requires typed `@export` hint)
*   **Custom Resources:** Nested `Resource` classes defined in your schema path.

### API Reference (High Level - via `SpacetimeDB` Singleton)

*   **Methods:** `connect_db`, `disconnect_db`, `is_connected_db`, `get_local_database`, `get_local_identity`, `subscribe`, `unsubscribe` (use with caution), `call_reducer`, `wait_for_reducer_response`.
*   **Signals:** `connected`, `disconnected`, `connection_error`, `identity_received`, `database_initialized`, `transaction_update_received`, `row_inserted`, `row_updated`, `row_deleted`, `row_deleted_key`.

## Compression

*   **Client -> Server:** Not currently implemented. Messages sent from the client (like reducer calls) are uncompressed.
*   **Server -> Client:**
    *   **None (0x00):** Fully supported. This is the default requested by the client.
    *   **Gzip (0x02):** **NOT SUPPORTED.** The deserializer will fail if it receives Gzip data.
    *   **Brotli (0x01):** **NOT SUPPORTED out-of-the-box.** If the server sends Brotli-compressed messages, the parser will report an error. To handle Brotli, you would need to:
        1.  Obtain or create a GDExtension/GDNative module wrapping a Brotli library.
        2.  Modify `addons/SpacetimeDB/BSATNDeserializer.gd` (`_get_query_update_stream` function and potentially `parse_packet`) to call your native decompression function.
    *   **Recommendation:** Ensure your SpacetimeDB server is configured *not* to send compressed messages, or only use `CompressionPreference.NONE` when connecting.

## Limitations & TODO

*   **Manual Schema Sync:** GDScript Resources must be manually created and kept in sync (name, type, order) with Rust structs. Code generation is planned.
*   **`Option<T>` Not Supported:** Rust's `Option<T>` cannot be directly mapped. Avoid using it in table definitions or implement workarounds.
*   **Compression:** As noted above, only uncompressed messages are fully supported bidirectionally.
*   **`unsubscribe()`:** May not function reliably in all cases.
*   **Error Handling:** Can be improved, especially for reducer call failures beyond basic connection errors.
*   **Configuration:** More options could be added (timeouts, reconnection).

## License

<!-- [PLACEHOLDER: Specify your license, e.g.:] -->
This project is licensed under the MIT License.
