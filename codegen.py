import os
import re
import argparse
from enum import Enum

#region Colors
RED = '\033[31m'
PURPLE = '\033[35m'
BLUE = '\033[34m'
YELLOW = '\033[33m'
GREEN = '\033[32m'
RESET = '\033[0m'
#endregion

#region Option Handling
# This enum defines how to handle Rust Option<T> types in GDScript.
class RustOptionHandling(Enum):
    IGNORE = 1 #This will not generate any fields for Option<T> types.
    USE_GODOT_OPTION = 2 #https://github.com/WhoStoleMyCoffee/godot-optional/tree/main
    OPTION_T_AS_T = 3 #This will use Option<T> as T in GDScript. This may have issues with nullability in Godot, so use with caution.

OPTION_HANDLING = RustOptionHandling.OPTION_T_AS_T
#endregion

#region Type Maps
# This maps Rust types to GDScript types.
TYPE_MAP = {
    "Identity": "PackedByteArray",
    "String": "String",
    "bool": "bool",
    "f32": "float",
    "f64": "float",
    "u64": "int",
    "i64": "int",
    "u32": "int",
    "i32": "int",
    "u16": "int",
    "i16": "int",
    "Timestamp": "int",
    "Vector3":"Vector3",
    "Vector2":"Vector2"
}
META_TYPE_MAP = {
    "Timestamp": "i64",
    "u64": "u64",
    "i64": "i64",
    "u32": "u32",
    "i32": "i32",
    "f32": "f32",
    "f64": "f64",
    "u16": "u16",
    "i16": "i16",
    "Identity": "identity",
}
#endregion

#region Regex Patterns
SPACETIME_TYPE_REGEX = re.compile(r'#\[.*(SpacetimeType).*\]')
TABLE_REGEX = re.compile(r'#\[.*table\(.*name\s*=\s*(?P<name>\w+).*\)\]')
REDUCER_REGEX = re.compile(r'#\[reducer.*\]')
ENUM_DEF_REGEX = re.compile(r'enum\s+(?P<enum_name>\w+)\s*\{')
ENUM_FIELD_REGEX = re.compile(r'(?P<enum_field_name>\w+)\s*([(](?P<field_sub_class>\w+)[)],|[{](?P<field_sub_classes>[\w:\s,]+)[}],{0,1}){0,1}')
STRUCT_DEF_REGEX = re.compile(r'pub\s+struct\s+(?P<struct_name>\w+)\s*\{')
STRUCT_FIELD_REGEX = re.compile(r'^\s*(?P<field_name>\w+)\s*:\s*(?P<field_type>[\w:<>]+),?\s*$')
OPTION_REGEX = re.compile(r'Option<(?P<option_T>\w+)>')
PRIMARY_KEY_REGEX = re.compile(r'#\[primary_key(?:.*)?\]')
SERVER_ONLY_TAG = re.compile(r'\/\/[\s\S]*server_only')
#endregion


TARGET_GDSCRIPTS_DIR = "schema"
TABLES_DIR = os.path.join(TARGET_GDSCRIPTS_DIR, "tables")
TYPES_DIR = os.path.join(TARGET_GDSCRIPTS_DIR, "spacetime_types")

REDUCERS_LIST = []
TABLES_LIST = []
SPACETIME_TYPE_LIST = []
GENERATED_FILES = []

#region Print Functions
def print_debug(message):
    print(f"{PURPLE}Debug: {message}{RESET}")

def print_warning(message):
    print(f"{YELLOW}Warning: {message}{RESET}")

def print_error(message):
    print(f"{RED}Error: {message}{RESET}")

def print_info(message):
    print(f"{BLUE}Info: {message}{RESET}")
#endregion
def generate_directories():
    if not os.path.exists(TARGET_GDSCRIPTS_DIR):
        try:
            os.makedirs(TARGET_GDSCRIPTS_DIR)
        except Exception as e:
            print(f"Error creating directory '{TARGET_GDSCRIPTS_DIR}': {e}")
    if not os.path.exists(TABLES_DIR):
        try:
            os.makedirs(TABLES_DIR)
        except Exception as e:
            print(f"Error creating directory '{TABLES_DIR}': {e}")
    if not os.path.exists(TYPES_DIR):
        try:
            os.makedirs(TYPES_DIR)
        except Exception as e:
            print(f"Error creating directory '{TYPES_DIR}': {e}")

def parse_rust_struct(lines):
    field_is_primary = False 
    fields = []
    for i, line in enumerate(lines):
        line = line.strip()
        if not line or line.startswith("//") or SERVER_ONLY_TAG.search(line):
            continue
        if PRIMARY_KEY_REGEX.search(line):
            field_is_primary = True
        struct_match = STRUCT_DEF_REGEX.search(line)
        if struct_match:
            struct_name = struct_match.group('struct_name')            
            TYPE_MAP[struct_name] = struct_name
            fields.append({'struct_name': struct_name})
            continue
        field_match = STRUCT_FIELD_REGEX.match(line)
        if field_match:
            field_info = field_match.groupdict()
            option = OPTION_REGEX.search(field_info['field_type'])
            if option:
                field_info['field_type'] = TYPE_MAP.get(option.group('option_T'), 'Variant')
                field_info['is_optional'] = True
            if field_is_primary:
                field_info['is_primary'] = field_is_primary
            fields.append(field_info)
            field_is_primary = False
        elif line == "}":
            break
    return fields

def parse_rust_enum(lines):
    enum_name = None
    enum_values = []
    enum_field = ""
    enum_sub_classes = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        if enum_match := ENUM_DEF_REGEX.search(line):
            enum_name = enum_match.group('enum_name')
            TYPE_MAP[enum_name] = enum_name
            continue
        enum_field += line
        if "," in line and not ":" in line:
            field = ENUM_FIELD_REGEX.search(enum_field)
            if field:
                field_name = field.group('enum_field_name')
                field_sub_class = field.group('field_sub_class')
                field_sub_classes = field.group('field_sub_classes')
                enum_sub_classes.append(field_sub_class)                  
                if field_sub_class:
                    enum_values.append({'name': field_name, 'sub_class': field_sub_class})
                    # print_debug(f"Enum sub-class: {field_sub_class}")
                elif field_sub_classes:
                    sub_classes = [s.strip() for s in field_sub_classes.split(',') if s.strip()]
                    enum_values.append({'name': field_name, 'sub_classes': sub_classes})
                else:
                    enum_values.append({'name': field_name})
            enum_field = ""        
    if(len(enum_values) > 254):
        print_error(f"Enum {enum_name} has more than 254 values, which is not supported by SpacetimeDB.")
        exit(1)
    META_TYPE_MAP[enum_name] = "enum"
    return {'enum_name': enum_name, 'values': enum_values}


def generate_struct_gdscript(struct_name, fields):
    gd_fields = []
    meta_lines = []
    primary_key_field = None
    table_name = None
    for field in fields:
        if 'table_name' in field:
            table_name = field['table_name']
            meta_lines.insert(0, f'	set_meta("table_name", "{table_name}")')
            continue
        if 'struct_name' in field:
            continue
        rust_type = field['field_type']
        field_name = field['field_name']
        gd_type = TYPE_MAP.get(rust_type, 'Variant')

        if field.get('is_optional', False):
            if OPTION_HANDLING == RustOptionHandling.IGNORE:
                print_warning(f"Field '{field_name}' in table '{table_name}' is optional but will be ignored due to current OPTION_HANDLING setting.")
                continue
            elif OPTION_HANDLING == RustOptionHandling.USE_GODOT_OPTION:
                gd_type = f"Option"
            #OPTION_T_AS_T will use the type as is, no if check needed.

        gd_fields.append(f"@export var {field_name}: {gd_type}")

        if field.get('is_primary', False):
            if primary_key_field:
                 print_warning(f"Multiple #[primary_key] found for table {table_name}. The last one is used: {field_name}")
            primary_key_field = field_name

        if rust_type in META_TYPE_MAP:
            meta_lines.append(f'	set_meta("bsatn_type_{field_name}", "{META_TYPE_MAP[rust_type]}")')

    if primary_key_field:
        meta_lines.insert(0, f'	set_meta("primary_key", "{primary_key_field}")')
    elif table_name:
        print_warning(f"Primary key not found for table {table_name}")

    meta_block = "\n".join(meta_lines) if meta_lines else ""
    init_func = f"""
func _init():
{meta_block}
	pass"""
    if not meta_block:
        init_func = init_func.replace("\n\tpass","  pass")

    script_content = f"""#Do not edit this file, it is generated automatically.
class_name {struct_name} extends Resource

{ "\n".join(gd_fields) }
{init_func}
"""
    return script_content.strip() + "\n"

def generate_enum_gdscript(enum_name, enum_values):
    sub_classes = []    
    enum_values_block = "enum {\n"
    enum_func_parse = """static func parse(i: int) -> String:
\tmatch i:\n"""
    enum_func_string_parse = f"""static func from_string(s: String) -> {enum_name}:
\tmatch s:\n"""
    for i, value in enumerate(enum_values):
        sub_classes.append(value.get('sub_class', 'None'))
        enum_values_block += f"\t{value['name']},\n"
        enum_func_string_parse += f"\t\t\"{value['name']}\": return {enum_name}.{value['name']}\n"
        enum_func_parse += f"\t\t{i}: return \"{value['name']}\"\n"
    enum_values_block += "}"
    enum_func_parse += """\t\t_: 
\t\t\tprinterr("Enum does not have value for %d. This is out of bounds." % i)
\t\t\treturn "Unknown"
"""
    gd_enum_content = f"""#Do not edit this file, it is generated automatically.
class_name {enum_name} extends Resource\n
const enum_sub_classes: Array = [{", ".join(str(f'"{s}"') for s in sub_classes)}]
var value: int = {enum_values[0]['name']}
var data: Variant\n
{enum_values_block}\n
func _init():
\tset_meta("bsatn_type_value", "i64")
\tpass\n
{enum_func_parse}\n
static func create(type: int, _data: Variant = null) -> {enum_name}:
\tvar result = {enum_name}.new()
\tresult.value = type
\tresult.data = _data
\treturn result
"""
    return gd_enum_content

def generate_reducers():
    print("Generating reducers...")
    callback_string = "cb: Callable = func(_t: TransactionUpdateData): pass"
    gd_script_content = """#Do not edit this file, it is generated automatically.
class_name Reducers extends Resource
"""       
    for reducer in REDUCERS_LIST:
        params_str = ", ".join([f"{p['param_name']}: {TYPE_MAP.get(p['param_type'], 'Variant')}" for p in reducer['params']])
        params_str = ", ".join([params_str, callback_string]) if params_str else callback_string
        gd_script_content += f"""        
static func {reducer['function_name']}({params_str}) -> void:
    var id = SpacetimeDB.call_reducer("{reducer['function_name']}", [{', '.join([f'{p["param_name"]}' for p in reducer['params']])}], [{', '.join([f'"{META_TYPE_MAP.get(p["param_type"])}"' for p in reducer['params']])}])
    var result = await SpacetimeDB.wait_for_reducer_response(id)
    cb.call(result)
    pass
"""
    output_path = os.path.join(TARGET_GDSCRIPTS_DIR, "reducers.gd")
    GENERATED_FILES.append(output_path)
    try:
        with open(output_path, 'w', encoding='utf-8') as outfile:
            outfile.write(gd_script_content)
    except Exception as e:
        print(f"File write error {output_path}: {e}")
    pass

def generate_tables():
    print("Generating tables...")
    for table in TABLES_LIST:
        table_name = table['table_name']
        fields = table['fields']
        fields.append({"table_name": table_name})
        struct_name = None
        for field in fields:
            if 'struct_name' in field:
                struct_name = field['struct_name']
                break
        gd_script_content = generate_struct_gdscript(struct_name, fields)
        output_filename = f"{table_name}.gd"
        output_filepath = os.path.join(TARGET_GDSCRIPTS_DIR, "tables", output_filename)
        with open(output_filepath, 'w', encoding='utf-8') as f:
            f.write(gd_script_content)
        GENERATED_FILES.append(output_filepath)

def generate_spacetime_types():
    print("Generating spacetime types...")
    for spacetime_type in SPACETIME_TYPE_LIST:
        if 'struct_name' in spacetime_type:
            spacetime_type_name = spacetime_type['struct_name']
            fields = spacetime_type['fields']
            gd_script_content = generate_struct_gdscript(spacetime_type_name, fields)
            output_filename = f"{spacetime_type_name}.gd"
            output_filepath = os.path.join(TYPES_DIR, to_lower_snake_case(output_filename))
            with open(output_filepath, 'w', encoding='utf-8') as f:
                f.write(gd_script_content)
            GENERATED_FILES.append(output_filepath)        
        elif 'enum_name' in spacetime_type:
            spacetime_type_name = spacetime_type['enum_name']
            values = spacetime_type['values']
            gd_script_content = generate_enum_gdscript(spacetime_type_name, values)
            output_filename = f"{spacetime_type_name}.gd"
            output_filepath = os.path.join(TYPES_DIR, to_lower_snake_case(output_filename))
            with open(output_filepath, 'w', encoding='utf-8') as f:
                f.write(gd_script_content)
            GENERATED_FILES.append(output_filepath)

def process_file(filepath):
    generated_files = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        print_error(f"Error reading file {filepath}: {e}")
        return generated_files
    
    file_len = len(lines)
    if file_len == 0:
        print_warning(f"File {filepath} is empty.")
        return generated_files
    
    for i in range(0, file_len):
        line = lines[i].strip()
        if not line or line.startswith("//"):
            continue
        
        spacetime_type_match = SPACETIME_TYPE_REGEX.search(line)
        if spacetime_type_match:
            #Find the SpacetimeType definition
            struct_match = None
            enum_match = None
            while True:
                i += 1
                line = lines[i].strip()
                struct_match = STRUCT_DEF_REGEX.search(line)
                enum_match = ENUM_DEF_REGEX.search(line)
                if struct_match or enum_match or line == "}":
                    break

            if not struct_match and not enum_match:
                print_error(f"SpacetimeType found but no struct or enum definition on line {i + 1} in file {filepath}")
                continue
                    
            if struct_match:
                spacetime_type_name = struct_match.group('struct_name')
                struct_buffer = []
                while True:
                    line = lines[i].strip()
                    struct_buffer.append(line)
                    if line == "}": break
                    i += 1
                fields = parse_rust_struct(struct_buffer)
                if fields:
                    SPACETIME_TYPE_LIST.append({'struct_name': spacetime_type_name, 'fields': fields})
            elif enum_match:
                spacetime_type_name = enum_match.group('enum_name')
                enum_buffer = []
                while True:
                    line = lines[i].strip()
                    enum_buffer.append(line)
                    if line == "}": break
                    i += 1
                enum_data = parse_rust_enum(enum_buffer)
                if enum_data:
                    SPACETIME_TYPE_LIST.append({'enum_name': spacetime_type_name, 'values': enum_data['values']})
                print_info(f"Found SpacetimeType enum '{spacetime_type_name}' in file {filepath} at line {i + 1}")
            else:
                print_error(f"SpacetimeType found but no struct definition on line {i + 1} in file {filepath}")
                continue

        table_match = TABLE_REGEX.search(line)
        if table_match:
            table_name = table_match.group('name')
            struct_buffer = []
            while True:
                i += 1
                line = lines[i].strip()
                struct_buffer.append(line)
                if line == "}": break
            fields = parse_rust_struct(struct_buffer)
            if fields:
                TABLES_LIST.append({'table_name': table_name, 'fields': fields})

        reducer_match = REDUCER_REGEX.search(line)
        if reducer_match:            
            next_line_stripped = lines[i + 1].strip()
            start_of_params = next_line_stripped.find("(")
            end_of_params = next_line_stripped.find(")")
            function_name = next_line_stripped[7:start_of_params]
            params = next_line_stripped[start_of_params + 1:end_of_params]
            param_list_split = params.split(",")
            params_list = []
            for i, param in enumerate(param_list_split):
                p = param.split(":")
                if not "ReducerContext" in p[1]:
                    params_list.append({"param_name": p[0].strip(), "param_type": p[1].strip()})
            REDUCERS_LIST.append({
                "function_name": function_name,
                "params": params_list
            })

def proccess_all_files():
    for root, dirs, files in os.walk('.'):      
        dirs[:] = [d for d in dirs if d not in ['target', '.git', '.vscode', 'schema']]
        for file in files:
            if file.endswith('.rs'):
                process_file(os.path.join(root, file))            
    pass

def to_lower_snake_case(s):
    return re.sub(r'(?<!^)(?=[A-Z])', '_', s).lower()

if __name__ == "__main__":
    print_debug("Starting GDScript generation from Rust SpacetimeDB structures...")
    generate_directories()
    parser = argparse.ArgumentParser(description="Generates GDScript Resource files from Rust SpacetimeDB structures.")
    parser.add_argument(
        "search_dir",
        nargs='?',
        default="src",
        help="Directory for recursively searching for lib.rs files (default: current directory)."
    )
    args = parser.parse_args()

    start_dir = args.search_dir
    abs_start_dir = os.path.abspath(start_dir)

    if not os.path.isdir(abs_start_dir):
        print_error(f"The specified path is not a directory: {abs_start_dir}")
        exit(1)

    proccess_all_files()
    generate_tables()
    generate_spacetime_types()
    generate_reducers()

    if GENERATED_FILES: 
        print("Generated files:")
        for fname in GENERATED_FILES:
            print(f"- {fname}")
    print_info("GDScript generation completed.\nYou can now use the generated scripts in your Godot project under the 'schema' directory.")