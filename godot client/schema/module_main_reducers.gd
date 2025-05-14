static func change_color_random(cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var _id: int = SpacetimeDB.call_reducer('main', 'change_color_random', [], [])
	var _result = await SpacetimeDB.wait_for_reducer_response(_id)
	cb.call(_result)

static func move_user(new_input: Vector2, global_position: Vector3, cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var _id: int = SpacetimeDB.call_reducer('main', 'move_user', [new_input, global_position], ['', ''])
	var _result = await SpacetimeDB.wait_for_reducer_response(_id)
	cb.call(_result)

static func save_my_bytes(bytes: Array[int], cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var _id: int = SpacetimeDB.call_reducer('main', 'save_my_bytes', [bytes], [&'u8'])
	var _result = await SpacetimeDB.wait_for_reducer_response(_id)
	cb.call(_result)

static func test_struct(message: MainMessage, another_message: MainMessage, cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var _id: int = SpacetimeDB.call_reducer('main', 'test_struct', [message, another_message], [&'MainMessage', &'MainMessage'])
	var _result = await SpacetimeDB.wait_for_reducer_response(_id)
	cb.call(_result)
