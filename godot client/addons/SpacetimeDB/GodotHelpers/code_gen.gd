@tool
extends Node

func _on_request_completed(json_string):
	var generated_code: Dictionary = parse_schema_to_gdscript(json_string)

	if generated_code.is_empty():
		print("Code generation failed or produced no scripts.")
	else:
		print("\n=====================================")
		print("Generated GDScript Code:")
		print("=====================================")
		for name_class in generated_code:
			print("\n# --- %s.gd ---" % name_class)
			print(generated_code[name_class])
			save_script(name_class, generated_code[name_class])
		print("\n=====================================")
		print("Code generation finished.")

func parse_schema_to_gdscript(json_string: String) -> Dictionary:
	var parse_result = JSON.parse_string(json_string)
	if parse_result == null:
		return {}

	var schema = parse_result as Dictionary

	if not schema.has("typespace") or not typeof(schema.typespace) == TYPE_DICTIONARY:
		printerr("Invalid schema: Root key 'typespace' not found or is not a Dictionary.")
		return {}
	if not schema.has("tables") or not typeof(schema.tables) == TYPE_ARRAY:
		printerr("Invalid schema: Root key 'tables' not found or is not an Array.")
		return {}
	if not schema.has("types") or not typeof(schema.types) == TYPE_ARRAY:
		printerr("Invalid schema: Root key 'types' (for named types) not found or is not an Array.")
		return {}

	var typespace = schema.typespace as Dictionary
	if not typespace.has("types") or not typeof(typespace.types) == TYPE_ARRAY:
		printerr("Invalid schema: Key 'types' (for structural types) not found inside 'typespace' or is not an Array.")
		return {}

	var structural_types: Array = typespace.types
	var tables: Array = schema.tables
	var named_types: Array = schema.types

	print("Schema structure validated. Found %d structural types, %d tables, %d named types." % [structural_types.size(), tables.size(), named_types.size()])

	return _build_scripts_from_parsed_data(structural_types, tables, named_types)

func _build_scripts_from_parsed_data(structural_types: Array, tables: Array, named_types: Array) -> Dictionary:
	var type_index_to_name_map := {}
	for named_type_info in named_types:
		var nt_dict = named_type_info as Dictionary
		if nt_dict and nt_dict.has("ty") and nt_dict.has("name"):
			var type_index: int = nt_dict.ty
			var type_name_data = nt_dict.name as Dictionary
			if type_name_data and type_name_data.has("name"):
				var name_class: String = type_name_data.name
				type_index_to_name_map[type_index] = name_class

	var type_index_to_table_info := {}
	for table_info in tables:
		var t_dict = table_info as Dictionary
		if t_dict and t_dict.has("product_type_ref") and t_dict.has("name") and t_dict.has("primary_key"):
			var type_ref: int = t_dict.product_type_ref
			var table_name: String = t_dict.name
			var pk_indices: Array = t_dict.primary_key
			type_index_to_table_info[type_ref] = {"name": table_name, "pk_indices": pk_indices}

	var generated_scripts := {}
	for named_type_info in named_types:
		var nt_dict = named_type_info as Dictionary
		if not nt_dict or not (nt_dict.has("ty") and nt_dict.has("name")):
			continue

		var type_index: int = nt_dict.ty
		var name_class: String = type_index_to_name_map.get(type_index, "UnknownType_%d" % type_index)

		if ClassDB.class_exists(name_class):
			print("Skipping generation for existing Godot class: %s" % name_class)
			continue

		if type_index < 0 or type_index >= structural_types.size():
			printerr("Type index %d for class %s is out of bounds for structural types." % [type_index, name_class])
			continue

		var structural_type_def = structural_types[type_index] as Dictionary
		if not structural_type_def or not structural_type_def.has("Product"):
			continue

		var product_def = structural_type_def.Product as Dictionary
		if not product_def or not product_def.has("elements"):
			printerr("Product definition for class %s (Index: %d) is missing 'elements'." % [name_class, type_index])
			continue

		var elements: Array = product_def.elements

		var gdscript_code := ""
		gdscript_code += "extends Resource\n"
		gdscript_code += "class_name %s\n\n" % name_class

		var field_lines := []
		var init_meta_lines := []
		var field_names := []

		for i in range(elements.size()):
			var element = elements[i] as Dictionary
			if not element or not (element.has("name") and element.has("algebraic_type")):
				printerr("Invalid element in class %s: Missing 'name' or 'algebraic_type'." % name_class)
				continue

			var name_data = element.name as Dictionary
			if not name_data or not name_data.has("some"):
				printerr("Invalid element name structure in class %s." % name_class)
				continue
			var field_name: String = name_data.some
			field_names.append(field_name)

			var algebraic_type = element.algebraic_type as Dictionary
			if not algebraic_type:
				printerr("Invalid algebraic_type structure for field %s in class %s." % [field_name, name_class])
				continue

			var gd_type: String = "Variant"
			var bsatn_type: String = ""
			var is_complex_ref = false

			if algebraic_type.has("U64"): gd_type = "int"; bsatn_type = "u64"
			elif algebraic_type.has("U32"): gd_type = "int"; bsatn_type = "u32"
			elif algebraic_type.has("U8"): gd_type = "int"; bsatn_type = "u8"
			elif algebraic_type.has("I64"): gd_type = "int"; bsatn_type = "i64"
			elif algebraic_type.has("F32"): gd_type = "float"; bsatn_type = "f32"
			elif algebraic_type.has("String"): gd_type = "String"
			elif algebraic_type.has("Bool"): gd_type = "bool"
			elif algebraic_type.has("Array"):
				var array_data = algebraic_type.Array as Dictionary
				if array_data:
					if array_data.has("U8"):
						gd_type = "PackedByteArray" if "bytes" in field_name.to_lower() else "Array[int]"
						bsatn_type = "u8"
					elif array_data.has("String"): gd_type = "Array[String]"
					else:
						printerr("Unsupported array element type in %s.%s: %s" % [name_class, field_name, array_data.keys()]); gd_type = "Array"
				else: gd_type = "Array"
			elif algebraic_type.has("Product"):
				var inner_product_def = algebraic_type.Product as Dictionary
				var product_elements = inner_product_def.get("elements", []) as Array if inner_product_def else []
				if product_elements.size() == 1:
					var inner_element = product_elements[0] as Dictionary
					var inner_name_data = inner_element.get("name", {}) as Dictionary
					var inner_alg_type = inner_element.get("algebraic_type", {}) as Dictionary
					if inner_name_data.get("some") == "__identity__" and inner_alg_type.has("U256"): gd_type = "PackedByteArray"; bsatn_type = "identity"
					elif inner_name_data.get("some") == "__timestamp_micros_since_unix_epoch__" and inner_alg_type.has("I64"): gd_type = "int"; bsatn_type = "i64"
					else: printerr("Unsupported inner Product in %s.%s." % [name_class, field_name])
				else: printerr("Unsupported Product structure in %s.%s." % [name_class, field_name])
			elif algebraic_type.has("Ref"):
				var ref_index: int = algebraic_type.Ref
				gd_type = type_index_to_name_map.get(ref_index, "UnknownRef_%d" % ref_index)
				is_complex_ref = true
				if field_name == "lobby_id": bsatn_type = "u64"; is_complex_ref = false
				elif field_name == "source" and name_class == "Damage": bsatn_type = "identity"; is_complex_ref = false
			else:
				printerr("Unsupported algebraic_type in %s.%s: %s" % [name_class, field_name, algebraic_type.keys()])

			field_lines.append("@export var %s: %s" % [field_name, gd_type])
			if not bsatn_type.is_empty() and not is_complex_ref:
				init_meta_lines.append("\tset_meta(\"bsatn_type_%s\", \"%s\")" % [field_name, bsatn_type])

		gdscript_code += "\n".join(field_lines) + "\n\n"

		if type_index_to_table_info.has(type_index):
			var table_data = type_index_to_table_info[type_index]
			var table_name = table_data.name
			var pk_indices = table_data.pk_indices
			var pk_field_names := []
			for pk_index in pk_indices:
				if pk_index >= 0 and pk_index < field_names.size():
					pk_field_names.append(field_names[pk_index])
				else:
					printerr("Primary key index %d out of bounds for class %s (table %s)." % [pk_index, name_class, table_name])

			if not pk_field_names.is_empty():
				if not init_meta_lines.is_empty():
					init_meta_lines.append("")
				init_meta_lines.append("\tset_meta(\"table_name\", \"%s\")" % table_name)
				init_meta_lines.append("\tset_meta(\"primary_key\", \"%s\")" % ",".join(pk_field_names))

		gdscript_code += "func _init():\n"
		if init_meta_lines.is_empty():
			gdscript_code += "\tpass\n"
		else:
			gdscript_code += "\n".join(init_meta_lines) + "\n"
			gdscript_code += "\tpass\n"

		generated_scripts[name_class] = gdscript_code

	return generated_scripts

func save_script(name_class: String, script_content: String, directory: String = "res://schema"):
	var file_path = "%s/%s.gd" % [directory, name_class]
	var dir_access = DirAccess.open("res://")
	if not dir_access.dir_exists(directory):
		var err = DirAccess.make_dir_recursive_absolute(directory)
		if err != OK:
			printerr("Failed to create directory '%s'. Error code: %s" % [directory, err])
			return

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(script_content)
		print("Saved script to: %s" % file_path)
	else:
		printerr("Failed to open file for saving %s.gd. Error code: %s" % [name_class, FileAccess.get_open_error()])
