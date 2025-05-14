static func change_color_random(cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var id: int = SpacetimeDB.call_reducer('change_color_random', [], [])
	var result = await SpacetimeDB.wait_for_reducer_response(id)
	cb.call(result)

static func move_user(new_input: Vector2, global_position: Vector3, cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var id: int = SpacetimeDB.call_reducer('move_user', [new_input, global_position], ['', ''])
	var result = await SpacetimeDB.wait_for_reducer_response(id)
	cb.call(result)

static func save_my_bytes(bytes: Array[int], cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var id: int = SpacetimeDB.call_reducer('save_my_bytes', [bytes], [&'u8'])
	var result = await SpacetimeDB.wait_for_reducer_response(id)
	cb.call(result)

static func test_struct(message: MainMessage, another_message: MainMessage, cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var id: int = SpacetimeDB.call_reducer('test_struct', [message, another_message], [&'MainMessage', &'MainMessage'])
	var result = await SpacetimeDB.wait_for_reducer_response(id)
	cb.call(result)