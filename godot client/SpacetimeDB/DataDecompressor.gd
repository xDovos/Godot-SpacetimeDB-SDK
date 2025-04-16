# addons/spacetimedb_client/DataDecompressor.gd
class_name DataDecompressor extends RefCounted # RefCounted is fine, no node features needed

enum CompressionType {
	NONE,
	BROTLI,
	GZIP
}

var _last_error: String = ""

func has_error() -> bool:
	return _last_error != ""

func get_last_error() -> String:
	var err := _last_error
	_last_error = "" # Clear after get
	return err

func _set_error(msg: String):
	if _last_error == "": # Don't overwrite first error
		_last_error = "DataDecompressor Error: " + msg
		printerr(_last_error)

# Decompresses data based on the specified type.
# Returns decompressed PackedByteArray or null on error.
func decompress(compressed_bytes: PackedByteArray, type: CompressionType) -> PackedByteArray:
	_last_error = "" # Clear previous error

	if compressed_bytes.is_empty():
		# Decompressing empty array results in empty array
		return PackedByteArray()

	match type:
		CompressionType.NONE:
			# No decompression needed, return as is
			return compressed_bytes

		CompressionType.BROTLI:
			_set_error("Brotli decompression requires a native GDExtension/GDNative implementation.")

		CompressionType.GZIP:
			_set_error("GZIP decompression requires a native GDExtension/GDNative implementation.")
			return []
		_:
			_set_error("Unknown compression type requested: %d" % type)
			return []

	return []
