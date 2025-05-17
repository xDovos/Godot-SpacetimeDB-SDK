# SpacetimeDB Godot SDK

## TESTED WITH: `GODOT 4.4.1` and `SpacetimeDB 1.1.0`

This SDK provides the necessary tools to integrate your Godot Engine project with a SpacetimeDB backend, enabling real-time data synchronization and server interaction directly from your Godot client.

## Quick Start / Setup & Usage

Follow these steps to get your Godot project connected to SpacetimeDB:

1. Upload your SpacetimeDB module

    Our code-gen tool uses the SpacetimeDB API endpoint to generate all types and reducers, so first upload your SpacetimeDB module to the server.
   
    IMPORTANT: Every table must have a primary key for the local database and deserialization to work correctly.
 
3.  **Copy Addon:** Download the `SpacetimeDB` folder and copy it into your Godot project's `addons/` directory. Create the `addons/` directory at the root of your project if it doesn't exist.
    ```
    YourGodotProject/
    ├── addons/
    │   └── SpacetimeDB/
    ├── spacetime_data
    │   └── All generated code and plugin data
    └── your game files
    ```

2.  **Enable Plugin:**
    *   Open your Godot project.
    *   Go to `Project -> Project Settings -> Plugins`.
    *   Find "SpacetimeDB" and check "Enable".
    *   This registers `SpacetimeDB` as an **Autoload Singleton**, making it globally accessible via the name `SpacetimeDB`.
3. **Setup plugin and generate code**
    * Open the new SpacetimeDB tab in the bottom dock.
    * Replace the default URL with your server’s URL.
    * Click `+` to add a module
    * Name the module exactly as you published it (e.g., main)
    * Click `Generate schema` button
    * The generated code now appears in the `spacetime_data/` folder.
      
![image](https://github.com/user-attachments/assets/bd4aef29-8528-43c7-8011-c1e9df05537f)

5.  **Configure & Connect:**
    *   Connect:
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

        var options = SpacetimeDBConnectionOptions.new()
        options.compression = SpacetimeDBConnection.CompressionPreference.NONE
        options.one_time_token = true
        options.debug_mode = false
        options.inbound_buffer_size = 1024 * 1024 * 2 # 2MB
        options.outbound_buffer_size = 1024 * 1024 * 2 # 2MB

        SpacetimeDB.connect_db(
            "http://127.0.0.1:3000", # Base HTTP URL
            "my_module",     # Module Name
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

6.  **React to Data Changes:** You have two main ways:

    *   **A) Using `RowReceiver` Node (Recommended for specific tables):**
        1.  Add a `RowReceiver` node to your scene.
        2.  In the Inspector, set `Table To Receive` to your schema resource via dropdown menu (e.g., `PlayerData`).
        3.  Connect to its `insert(row)`, `update(previous_row, new_row)` and `delete(row)` signals.

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

7.  **Call Reducers:** Use generated code to trigger server-side logic.

    ```gdscript
    func move_player(direction: Vector2):
        if not SpacetimeDB.is_connected_db(): return
    
        #You can use callback, but it doesn`t required
        #Example with callback 
        SpacetimeModule.Main.Reducers.move_user(direction, global_position, func(_t:TransactionUpdateData): 
		    print("Result:", _t)
		    pass)
    
        #Example without callback
        SpacetimeModule.Main.Reducers.move_user(direction, global_position)
    
        #Or use module name 
        MainModule.move_user(direction, global_position)
    ```

8.  **Query Local Database:** Access the cached data synchronously at any time.

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
            return db.get_all_rows("PlayerData") # Returns Array[ModuleTable], cast if needed
        return []
    ```

9. **Rust Enums In Godot:**
There is full support for rust enum sumtypes when derived from SpacetimeType.

The following is fully supported syntax:
```rs
#[derive(spacetimedb::SpacetimeType, Debug, Clone)]
pub enum CharacterClass {
    Warrior(Vec<i32>),
    Mage(CharacterMageData),
    Archer(ArcherOptions),
}

#[derive(SpacetimeType, Debug, Clone)]
pub struct CharacterMageData {
    mana: u32,
    spell_power: u32,
    other: Vec<u8>,
}

#[derive(SpacetimeType, Debug, Clone)]
pub enum ArcherOptions {
    None,
    Bow(BowOptions),
    Crossbow,
}

#[derive(SpacetimeType, Debug, Clone)]
pub enum BowOptions {
    None,
    Longbow,
    Shortbow,
}
```
This will codegen the following for CharacterClass:
![image](https://github.com/user-attachments/assets/cdd5cddd-8a15-4da2-a0bb-ef0a1e446883)

There are static functions to create specific enum variants in godot as well as getters to return the variant as the specific type.
The following is how to create and match through and enum:
```gdscript
var cc = TestModule.CharacterClass.create_warrior([1,2,3,4,5])
match cc.value:
	cc.Warrior:
		var warrior: = cc.get_warrior()
		var first: = warrior[0]
		print_debug("Warrior:", first)
```
With this you will have full support for code completion due to strong types being returned.
![image](https://github.com/user-attachments/assets/ddfeab8b-1423-41b0-84ca-52af19c96015)

![image](https://github.com/user-attachments/assets/3bb7cac8-78d4-40b7-90f8-20e19274d94a)

Since BowOptions in rust is not being used as a sumtype in godot it becomes just a standard enum.

![image](https://github.com/user-attachments/assets/0c4b4c00-c479-47cc-a459-394b917457c1)

	
## Technical Details

### Type System & Serialization

The SDK handles serialization between Godot types and SpacetimeDB's BSATN format based on your schema Resources.

*   **Default Mappings:**
    *   `bool` <-> `bool`
    *   `int` <-> `i64` (Signed 64-bit integer)
    *   `float` <-> `f64` (Single-precision float)
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
*   **Rust Enums:** Code generator creates a RustEnum class in Godot

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

*   **`Option<T>` Not Supported:** Rust's `Option<T>` cannot be directly mapped. Avoid using it in table definitions or implement workarounds.
*   **Compression:** As noted above, only uncompressed messages are fully supported bidirectionally.
*   **`unsubscribe()`:** May not function reliably in all cases.
*   **Error Handling:** Can be improved, especially for reducer call failures beyond basic connection errors.
*   **Configuration:** More options could be added (timeouts, reconnection).

## License
This project is licensed under the MIT License.
