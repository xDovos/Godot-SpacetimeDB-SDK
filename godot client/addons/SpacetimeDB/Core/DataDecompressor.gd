class_name DataDecompressor extends RefCounted

static func decompress_packet(compressed_bytes: PackedByteArray) -> PackedByteArray:
	if compressed_bytes.is_empty():
		return PackedByteArray()

	var gzip_stream := StreamPeerGZIP.new()
	
	if gzip_stream.start_decompression() != OK:
		printerr("DataDecompressor Error: Failed to start Gzip decompression.")
		return []
		
	if gzip_stream.put_data(compressed_bytes) != OK:
		printerr("DataDecompressor Error: Failed to put data into Gzip stream.")
		return []
		
	var available_bytes = gzip_stream.get_available_bytes()
	if available_bytes == 0:
		var decompressed_data := PackedByteArray()
		var chunk_size := 4096

		while true:
			var result: Array = gzip_stream.get_partial_data(chunk_size)
			if result[0] == OK and not result[1].is_empty():
				decompressed_data.append_array(result[1])
			else:
				break
		return decompressed_data
	var result = gzip_stream.get_data(available_bytes)
	if result[0] != OK:
		printerr("DataDecompressor Error: Failed to get decompressed Gzip data.")
		return []
	return result[1]
