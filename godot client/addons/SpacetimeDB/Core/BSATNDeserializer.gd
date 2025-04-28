class_name BSATNDeserializer extends RefCounted

# --- Constants ---
const MAX_STRING_LEN := 4 * 1024 * 1024 # 4 MiB limit for strings
const MAX_VEC_LEN := 131072            # Limit for vector elements
const IDENTITY_SIZE := 32
const CONNECTION_ID_SIZE := 16

const COMPRESSION_NONE := 0x00
const COMPRESSION_BROTLI := 0x01
const COMPRESSION_GZIP := 0x02

const SERVER_MSG_INITIAL_SUB := 0x00
const SERVER_MSG_TRANSACTION_UPDATE := 0x01
const SERVER_MSG_TRANSACTION_UPDATE_LIGHT := 0x02 
const SERVER_MSG_IDENTITY_TOKEN := 0x03
const SERVER_MSG_ONE_OFF_QUERY_RESPONSE := 0x04
const SERVER_MSG_SUBSCRIBE_APPLIED := 0x05
const SERVER_MSG_UNSUBSCRIBE_APPLIED := 0x06
const SERVER_MSG_SUBSCRIPTION_ERROR := 0x07
const SERVER_MSG_SUBSCRIBE_MULTI_APPLIED := 0x08
const SERVER_MSG_UNSUBSCRIBE_MULTI_APPLIED := 0x09

const ROW_LIST_FIXED_SIZE := 0
const ROW_LIST_ROW_OFFSETS := 1

# --- Properties ---
var _last_error: String = ""
# Stores loaded table row schema scripts: { "table_name_lower": Script }
var _possible_row_schemas: Dictionary = {}
var _decompressor := DataDecompressor.new()
# Maps Variant.Type to specialized property reader methods
var _property_readers: Dictionary = {}


# --- Initialization ---

func _init(schema_path: String = "res://schema") -> void:
	_load_row_schemas(schema_path)
	_initialize_property_readers()

# Loads table row schema scripts (e.g., UserData.gd) from a directory.
func _load_row_schemas(path: String) -> void:
	_possible_row_schemas.clear()
	
	var files := DirAccess.get_files_at(path)

	if files.is_empty() and not DirAccess.dir_exists_absolute(path):
		printerr("BSATNParser: Schema directory does not exist or is empty: ", path)
		return

	for file_name_raw in files:
		var file_name := file_name_raw # Work with a mutable copy

		# Handle potential remapping, common on export (especially Android)
		if file_name.ends_with(".remap"):
			# If it's a remap file, we need the original .gd name to load the script
			file_name = file_name.replace(".remap", "")
			# We still need the .gd extension for the load() call later
			if not file_name.ends_with(".gd"):
				file_name += ".gd"

		# Ensure we are only processing Godot scripts
		if not file_name.ends_with(".gd"):
			continue

		var script_path := path.path_join(file_name)
		# Use ResourceLoader for potentially cached resources
		if not ResourceLoader.exists(script_path):
			printerr("BSATNParser: Script file not found or inaccessible after potential remap handling: ", script_path, " (Original name: ", file_name_raw, ")")
			continue

		# Explicitly load as GDScript
		var script := ResourceLoader.load(script_path, "GDScript") as GDScript

		if script and script.can_instantiate():
			# Instantiate only once to get metadata/table name
			var instance_for_name = script.new()
			if instance_for_name:
				# Pass the original filename *without* extension for fallback name logic
				var base_name := file_name.get_basename().get_file()
				var table_name : String = _get_schema_table_name(instance_for_name, base_name)

				if not table_name.is_empty():
					_possible_row_schemas[table_name.to_lower()] = script
					# print("BSATNParser: Loaded schema for table '%s' from %s" % [table_name, script_path])
				else:
					printerr("BSATNParser: Could not determine table name for schema: ", script_path)
			else:
				printerr("BSATNParser: Failed to instantiate script even though can_instantiate() was true: ", script_path)
		elif script:
			printerr("BSATNParser: Script loaded but cannot be instantiated: ", script_path)
		else:
			printerr("BSATNParser: Failed to load script resource: ", script_path)

# Helper to determine the table name from schema instance or filename.
func _get_schema_table_name(instance: Resource, fallback_base_filename: String) -> String:
	if instance.has_meta("table_name"):
		return instance.get_meta("table_name")
	elif instance.has_method("get_table_name"):
		return instance.call("get_table_name")
	else:
		# Fallback to filename without extension
		return fallback_base_filename

# Initialize the dictionary mapping Variant types to their reader functions.
func _initialize_property_readers() -> void:
	_property_readers = {
		TYPE_PACKED_BYTE_ARRAY: Callable(self, "_read_property_packed_byte_array"),
		TYPE_INT: Callable(self, "_read_property_int"),
		TYPE_FLOAT: Callable(self, "_read_property_float"),
		TYPE_STRING: Callable(self, "_read_property_string"),
		TYPE_BOOL: Callable(self, "_read_property_bool"),
		TYPE_VECTOR3: Callable(self, "_read_property_vector3"),
		TYPE_VECTOR2: Callable(self, "_read_property_vector2"),
		TYPE_COLOR: Callable(self, "_read_property_color"),
		TYPE_ARRAY: Callable(self, "_read_property_array"),
		TYPE_OBJECT: Callable(self, "_read_property_object")
		# Add other types here if needed
	}

# --- Error Handling ---

func has_error() -> bool:
	return _last_error != ""

func get_last_error() -> String:
	var err := _last_error
	_last_error = "" # Clear error after getting
	return err

func clear_error() -> void:
	_last_error = ""

# Sets the error message if not already set. Internal use.
func _set_error(msg: String, position: int = -1) -> void:
	if _last_error == "": # Prevent overwriting the first error
		var pos_str := " (at approx. position %d)" % position if position >= 0 else ""
		_last_error = "BSATNParser Error: %s%s" % [msg, pos_str]
		printerr(_last_error) # Always print errors

# Checks if enough bytes are available to read. Sets error if not.
func _check_read(spb: StreamPeerBuffer, bytes_needed: int) -> bool:
	if has_error(): return false
	if spb.get_position() + bytes_needed > spb.get_size():
		_set_error("Attempted to read %d bytes past end of buffer (size: %d)." % [bytes_needed, spb.get_size()], spb.get_position())
		return false
	return true

# --- Primitive Value Readers ---
# These functions read basic BSATN types from the StreamPeerBuffer.
# They rely on _check_read for boundary checks and error state.

func read_i8(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 1): return 0
	var uval := spb.get_u8()
	return uval - 256 if uval >= 128 else uval

func read_i16_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 2): return 0
	spb.big_endian = false
	var uval := spb.get_u16()
	return uval - 65536 if uval >= 32768 else uval

func read_i32_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 4): return 0
	spb.big_endian = false
	var uval := spb.get_u32()
	return int(uval - 4294967296) if uval >= 2147483648 else int(uval) # Cast needed for i32 range

func read_i64_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 8): return 0
	spb.big_endian = false
	var uval := spb.get_u64()
	# Convert u64 to i64 (two's complement)
	return uval - (1 << 64) if uval >= (1 << 63) else uval

func read_u8(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 1): return 0 # Return 0 on error for unsigned
	return spb.get_u8()

func read_u16_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 2): return 0
	spb.big_endian = false
	return spb.get_u16()

func read_u32_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 4): return 0
	spb.big_endian = false
	return spb.get_u32()

func read_u64_le(spb: StreamPeerBuffer) -> int:
	if not _check_read(spb, 8): return 0
	spb.big_endian = false
	return spb.get_u64()

func read_f32_le(spb: StreamPeerBuffer) -> float:
	if not _check_read(spb, 4): return 0.0
	spb.big_endian = false
	return spb.get_float()

func read_f64_le(spb: StreamPeerBuffer) -> float:
	if not _check_read(spb, 8): return 0.0
	spb.big_endian = false
	return spb.get_double()

func read_bool(spb: StreamPeerBuffer) -> bool:
	var byte := read_u8(spb)
	if has_error(): return false
	if byte != 0 and byte != 1:
		_set_error("Invalid boolean value: %d (expected 0 or 1)" % byte, spb.get_position() - 1)
		return false
	return byte == 1

func read_bytes(spb: StreamPeerBuffer, num_bytes: int) -> PackedByteArray:
	if num_bytes < 0:
		_set_error("Attempted to read negative number of bytes: %d" % num_bytes, spb.get_position())
		return PackedByteArray()
	if num_bytes == 0:
		return PackedByteArray()

	if not _check_read(spb, num_bytes): return PackedByteArray()

	var result: Array = spb.get_data(num_bytes) # get_data returns [Error, PackedByteArray]
	if result[0] != OK:
		_set_error("StreamPeerBuffer.get_data failed with code %d" % result[0], spb.get_position() - num_bytes)
		return PackedByteArray()
	return result[1]

func read_string_with_u32_len(spb: StreamPeerBuffer) -> String:
	var start_pos := spb.get_position()
	var length := read_u32_le(spb)
	if has_error() or length == 0: return ""

	if length > MAX_STRING_LEN:
		_set_error("String length %d exceeds maximum limit %d" % [length, MAX_STRING_LEN], start_pos)
		return ""

	var str_bytes := read_bytes(spb, length)
	if has_error(): return ""

	var str_result := str_bytes.get_string_from_utf8()
	# More robust check for UTF-8 decoding errors
	if str_result == "" and length > 0:
		# Check if it was really an empty string or a decoding error
		if str_bytes.get_string_from_ascii() == "" or str_bytes.find(0) != -1:
			_set_error("Failed to decode UTF-8 string of length %d" % length, start_pos)
			return "" # Return empty string on error

	return str_result

func read_identity(spb: StreamPeerBuffer) -> PackedByteArray:
	return read_bytes(spb, IDENTITY_SIZE)

func read_timestamp(spb: StreamPeerBuffer) -> int:
	# Timestamp is represented as i64 nanoseconds since UNIX epoch
	return read_i64_le(spb)

# --- Vector/Array Reader ---

# Reads a vector (dynamic array) of elements using a provided reader function for the elements.
func read_vec(spb: StreamPeerBuffer, element_reader_func: Callable) -> Array:
	var length := read_u32_le(spb)
	if has_error() or length == 0: return []

	if length > MAX_VEC_LEN:
		_set_error("Vector length %d exceeds maximum limit %d" % [length, MAX_VEC_LEN], spb.get_position() - 4)
		return []

	# Important: Create a standard (non-typed) Array.
	# The elements added will have their correct types.
	var result_array := []
	result_array.resize(length) # Pre-allocate for performance

	for i in range(length):
		if has_error(): # Check error before reading each element
			# Error likely occurred in previous iteration or reading length
			return []

		var element_start_pos = spb.get_position()
		var element = element_reader_func.call(spb)

		if has_error(): # Check error *after* attempting to read element
			# Avoid overwriting a more specific error from the element reader
			if not _last_error.contains("element %d" % i):
				_set_error("Failed reading element %d of vector." % i, element_start_pos)
			return []

		result_array[i] = element

	return result_array

# --- BsatnRowList Reader ---

# Reads a BSATN-encoded list of rows, handling FixedSize and RowOffsets formats.
func read_bsatn_row_list(spb: StreamPeerBuffer) -> Array[PackedByteArray]:
	var start_pos := spb.get_position()
	var size_hint_type := read_u8(spb)
	if has_error(): return []

	var rows: Array[PackedByteArray] = []

	match size_hint_type:
		ROW_LIST_FIXED_SIZE: # FixedSize(RowSize)
			var row_size := read_u16_le(spb)
			var data_len := read_u32_le(spb)
			if has_error(): return []

			if row_size == 0:
				if data_len != 0:
					_set_error("FixedSize row list has row_size 0 but data_len %d" % data_len, start_pos)
					read_bytes(spb, data_len) # Attempt to skip data
					return []
				return [] # Valid empty list

			var data := read_bytes(spb, data_len)
			if has_error(): return []

			if data_len % row_size != 0:
				_set_error("FixedSize data length %d is not divisible by row size %d" % [data_len, row_size], start_pos)
				return []

			var num_rows := data_len / row_size
			rows.resize(num_rows)
			for i in range(num_rows):
				rows[i] = data.slice(i * row_size, (i + 1) * row_size)

		ROW_LIST_ROW_OFFSETS: # RowOffsets(Vec<u64>)
			var num_offsets := read_u32_le(spb)
			if has_error(): return []

			# Read offsets (Vec<u64>) - Use read_vec for cleaner code? No, direct loop is fine here.
			var offsets: Array[int] = []
			offsets.resize(num_offsets)
			for i in range(num_offsets):
				offsets[i] = read_u64_le(spb)
				if has_error(): return []

			var data_len := read_u32_le(spb)
			if has_error(): return []

			var data := read_bytes(spb, data_len)
			if has_error(): return []

			# Slice data based on offsets
			rows.resize(num_offsets)
			for i in range(num_offsets):
				var start_offset : int = offsets[i]
				var end_offset : int = data_len if (i + 1 == num_offsets) else offsets[i+1]

				if start_offset < 0 or end_offset < start_offset or end_offset > data_len:
					_set_error("Invalid row offsets: start=%d, end=%d, data_len=%d for row %d" % [start_offset, end_offset, data_len, i], start_pos)
					return []

				rows[i] = data.slice(start_offset, end_offset)

		_:
			_set_error("Unknown RowSizeHint type: %d" % size_hint_type, start_pos)
			return []

	return rows

# --- Row Deserialization ---

# Populates an existing Resource instance from raw BSATN bytes based on its exported properties.
func _populate_resource_from_bytes(resource: Resource, spb: StreamPeerBuffer) -> bool:
	if not resource or not resource.get_script():
		var err_pos := -1 if not spb else spb.get_position()
		_set_error("Cannot populate null or scriptless resource", err_pos)
		return false

	var properties: Array = resource.get_script().get_script_property_list()

	for prop in properties:
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue # Skip non-serialized properties

		var prop_name: StringName = prop.name
		var prop_type: Variant.Type = prop.type
		var value = null

		if prop_type == TYPE_ARRAY:
			# Handle arrays: Use the dedicated array reader from _property_readers
			var array_reader_callable: Callable = _property_readers.get(TYPE_ARRAY)
			if array_reader_callable.is_valid():
				# _read_property_array internally handles element type via hint/metadata
				value = array_reader_callable.call(spb, resource, prop)
			else:
				# This should not happen if initialized correctly
				_set_error("Internal error: No reader configured for TYPE_ARRAY.", spb.get_position())
				return false # Cannot proceed
		elif prop_type == TYPE_OBJECT:
			# Handle nested objects: Use the dedicated object reader
			var object_reader_callable: Callable = _property_readers.get(TYPE_OBJECT)
			if object_reader_callable.is_valid():
				# _read_property_object handles instantiation and recursive population
				value = object_reader_callable.call(spb, resource, prop)
			else:
				_set_error("Internal error: No reader configured for TYPE_OBJECT.", spb.get_position())
				return false
		else:
			# Handle non-array, non-object types (Primitives, Vector*, etc.)
			# 1. Check for specific BSATN type override via metadata
			var meta_key := "bsatn_type_" + prop_name
			var specific_reader_callable: Callable = _get_specific_bsatn_reader(resource, meta_key)

			if specific_reader_callable.is_valid():
				# Use the specific reader found via metadata (e.g., read_u8, read_i32)
				value = specific_reader_callable.call(spb)
			else:
				# 2. Fallback to default reader based on property type (if no metadata)
				if _property_readers.has(prop_type):
					var default_reader_callable: Callable = _property_readers[prop_type]
					# Pass context only if needed (shouldn't be for primitives)
					value = default_reader_callable.call(spb, resource, prop) # Pass context just in case
				else:
					# 3. Unsupported primitive/other type
					_set_error("Unsupported property type '%s' (or missing reader) for BSATN deserialization of property '%s' in resource '%s'" % [type_string(prop_type), prop_name, resource.resource_path], spb.get_position())
					return false

		# Check for errors after attempting to read the value
		if has_error():
			# Error should have been set by the reader function
			if not _last_error.contains(str(prop_name)):
				var existing_error = get_last_error() # Consume the error
				_set_error("Failed reading value for property '%s' in '%s'. Cause: %s" % [prop_name, resource.resource_path, existing_error], spb.get_position())
			return false

		# Set the read value onto the resource property using the existing function
		if not _set_resource_property(resource, prop_name, prop_type, value):
			# _set_resource_property will set the error if assignment fails
			return false

	return true # Successfully populated all properties


# Helper to get a specific reader based on "bsatn_type_" metadata.
func _get_specific_bsatn_reader(resource: Resource, meta_key: String) -> Callable:
	if resource.has_meta(meta_key):
		var bsatn_type_str: String = resource.get_meta(meta_key).to_lower()
		match bsatn_type_str:
			"u64": return Callable(self, "read_u64_le")
			"i64": return Callable(self, "read_i64_le")
			"u32": return Callable(self, "read_u32_le")
			"i32": return Callable(self, "read_i32_le")
			"u16": return Callable(self, "read_u16_le")
			"i16": return Callable(self, "read_i16_le")
			"u8": return Callable(self, "read_u8")
			"i8": return Callable(self, "read_i8")
			"identity": return Callable(self, "read_identity") # Reads fixed IDENTITY_SIZE
			"connection_id": return Callable(self, "_read_connection_id_bytes") # Reads fixed CONNECTION_ID_SIZE
			"timestamp": return Callable(self, "read_timestamp")
			# Add other specific types if needed
			_:
				push_warning("Unknown 'bsatn_type' metadata value: '%s'" % bsatn_type_str)
	return Callable() # Return invalid Callable if no specific reader found

# Helper to set the property value, handling arrays correctly.
func _set_resource_property(resource: Resource, prop_name: StringName, prop_type: Variant.Type, value) -> bool:
	if value == null:
		# Don't attempt to set null unless the property type supports it.
		# GDScript generally doesn't allow setting null for primitive/@export vars easily.
		# Assume null means an error occurred or it's an unsupported type for now.
		# If null is a valid state for some types, this needs adjustment.
		if not has_error(): # Only warn if no error was explicitly set before
			push_warning("Read value for property '%s' was null. Skipping assignment." % prop_name)
		return true # Continue parsing other properties

	if prop_type == TYPE_ARRAY:
		# Assign elements to the existing typed array
		var target_array = resource.get(prop_name)
		if target_array is Array:
			target_array.assign(value) # Use assign for typed arrays
			return true
		else:
			_set_error("Property '%s' expected Array type but resource.get returned %s" % [prop_name, typeof(target_array)], -1)
			return false
	else:
		# For non-array types or if target isn't an array, use direct assignment
		# This assumes the type read matches the property type.
		resource[prop_name] = value
		return true

# --- Property Type Readers (Called by _populate_resource_from_bytes) ---
# These methods read specific Variant types. `resource` and `prop` are passed
# mainly for context needed by array reading.

# Reads a PackedByteArray property based on metadata or defaults to Vec<u8>.
func _read_property_packed_byte_array(spb: StreamPeerBuffer, resource: Resource, prop: Dictionary) -> PackedByteArray:
	# This function is called ONLY if _get_specific_bsatn_reader did NOT find
	# specific metadata like 'identity', 'connection_id', etc.
	# Therefore, the default behavior here MUST be Vec<u8>.

	# Default behavior: Read as Vec<u8> (u32 length + bytes).
	var start_pos := spb.get_position()
	var length := read_u32_le(spb)
	if has_error(): return PackedByteArray()

	const MAX_BYTE_ARRAY_LEN = 16 * 1024 * 1024 # Example: 16 MiB limit
	if length > MAX_BYTE_ARRAY_LEN:
		_set_error("PackedByteArray (Vec<u8>) length %d exceeds maximum limit %d for property '%s'" % [length, MAX_BYTE_ARRAY_LEN, prop.name], start_pos)
		return PackedByteArray()
	if length == 0:
		return PackedByteArray() # Valid empty array

	return read_bytes(spb, length)

# Reads an embedded Resource property (TYPE_OBJECT).
# Assumes the resource fields are serialized inline without length prefix.
# Uses the preloaded _possible_row_schemas for instantiation.
func _read_property_object(spb: StreamPeerBuffer, resource: Resource, prop: Dictionary) -> Resource:
	var prop_name: StringName = prop.name
	# The class name comes from the property definition's hint
	var nested_class_name: StringName = prop.class_name

	# 1. Check if the property hint specified a class name
	if nested_class_name == &"":
		_set_error("Property '%s' is TYPE_OBJECT but has no class_name hint in script '%s'. Cannot deserialize." % [prop_name, resource.get_script().resource_path], spb.get_position())
		return null

	# 2. Look up the required schema script in our preloaded dictionary
	var key := nested_class_name.to_lower()
	if not _possible_row_schemas.has(key):
		# Error: The required schema wasn't loaded during initialization
		_set_error("Could not find preloaded schema '%s' (required by property '%s') in _possible_row_schemas. Ensure the script exists and is correctly named or has 'table_name' metadata." % [nested_class_name, prop_name], spb.get_position())
		return null # Cannot proceed without the schema script

	# 3. Get the script and attempt to instantiate it
	var script: Script = _possible_row_schemas[key]
	if not script:
		# This case should be unlikely if .has(key) returned true, but check defensively
		_set_error("Internal error: Schema found for key '%s' but script object is null (property '%s')." % [key, prop_name], spb.get_position())
		return null

	var nested_instance: Resource = script.new()

	# 4. Check if instantiation was successful
	if nested_instance == null:
		# Error: script.new() failed for some reason (e.g., script error)
		var script_path = script.resource_path if script else "Unknown Script"
		_set_error("Failed to instantiate nested resource from script '%s' (required by property '%s'). Check the script for errors." % [script_path, prop_name], spb.get_position())
		return null # Instantiation failed

	# 5. Recursively populate the newly created nested resource instance
	if not _populate_resource_from_bytes(nested_instance, spb):
		# Error should be set by the recursive call
		# Add context if the error message doesn't already mention the property/type
		if not has_error(): # Defensive check, error should already be set
			_set_error("Failed during recursive population for nested resource '%s' of type '%s'." % [prop_name, nested_class_name], spb.get_position())
		# Don't return the partially populated (or failed) instance
		return null

	# 6. Success: Instantiation and population complete
	return nested_instance
	
func _read_property_int(spb: StreamPeerBuffer, resource: Resource, prop: Dictionary) -> int:
	# Default integer type is i64 as per BSATN common usage for IDs/timestamps
	# Specific types (u8, i32, etc.) should be handled by "bsatn_type_" metadata.
	return read_i64_le(spb)

func _read_property_float(spb: StreamPeerBuffer, resource: Resource, prop: Dictionary) -> float:
	# Default float is f32. Use "bsatn_type_" = "f64" metadata if needed.
	# Check for f64 metadata (example, assumes read_f64_le exists if needed)
	# var meta_key = "bsatn_type_" + prop.name
	# if resource.has_meta(meta_key) and resource.get_meta(meta_key) == "f64":
	#     return read_f64_le(spb)
	return read_f32_le(spb)

func _read_property_string(spb: StreamPeerBuffer, resource: Resource, prop: Dictionary) -> String:
	return read_string_with_u32_len(spb)

func _read_property_bool(spb: StreamPeerBuffer, resource: Resource, prop: Dictionary) -> bool:
	return read_bool(spb)

func _read_property_vector3(spb: StreamPeerBuffer, resource: Resource, prop: Dictionary) -> Vector3:
	var x := read_f32_le(spb)
	var y := read_f32_le(spb)
	var z := read_f32_le(spb)
	return Vector3.ZERO if has_error() else Vector3(x, y, z)

func _read_property_vector2(spb: StreamPeerBuffer, resource: Resource, prop: Dictionary) -> Vector2:
	var x := read_f32_le(spb)
	var y := read_f32_le(spb)
	return Vector2.ZERO if has_error() else Vector2(x, y)

func _read_property_color(spb: StreamPeerBuffer, resource: Resource, prop: Dictionary) -> Color:
	var r := read_f32_le(spb)
	var g := read_f32_le(spb)
	var b := read_f32_le(spb)
	var a := read_f32_le(spb)
	return Color.BLACK if has_error() else Color(r, g, b, a)

func _read_property_array(spb: StreamPeerBuffer, resource: Resource, prop: Dictionary) -> Array:
	# Determine the element reader function based on hint_string or metadata
	var element_reader_func: Callable = _get_array_element_reader(resource, prop)

	if not element_reader_func.is_valid():
		# Error is set by _get_array_element_reader
		return [] # Return empty array on error

	# Read the vector using the determined element reader
	return read_vec(spb, element_reader_func)

# Helper to determine the correct reader function for array elements.
func _get_array_element_reader(resource: Resource, prop: Dictionary) -> Callable:
	var prop_name: StringName = prop.name
	var hint: int = prop.hint
	var hint_string: String = prop.hint_string # Format like "Type:TypeName" e.g., "2:int", "4:String", "19:Vector3"

	if hint != PROPERTY_HINT_TYPE_STRING or ":" not in hint_string:
		_set_error("Array property '%s' requires a typed hint (e.g., Array[String], Array[Vector3])." % prop_name, -1)
		return Callable()

	var hint_parts := hint_string.split(":", true, 1)
	if hint_parts.size() != 2:
		_set_error("Could not parse hint_string '%s' for array property '%s'" % [hint_string, prop_name], -1)
		return Callable()

	var element_type_code: int = int(hint_parts[0]) # Variant.Type enum value

	# Check for specific element type override first (e.g., for int/float subtypes)
	
	var element_meta_key := "bsatn_type_" + prop_name
	var specific_element_reader := _get_specific_bsatn_reader(resource, element_meta_key)
	if specific_element_reader.is_valid():
		return specific_element_reader

	# Fallback to reader based on the element's Variant.Type from hint_string
	match element_type_code:
		TYPE_STRING: return Callable(self, "_read_string_element")
		TYPE_INT:
			# Default to i64 if no specific metadata was provided
			push_warning("No 'bsatn_vec_element_type_%s' metadata found for Array[int]. Assuming element BSATN type 'i64'." % prop_name)
			return Callable(self, "_read_i64_element")
		TYPE_FLOAT:
			# Default to f32 if no specific metadata was provided
			# Add check for f64 metadata if implemented
			# if resource.has_meta(element_meta_key) and resource.get_meta(element_meta_key).to_lower() == "f64":
			#     # return Callable(self, "_read_f64_element") # If implemented
			#     _set_error("Array[float] with bsatn_type f64 not implemented yet for property '%s'." % prop_name, -1)
			#     return Callable()
			return Callable(self, "_read_f32_element")
		TYPE_BOOL: return Callable(self, "_read_bool_element")
		TYPE_VECTOR3: return Callable(self, "_read_vector3_element")
		TYPE_VECTOR2: return Callable(self, "_read_vector2_element")
		TYPE_COLOR: return Callable(self, "_read_color_element")
		TYPE_PACKED_BYTE_ARRAY:
			# Need metadata to distinguish Vec<Identity> from Vec<u8> etc.
			# Metadata check was already done via _get_specific_bsatn_reader
			_set_error("Unsupported element type 'PackedByteArray' for array '%s'. Specify element type (e.g., 'identity') via '%s' metadata." % [prop_name, element_meta_key], -1)
			return Callable()
		_:
			_set_error("Unsupported element type code '%d' in hint_string '%s' for array property '%s'" % [element_type_code, hint_string, prop_name], -1)
			return Callable()


# --- Helper Element Readers (for read_vec) ---
# Simple wrappers calling the main primitive readers.

func _read_vector3_element(spb: StreamPeerBuffer) -> Vector3: return _read_property_vector3(spb, null, {})
func _read_vector2_element(spb: StreamPeerBuffer) -> Vector2: return _read_property_vector2(spb, null, {})
func _read_color_element(spb: StreamPeerBuffer) -> Color: return _read_property_color(spb, null, {})
func _read_identity_element(spb: StreamPeerBuffer) -> PackedByteArray: return read_identity(spb)
func _read_connection_id_bytes(spb: StreamPeerBuffer) -> PackedByteArray:return read_bytes(spb, CONNECTION_ID_SIZE)
func _read_string_element(spb: StreamPeerBuffer) -> String: return read_string_with_u32_len(spb)
func _read_f32_element(spb: StreamPeerBuffer) -> float: return read_f32_le(spb)
func _read_f64_element(spb: StreamPeerBuffer) -> float: return read_f64_le(spb) 
func _read_bool_element(spb: StreamPeerBuffer) -> bool: return read_bool(spb)
func _read_i64_element(spb: StreamPeerBuffer) -> int: return read_i64_le(spb)
func _read_i32_element(spb: StreamPeerBuffer) -> int: return read_i32_le(spb)
func _read_u64_element(spb: StreamPeerBuffer) -> int: return read_u64_le(spb)

# --- Top-Level Message Parsing ---

# Entry point: Parses the entire byte buffer into a top-level message Resource.
func parse_packet(buffer: PackedByteArray) -> Resource:
	clear_error() # Ensure clean state for this parse attempt

	if buffer.is_empty():
		_set_error("Input buffer is empty", 0)
		return null

	var spb := StreamPeerBuffer.new()
	spb.data_array = buffer

	# 1. Read compression tag (currently only None is supported)
	var compression_tag := read_u8(spb)
	if has_error(): return null
	
	if compression_tag != COMPRESSION_NONE:
		# Handle or check for other compression types (Gzip, Brotli) if needed
		# spb = _decompress_stream(spb, compression_tag) # Hypothetical decompression
		# if has_error(): return null
		_set_error("Unsupported compression tag: 0x%02X" % compression_tag, 0)
		return null

	# 2. Read the ServerMessage enum tag (u8)
	var msg_type := read_u8(spb)
	if has_error(): return null

	# 3. Call the specific parser function based on the message type
	var result_resource: Resource = null
	#print(msg_type)
	match msg_type:
		SERVER_MSG_INITIAL_SUB: # 1
			result_resource = _read_initial_subscription_data(spb)
		SERVER_MSG_TRANSACTION_UPDATE: # 2
			result_resource = _read_transaction_update_data(spb)
		SERVER_MSG_IDENTITY_TOKEN: # 3
			result_resource = _read_identity_token_data(spb)
		SERVER_MSG_ONE_OFF_QUERY_RESPONSE: # 4
			result_resource = _read_one_off_query_response_data(spb) 
		SERVER_MSG_SUBSCRIBE_APPLIED: # 5
			result_resource = _read_subscribe_applied_data(spb) 
		SERVER_MSG_UNSUBSCRIBE_APPLIED: # 6
			result_resource = _read_unsubscribe_applied_data(spb) 
		SERVER_MSG_SUBSCRIPTION_ERROR: # 7
			result_resource = _read_subscription_error_data(spb)
			if result_resource.error_message:
				printerr(result_resource.error_message)
		SERVER_MSG_SUBSCRIBE_MULTI_APPLIED: # 8
			result_resource = _read_subscribe_multi_applied_data(spb)
		SERVER_MSG_UNSUBSCRIBE_MULTI_APPLIED: # 9
			result_resource = _read_unsubscribe_multi_applied_data(spb)
		_:
			_set_error("Unknown server message type: 0x%02X" % msg_type, 1)
			return null

	# Check for errors during the specific message parsing
	if has_error():
		return null # Error already set

	# Optional: Check if all bytes were consumed after parsing the message body
	var remaining_bytes := spb.get_size() - spb.get_position()
	if remaining_bytes > 0:
		# This might indicate a parsing error or extra data. Warning is appropriate.
		push_error("Bytes remaining after parsing message type 0x%02X: %d" % [msg_type, remaining_bytes])

	return result_resource

# --- Specific Message Data Readers ---
# These functions parse the data payload for specific ServerMessage types.
# They should return the corresponding Godot Resource (e.g., InitialSubscriptionData).

# Placeholder - Requires definition of OneOffQueryResponseData resource
func _read_one_off_query_response_data(spb: StreamPeerBuffer) -> Resource:
	_set_error("Reader for OneOffQueryResponse (0x04) not implemented.", spb.get_position() -1)
	return null

# Reads SubscribeApplied message data
func _read_subscribe_applied_data(spb: StreamPeerBuffer) -> SubscribeAppliedData:
	var resource := SubscribeAppliedData.new()
	resource.request_id = read_u32_le(spb)
	resource.total_host_execution_duration_micros = read_u64_le(spb)
	resource.query_id = _read_query_id_data(spb)
	resource.rows = _read_subscribe_rows_data(spb)
	return null if has_error() else resource

# Reads UnsubscribeApplied message data
func _read_unsubscribe_applied_data(spb: StreamPeerBuffer) -> UnsubscribeAppliedData:
	var resource := UnsubscribeAppliedData.new()
	resource.request_id = read_u32_le(spb)
	resource.total_host_execution_duration_micros = read_u64_le(spb)
	resource.query_id = _read_query_id_data(spb)
	resource.rows = _read_subscribe_rows_data(spb)
	return null if has_error() else resource

# Reads SubscriptionError message data
func _read_subscription_error_data(spb: StreamPeerBuffer) -> SubscriptionErrorData:
	var start_pos = spb.get_position()
	var dump = spb.data_array.duplicate().slice(start_pos) # DEBUG
	#print("  Data (hex): ", dump.hex_encode()) # DEBUG

	var resource := SubscriptionErrorData.new()

	# Read total_host_execution_duration_micros (u64)
	resource.total_host_execution_duration_micros = read_u64_le(spb)
	if has_error(): return null
	
	## FOR OPTION
	## 00 - SOME
	## 01 - NONE
	# Read Option<u32> request_id
	var req_id_tag = read_u8(spb); if has_error(): return null
	if req_id_tag == 0: resource.request_id = read_u32_le(spb)
	else: resource.request_id = -1
	if has_error(): return null
	#print("req_id_tag: ", req_id_tag, " ", resource.request_id)
	
	var query_id_tag = read_u8(spb); if has_error(): return null
	if query_id_tag == 0: resource.query_id = read_u32_le(spb)
	else: resource.query_id = -1
	if has_error(): return null
	#print("query_id_tag: ", query_id_tag, " ", resource.query_id)
	
	var table_id_tag = read_u8(spb); if has_error(): return null
	if table_id_tag == 0: # Some(TableId)
		resource.table_id_resource = _read_table_id_data(spb) 
		if has_error(): return null
	elif table_id_tag == 1: 
		resource.table_id_resource = null 
	else:
		_set_error("Invalid tag for Option<TableId>: %d" % table_id_tag, spb.get_position() - 1)
		return null
	#print("table_id_tag: ", table_id_tag, " ", resource.table_id_resource)
	#print("Readed: ", spb.data_array.duplicate().slice(start_pos, spb.get_position()).hex_encode())
	#print("Next: ", spb.data_array.duplicate().slice(spb.get_position(), spb.get_size()).hex_encode())
	resource.error_message = read_string_with_u32_len(spb)
	if has_error(): return null
	return resource

# Reads SubscribeMultiApplied message data
func _read_subscribe_multi_applied_data(spb: StreamPeerBuffer) -> SubscribeMultiAppliedData:
	var resource := SubscribeMultiAppliedData.new()
	resource.request_id = read_u32_le(spb)
	resource.total_host_execution_duration_micros = read_u64_le(spb)
	resource.query_id = _read_query_id_data(spb)
	resource.database_update = _read_database_update(spb)
	return null if has_error() else resource

# Reads UnsubscribeMultiApplied message data
func _read_unsubscribe_multi_applied_data(spb: StreamPeerBuffer) -> UnsubscribeMultiAppliedData:
	var resource := UnsubscribeMultiAppliedData.new()
	resource.request_id = read_u32_le(spb)
	resource.total_host_execution_duration_micros = read_u64_le(spb)
	resource.query_id = _read_query_id_data(spb)
	resource.database_update = _read_database_update(spb)
	return null if has_error() else resource

# Reads QueryId structure (inline)
func _read_query_id_data(spb: StreamPeerBuffer) -> QueryIdData:
	var resource := QueryIdData.new()
	resource.id = read_u32_le(spb) 
	return null if has_error() else resource

# Reads SubscribeRows structure (inline)
func _read_subscribe_rows_data(spb: StreamPeerBuffer) -> SubscribeRowsData:
	var resource := SubscribeRowsData.new()
	resource.table_id = read_u32_le(spb) # TableId = u32
	resource.table_name = read_string_with_u32_len(spb)
	resource.table_rows = _read_table_update(spb)
	return null if has_error() else resource

# Placeholder reader for OneOffTable (needed by _read_one_off_query_response_data)
func _read_one_off_table(spb: StreamPeerBuffer) -> Resource:
	_set_error("Reader for OneOffTable not implemented.", spb.get_position())
	return null

func _read_identity_token_data(spb: StreamPeerBuffer) -> IdentityTokenData:
	var resource := IdentityTokenData.new()
	resource.identity = read_identity(spb)
	resource.token = read_string_with_u32_len(spb)
	resource.connection_id = read_bytes(spb, CONNECTION_ID_SIZE)
	return null if has_error() else resource

func _read_initial_subscription_data(spb: StreamPeerBuffer) -> InitialSubscriptionData:
	var resource := InitialSubscriptionData.new()
	resource.database_update = _read_database_update(spb)
	resource.request_id = read_u32_le(spb)
	resource.total_host_execution_duration_ns = read_i64_le(spb)
	return null if has_error() else resource

func _read_transaction_update_data(spb: StreamPeerBuffer) -> TransactionUpdateData:
	var resource := TransactionUpdateData.new()
	resource.status = _read_update_status(spb)
	resource.timestamp_ns = read_timestamp(spb)
	resource.caller_identity = read_identity(spb)
	resource.caller_connection_id = read_bytes(spb, CONNECTION_ID_SIZE)
	resource.reducer_call = _read_reducer_call_info(spb)
	resource.energy_quanta_used = read_u64_le(spb)
	resource.total_host_execution_duration_ns = read_i64_le(spb)
	return null if has_error() else resource

# --- Sub-Structure Readers ---
# Readers for nested structures within messages.

func _read_table_id_data(spb: StreamPeerBuffer) -> TableIdData:
	var resource := TableIdData.new()
	# print("    Reading TableIdData at pos: ", spb.get_position()) # DEBUG
	resource.pascal_case = read_string_with_u32_len(spb)
	if has_error(): return null
	# print("      Read pascal_case, pos: ", spb.get_position()) # DEBUG
	resource.snake_case = read_string_with_u32_len(spb)
	if has_error(): return null
	# print("      Read snake_case, pos: ", spb.get_position()) # DEBUG
	return resource
	
func _read_update_status(spb: StreamPeerBuffer) -> UpdateStatusData:
	var resource := UpdateStatusData.new()
	var tag := read_u8(spb) # Enum tag
	if has_error(): return null

	match tag:
		0: # Committed(DatabaseUpdate<F>)
			resource.status_type = UpdateStatusData.StatusType.COMMITTED
			resource.committed_update = _read_database_update(spb)
		1: # Failed(Box<str>)
			resource.status_type = UpdateStatusData.StatusType.FAILED
			resource.failure_message = read_string_with_u32_len(spb)
		2: # OutOfEnergy
			resource.status_type = UpdateStatusData.StatusType.OUT_OF_ENERGY
		_:
			_set_error("Unknown UpdateStatus tag: %d" % tag, spb.get_position() - 1)
			return null

	return null if has_error() else resource

func _read_reducer_call_info(spb: StreamPeerBuffer) -> ReducerCallInfoData:
	var resource := ReducerCallInfoData.new()
	resource.reducer_name = read_string_with_u32_len(spb)
	resource.reducer_id = read_u32_le(spb)
	var args_len := read_u32_le(spb)
	resource.args = read_bytes(spb, args_len) # Args remain raw bytes
	resource.request_id = read_u32_le(spb)
	resource.execution_time = read_f64_le(spb) # Assuming execution time is f64
	return null if has_error() else resource

# Reads DatabaseUpdate structure (Vec<TableUpdate>).
func _read_database_update(spb: StreamPeerBuffer) -> DatabaseUpdateData:
	var resource := DatabaseUpdateData.new()
	# Use read_vec to read the array of TableUpdateData resources
	var table_updates_array: Array = read_vec(spb, Callable(self, "_read_table_update"))
	if has_error(): return null

	# Assign the read array to the typed array in the resource
	resource.tables.assign(table_updates_array)
	return resource

# Reads a single TableUpdate structure. Called by read_vec within _read_database_update.
func _read_table_update(spb: StreamPeerBuffer) -> TableUpdateData:
	var resource := TableUpdateData.new()
	resource.table_id = read_u32_le(spb)
	resource.table_name = read_string_with_u32_len(spb)
	resource.num_rows = read_u64_le(spb) # Total rows in table after update

	var updates_count := read_u32_le(spb) # Number of CompressableQueryUpdate blocks
	if has_error(): return null

	var all_parsed_deletes: Array[Resource] = []
	var all_parsed_inserts: Array[Resource] = []

	var table_name_lower := resource.table_name.to_lower()
	var row_schema_script: Script = _possible_row_schemas.get(table_name_lower)

	if not row_schema_script and updates_count > 0:
		push_warning("No row schema found for table '%s', cannot deserialize rows." % resource.table_name)

	for i in range(updates_count):
		if has_error(): break # Stop processing updates if an error occurred

		var update_start_pos := spb.get_position()
		var query_update_spb: StreamPeerBuffer = _get_query_update_stream(spb, resource.table_name)
		if has_error() or query_update_spb == null:
			if not has_error():
				_set_error("Failed to get query update stream for table '%s'." % resource.table_name, update_start_pos)
			break

		var raw_deletes := read_bsatn_row_list(query_update_spb)
		if has_error(): break
		var raw_inserts := read_bsatn_row_list(query_update_spb)
		if has_error(): break

		if query_update_spb != spb: # Check decompressed stream consumption
			if query_update_spb.get_position() < query_update_spb.get_size():
				push_error("Extra %d bytes remaining in decompressed QueryUpdate block for table '%s'" % \
						[query_update_spb.get_size() - query_update_spb.get_position(), resource.table_name])
			# temp_spb will be GC'd

		if row_schema_script:
			# Process deletes
			for raw_row_bytes in raw_deletes:
				var row_resource = row_schema_script.new()
				# Create a temporary SPB for the raw row data
				var row_spb := StreamPeerBuffer.new()
				row_spb.data_array = raw_row_bytes
				# Call populate with the temporary SPB
				if _populate_resource_from_bytes(row_resource, row_spb):
					# Check if all bytes for this row were consumed
					if row_spb.get_position() < row_spb.get_size():
						push_error("Extra %d bytes remaining after parsing delete row for table '%s'" % [row_spb.get_size() - row_spb.get_position(), resource.table_name])
						# Mark as error? Or just warn? For now, just warn and add anyway.
					all_parsed_deletes.append(row_resource)
				else:
					push_error("Stopping update processing for table '%s' due to delete row parsing failure." % resource.table_name)
					break # Break inner loop (deletes)
			if has_error(): break # Break outer loop (updates)

			# Process inserts
			for raw_row_bytes in raw_inserts:
				var row_resource = row_schema_script.new()
				# Create a temporary SPB for the raw row data
				var row_spb := StreamPeerBuffer.new()
				row_spb.data_array = raw_row_bytes
				# Call populate with the temporary SPB
				if _populate_resource_from_bytes(row_resource, row_spb):
					# Check if all bytes for this row were consumed
					if row_spb.get_position() < row_spb.get_size():
						push_error("Extra %d bytes remaining after parsing insert row for table '%s'" % [row_spb.get_size() - row_spb.get_position(), resource.table_name])
						# Mark as error? Or just warn? For now, just warn and add anyway.
					all_parsed_inserts.append(row_resource)
				else:
					push_error("Stopping update processing for table '%s' due to insert row parsing failure." % resource.table_name)
					break # Break inner loop (inserts)
			if has_error(): break # Break outer loop (updates)

	if has_error(): return null

	resource.deletes.assign(all_parsed_deletes)
	resource.inserts.assign(all_parsed_inserts)

	return resource

# Helper to handle potential compression of a QueryUpdate block.
# Returns a StreamPeerBuffer to read the QueryUpdate from (either original or decompressed).
# Sets error and returns null on failure.
func _get_query_update_stream(spb: StreamPeerBuffer, table_name_for_error: String) -> StreamPeerBuffer:
	var compression_tag_raw := read_u8(spb)
	if has_error(): return null

	match compression_tag_raw:
		COMPRESSION_NONE:
			return spb # Read directly from the original stream

		COMPRESSION_BROTLI, COMPRESSION_GZIP:
			var compression_type = DataDecompressor.CompressionType.BROTLI if \
					compression_tag_raw == COMPRESSION_BROTLI else DataDecompressor.CompressionType.GZIP
			var compression_name = "Brotli" if compression_type == DataDecompressor.CompressionType.BROTLI else "Gzip"

			var compressed_len := read_u32_le(spb)
			if has_error(): return null
			var compressed_data := read_bytes(spb, compressed_len)
			if has_error(): return null

			var decompressed_data := _decompressor.decompress(compressed_data, compression_type)

			if _decompressor.has_error() or decompressed_data == null:
				_set_error("Failed to decompress %s data for table '%s'. Cause: %s" % \
						[compression_name, table_name_for_error, _decompressor.get_last_error()], spb.get_position() - compressed_len - 4 - 1) # Approx position before block
				return null

			# Create a *new* StreamPeerBuffer with the decompressed data
			var temp_spb := StreamPeerBuffer.new()
			temp_spb.data_array = decompressed_data
			return temp_spb

		_:
			_set_error("Unknown QueryUpdate compression tag %d for table '%s'" % \
					[compression_tag_raw, table_name_for_error], spb.get_position() - 1)
			return null
