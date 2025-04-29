class_name BSATNSerializer extends RefCounted

# --- Constants ---
const IDENTITY_SIZE := 32
const CONNECTION_ID_SIZE := 16

# Client Message Variant Tags (ensure these match server/protocol)
const CLIENT_MSG_VARIANT_TAG_CALL_REDUCER    := 0x00
const CLIENT_MSG_VARIANT_TAG_SUBSCRIBE       := 0x01 # Legacy? Verify usage.
const CLIENT_MSG_VARIANT_TAG_ONEOFF_QUERY    := 0x02
const CLIENT_MSG_VARIANT_TAG_SUBSCRIBE_SINGLE := 0x03
const CLIENT_MSG_VARIANT_TAG_SUBSCRIBE_MULTI  := 0x04
const CLIENT_MSG_VARIANT_TAG_UNSUBSCRIBE     := 0x05 # Single? Verify usage.
const CLIENT_MSG_VARIANT_TAG_UNSUBSCRIBE_MULTI := 0x06

# --- Properties ---
var _last_error: String = ""
var _spb: StreamPeerBuffer # Internal buffer used by writing functions

# --- Initialization ---
func _init() -> void:
	_spb = StreamPeerBuffer.new()
	_spb.big_endian = false # Default to Little-Endian

# --- Error Handling ---
func has_error() -> bool: return _last_error != ""
func get_last_error() -> String: var e = _last_error; _last_error = ""; return e
func clear_error() -> void: _last_error = ""
# Sets the error message if not already set. Internal use.
func _set_error(msg: String) -> void:
	if _last_error == "": # Prevent overwriting
		_last_error = "BSATNSerializer Error: %s" % msg
		printerr(_last_error)

# --- Primitive Value Writers ---
# These directly write basic types to the *current* _spb

func write_i8(v: int) -> void:
	if v < -128 or v > 127: _set_error("Value %d out of range for i8" % v); v = 0
	_spb.put_u8(v if v >= 0 else v + 256)

func write_i16_le(v: int) -> void:
	if v < -32768 or v > 32767: _set_error("Value %d out of range for i16" % v); v = 0
	_spb.put_u16(v if v >= 0 else v + 65536)

func write_i32_le(v: int) -> void:
	if v < -2147483648 or v > 2147483647: _set_error("Value %d out of range for i32" % v); v = 0
	_spb.put_u32(v) # put_u32 handles negative i32 correctly

func write_i64_le(v: int) -> void:
	_spb.put_u64(v) # put_u64 handles negative i64 correctly

func write_u8(v: int) -> void:
	if v < 0 or v > 255: _set_error("Value %d out of range for u8" % v); v = 0
	_spb.put_u8(v)

func write_u16_le(v: int) -> void:
	if v < 0 or v > 65535: _set_error("Value %d out of range for u16" % v); v = 0
	_spb.put_u16(v)

func write_u32_le(v: int) -> void:
	if v < 0 or v > 4294967295: _set_error("Value %d out of range for u32" % v); v = 0
	_spb.put_u32(v)

func write_u64_le(v: int) -> void:
	if v < 0: _set_error("Value %d out of range for u64" % v); v = 0
	_spb.put_u64(v)

func write_f32_le(v: float) -> void:
	_spb.put_float(v)

func write_f64_le(v: float) -> void:
	_spb.put_double(v)

func write_bool(v: bool) -> void:
	_spb.put_u8(1 if v else 0)

func write_bytes(v: PackedByteArray) -> void:
	if v == null: v = PackedByteArray() # Avoid error on null
	var result = _spb.put_data(v)
	if result != OK: _set_error("StreamPeerBuffer.put_data failed with code %d" % result)

func write_string_with_u32_len(v: String) -> void:
	if v == null: v = ""
	var str_bytes := v.to_utf8_buffer()
	write_u32_le(str_bytes.size())
	if str_bytes.size() > 0: write_bytes(str_bytes)

func write_identity(v: PackedByteArray) -> void:
	if v == null or v.size() != IDENTITY_SIZE:
		_set_error("Invalid Identity value (null or size != %d)" % IDENTITY_SIZE)
		var default_bytes = PackedByteArray(); default_bytes.resize(IDENTITY_SIZE)
		write_bytes(default_bytes)
		return
	write_bytes(v)

func write_connection_id(v: PackedByteArray) -> void:
	if v == null or v.size() != CONNECTION_ID_SIZE:
		_set_error("Invalid ConnectionId value (null or size != %d)" % CONNECTION_ID_SIZE)
		var default_bytes = PackedByteArray(); default_bytes.resize(CONNECTION_ID_SIZE)
		write_bytes(default_bytes)
		return
	write_bytes(v)

func write_timestamp(v: int) -> void:
	write_i64_le(v)

func write_vector3(v: Vector3) -> void:
	if v == null: v = Vector3.ZERO
	write_f32_le(v.x); write_f32_le(v.y); write_f32_le(v.z)

func write_vector2(v: Vector2) -> void:
	if v == null: v = Vector2.ZERO
	write_f32_le(v.x); write_f32_le(v.y)

func write_color(v: Color) -> void:
	if v == null: v = Color.BLACK
	write_f32_le(v.r); write_f32_le(v.g); write_f32_le(v.b); write_f32_le(v.a)

func write_quaternion(v: Quaternion) -> void:
	if v == null: v = Quaternion.IDENTITY
	write_f32_le(v.x); write_f32_le(v.y); write_f32_le(v.z); write_f32_le(v.w)

# Writes a PackedByteArray prefixed with its u32 length (Vec<u8> format)
func write_vec_u8(v: PackedByteArray) -> void:
	if v == null: v = PackedByteArray()
	write_u32_le(v.size())
	write_bytes(v)

# --- Core Serialization Logic ---

# Helper to get the specific BSATN writer METHOD NAME based on metadata value.
# Returns StringName or &"" if not found/applicable.
func _get_specific_writer_method_name(bsatn_type_value) -> StringName:
	if bsatn_type_value == null: return &""
	var bsatn_type_str := str(bsatn_type_value).to_lower() # Ensure string and lower case
	match bsatn_type_str:
		"u64": return &"write_u64_le"
		"i64": return &"write_i64_le"
		"u32": return &"write_u32_le"
		"i32": return &"write_i32_le"
		"u16": return &"write_u16_le"
		"i16": return &"write_i16_le"
		"u8": return &"write_u8"
		"i8": return &"write_i8"
		"identity": return &"write_identity"
		"connection_id": return &"write_connection_id"
		"timestamp": return &"write_timestamp"
		"f64": return &"write_f64_le"
		"f32": return &"write_f32_le" # Explicit f32
		"vec_u8": return &"write_vec_u8" # Explicit Vec<u8>
		# Add other specific types if needed
		_: return &"" # Unknown type

# The central function to write any value to the *current* _spb.
# Handles basic types, resources, arrays (recursively), using metadata if available.
# Returns true on success, false on failure.
# - value: The value to write.
# - value_variant_type: The Godot Variant.Type of the value.
# - specific_writer_override: (Optional) Method name from metadata to use instead of default.
# - element_variant_type: (Optional) For arrays, the Variant.Type of elements.
# - element_class_name: (Optional) For arrays of objects, the element class name.
func _write_value(value, value_variant_type: Variant.Type, specific_writer_override: StringName = &"", \
				  element_variant_type: Variant.Type = TYPE_MAX, \
				  element_class_name: StringName = &"" \
				 ) -> bool:

	# 1. Use specific writer method if provided (highest priority)
	if specific_writer_override != &"" and value_variant_type != TYPE_ARRAY:
		if has_method(specific_writer_override):
			call(specific_writer_override, value)
		else:
			_set_error("Internal error: Specific writer method '%s' not found." % specific_writer_override)
			return false
	else:
		# 2. If no specific writer, use default based on Variant.Type
		match value_variant_type:
			TYPE_NIL: _set_error("Cannot serialize null value."); return false
			TYPE_BOOL: write_bool(value)
			TYPE_INT: write_i64_le(value)  # Default int is i64
			TYPE_FLOAT: write_f32_le(value) # Default float is f32
			TYPE_STRING: write_string_with_u32_len(value)
			TYPE_VECTOR2: write_vector2(value)
			TYPE_VECTOR3: write_vector3(value)
			TYPE_COLOR: write_color(value)
			TYPE_QUATERNION: write_quaternion(value)
			TYPE_PACKED_BYTE_ARRAY: write_vec_u8(value) # Default PBA is Vec<u8>
			TYPE_ARRAY:
				# Handle Arrays: write length, then write each element recursively
				if value == null: value = [] # Treat null array as empty
				if not value is Array: _set_error("Value is not an Array but type is TYPE_ARRAY"); return false
				if element_variant_type == TYPE_MAX: _set_error("Cannot serialize array without element type info"); return false

				write_u32_le(value.size()) # Write array length

				for element in value:
					if has_error(): return false # Stop early
					# Recursively call _write_value for the element.
					# Pass element's type info. The specific_writer_override for the *element*
					# (derived from the array's bsatn_type metadata) is passed here.
					# Note: specific_writer_override here comes from the *array's* metadata, it applies to elements.
					if not _write_value(element, element_variant_type, specific_writer_override, TYPE_MAX, element_class_name):
						_set_error("Failed to write array element.") # Add context?
						return false
			TYPE_OBJECT:
				if value is Resource:
					# Serialize nested resource fields *inline* (no length prefix)
					if not _serialize_resource_fields(value): # Recursive call
						# Error should be set by _serialize_resource_fields
						return false
				else:
					_set_error("Cannot serialize non-Resource Object value."); return false
			_:
				_set_error("Unsupported default value type '%s'." % type_string(value_variant_type)); return false

	# 3. Check for errors after writing attempt
	return not has_error()


# Serializes the fields of a Resource instance into the *current* _spb.
# Internal use. Returns true on success, false on failure.
func _serialize_resource_fields(resource: Resource) -> bool:
	if not resource or not resource.get_script():
		_set_error("Cannot serialize fields of null or scriptless resource"); return false

	var properties: Array = resource.get_script().get_script_property_list()
	for prop in properties:
		if not (prop.usage & PROPERTY_USAGE_STORAGE): continue

		var prop_name: StringName = prop.name
		var prop_type: Variant.Type = prop.type
		var value = resource.get(prop_name)
		var specific_writer_method: StringName = &""
		var element_type: Variant.Type = TYPE_MAX
		var element_class: StringName = &""

		# Determine specific writer or element type info
		var meta_key := "bsatn_type_" + prop_name
		if resource.has_meta(meta_key):
			# This metadata applies to the field itself, or the *elements* if it's an array.
			specific_writer_method = _get_specific_writer_method_name(resource.get_meta(meta_key))

		# If it's an array, get element type info from hint string
		if prop_type == TYPE_ARRAY:
			if prop.hint == PROPERTY_HINT_TYPE_STRING and ":" in prop.hint_string:
				var hint_parts = prop.hint_string.split(":", true, 1)
				if hint_parts.size() == 2:
					element_type = int(hint_parts[0])
					if element_type == TYPE_OBJECT: element_class = hint_parts[1] # Get class name hint
				else:
					_set_error("Array property '%s': Bad hint_string '%s'." % [prop_name, prop.hint_string]); return false
			else:
				_set_error("Array property '%s' needs typed hint." % prop_name); return false

			# For arrays, pass the specific_writer_method (from bsatn_type_*)
			# as the override for the ELEMENTS.
			if not _write_value(value, TYPE_ARRAY, specific_writer_method, element_type, element_class):
				if not has_error(): _set_error("Failed writing array property '%s'" % prop_name) # Ensure error is set
				return false
		else:
			# For non-arrays, pass the specific_writer_method for the value itself.
			if not _write_value(value, prop_type, specific_writer_method):
				if not has_error(): _set_error("Failed writing property '%s'" % prop_name) # Ensure error is set
				return false

	return true # All fields serialized successfully


# --- Argument Serialization Helpers ---

# Serializes an array of arguments into a single PackedByteArray block.
# Used by functions preparing calls like CallReducer.
# Returns the bytes, or empty PackedByteArray on error (and sets error).
func _serialize_arguments(args_array: Array, rust_types: Array = []) -> PackedByteArray:
	var args_spb := StreamPeerBuffer.new(); args_spb.big_endian = false
	var original_main_spb := _spb; _spb = args_spb # Redirect writes to temp buffer

	for i in range(args_array.size()):
		var arg_value = args_array[i]
		# For arguments, we only know the Variant type, no metadata.
		# Pass null resource/prop context to _write_value.
		# Need a way to call _write_value without prop/resource or a dedicated arg writer.
		# Using a dedicated argument writer is cleaner.
		
		var rust_type = ""
		if i < rust_types.size():
			rust_type = rust_types[i]
			
		if not _write_argument_value(arg_value, rust_type):
			push_error("Failed to serialize argument %d." % i)
			_spb = original_main_spb # Restore _spb before returning
			return PackedByteArray()

	_spb = original_main_spb # Restore _spb
	return args_spb.data_array if not has_error() else PackedByteArray()


# Helper to write a single *argument* value to the *current* _spb.
# Handles nested Resources *inline*. Does not use metadata.
func _write_argument_value(value, rust_type: String = "") -> bool:
	var value_type := typeof(value)

	match value_type:
		TYPE_NIL: _set_error("Cannot serialize null argument."); return false
		TYPE_BOOL: write_bool(value)
		TYPE_INT: 
			match rust_type:
				"u8": write_u8(value)
				"u16": write_u16_le(value)
				"u32": write_u32_le(value)
				"u64": write_u64_le(value)
				"i8": write_i8(value)
				"i16": write_i16_le(value)
				"i32": write_i32_le(value)
				_: write_i64_le(value) #Default i64
		TYPE_FLOAT: 
			match rust_type:
				"f64": write_f64_le(value)
				_: write_f32_le(value) # Default f32 for args
		TYPE_STRING: write_string_with_u32_len(value)
		TYPE_VECTOR2: write_vector2(value)
		TYPE_VECTOR3: write_vector3(value)
		TYPE_COLOR: write_color(value)
		TYPE_QUATERNION: write_quaternion(value)
		TYPE_PACKED_BYTE_ARRAY: write_vec_u8(value) # Default Vec<u8> for args
		TYPE_ARRAY: _set_error("Cannot serialize Array as direct argument."); return false
		TYPE_OBJECT:
			if rust_type == "enum":
				write_i64_le(value.value)
			elif value is Resource:
				# Serialize resource fields directly into the current stream (inline)
				if not _serialize_resource_fields(value):
					# Error should be set by _serialize_resource_fields
					if not has_error(): _set_error("Failed to serialize nested Resource argument.")
					return false
			else:
				_set_error("Cannot serialize non-Resource Object argument."); return false
		_:
			_set_error("Unsupported argument type: %s" % type_string(value_type)); return false

	return not has_error()


# Helper to serialize a single Resource argument into raw bytes block (for call_reducer_struct).
func _serialize_resource_argument(resource_arg: Resource) -> PackedByteArray:
	if not resource_arg: _set_error("Cannot serialize null resource argument."); return PackedByteArray()
	var arg_spb := StreamPeerBuffer.new(); arg_spb.big_endian = false
	var original_main_spb := _spb; _spb = arg_spb # Redirect writes

	# Write the resource fields inline into the temp buffer
	if not _serialize_resource_fields(resource_arg):
		push_error("Failed to serialize resource argument fields.")
		_spb = original_main_spb # Restore _spb
		return PackedByteArray()

	_spb = original_main_spb # Restore _spb
	return arg_spb.data_array if not has_error() else PackedByteArray()


# --- Public API ---

# Serializes a complete ClientMessage (variant tag + payload resource).
func serialize_client_message(variant_tag: int, payload_resource: Resource) -> PackedByteArray:
	clear_error(); _spb.data_array = PackedByteArray(); _spb.seek(0) # Reset state

	# 1. Write the message variant tag
	write_u8(variant_tag)
	if has_error(): return PackedByteArray()

	# 2. Serialize payload resource fields inline after the tag
	if not _serialize_resource_fields(payload_resource):
		if not has_error(): _set_error("Failed to serialize payload resource for tag %d" % variant_tag)
		return PackedByteArray()

	return _spb.data_array if not has_error() else PackedByteArray()
