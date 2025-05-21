static func change_color_random(cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var __id__: int = SpacetimeDB.call_reducer('change_color_random', [], [])
	var __result__ = await SpacetimeDB.wait_for_reducer_response(__id__)
	cb.call(__result__)

static func move_user(new_input: Vector2, global_position: Vector3, cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var __id__: int = SpacetimeDB.call_reducer('move_user', [new_input, global_position], [&'Vector2', &'Vector3'])
	var __result__ = await SpacetimeDB.wait_for_reducer_response(__id__)
	cb.call(__result__)

static func save_my_bytes(bytes: Array[int], cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var __id__: int = SpacetimeDB.call_reducer('save_my_bytes', [bytes], [&'u8'])
	var __result__ = await SpacetimeDB.wait_for_reducer_response(__id__)
	cb.call(__result__)

static func test_option_single(option: Option, cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var __id__: int = SpacetimeDB.call_reducer('test_option_single', [option], [&'string'])
	var __result__ = await SpacetimeDB.wait_for_reducer_response(__id__)
	cb.call(__result__)

static func test_option_vec(option: Option, cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var __id__: int = SpacetimeDB.call_reducer('test_option_vec', [option], [&'vec_string'])
	var __result__ = await SpacetimeDB.wait_for_reducer_response(__id__)
	cb.call(__result__)

static func test_struct(message: MainMessage, cb: Callable = func(_t: TransactionUpdateData): pass) -> void:
	var __id__: int = SpacetimeDB.call_reducer('test_struct', [message], [&'MainMessage'])
	var __result__ = await SpacetimeDB.wait_for_reducer_response(__id__)
	cb.call(__result__)