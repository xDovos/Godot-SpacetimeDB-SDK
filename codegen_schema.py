from enum import Enum
import urllib.request
import json
import os
import re

class Time:
    Miliseconds = 1 / 1000
    Seconds = 1
    Minutes = 60
    Hours = 3600
    Days = 86400
    Weeks = 604800
    Years = 31536000

REQUESTS = urllib.request
SERVER_ADDRESS = "localhost"
PORT = 3000
MODULE = "test"
TIMEOUT = 5 * Time.Seconds
OUT_PATH = "schema"

TYPE_MAP = {
    "I8": "int",
    "I16": "int",
    "I32": "int",
    "I64": "int",
    "U8": "int",
    "U16": "int",
    "U32": "int",
    "U64": "int",
    "F32": "float",
    "F64": "float",
    "String": "String",
    "Vector3": "Vector3",
    "Vector2": "Vector2",
    "Bool": "bool",
    "__identity__": "PackedByteArray",
    "__timestamp_micros_since_unix_epoch__": "int",
}
META_TYPE_MAP = {
    "I8": "i8",
    "I16": "i16",
    "I32": "i32",
    "I64": "i64",
    "U8": "u8",
    "U16": "u16",
    "U32": "u32",
    "U64": "u64",
    "F32": "f32",
    "F64": "f64",
    "__identity__": "identity",
    "__timestamp_micros_since_unix_epoch__": "i64",
}

#region Option Handling
# This enum defines how to handle Rust Option<T> types in GDScript.
class RustOptionHandling(Enum):
    IGNORE = 1 #This will not generate any fields for Option<T> types.
    USE_GODOT_OPTION = 2 #https://github.com/WhoStoleMyCoffee/godot-optional/tree/main
    OPTION_T_AS_T = 3 #This will use Option<T> as T in GDScript. This may have issues with nullability in Godot, so use with caution.

OPTION_HANDLING = RustOptionHandling.OPTION_T_AS_T
#endregion

#region Colors
RED = '\033[31m'
PURPLE = '\033[35m'
BLUE = '\033[34m'
YELLOW = '\033[33m'
GREEN = '\033[32m'
RESET = '\033[0m'
#endregion

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

class Typespace:
    def __init__(self, typespace):
        self.types = dict(enumerate(typespace.get("types", [])))

def to_lower_snake_case(s):
    s = re.sub(r'[\s_-]+', '_', s)  # Replace underscores, hyphens, and spaces with underscores
    s = re.sub(r'([a-z])([A-Z])', r'\1_\2', s)  # Add underscore before uppercase letters
    return s.lower()  # Convert to lowercase

def to_pascal_case(s):
    s = re.sub(r'[\s_-]+', ' ', s)  # Replace underscores, hyphens, and spaces with a single space
    s = re.sub(r'([a-z])([A-Z])', r'\1 \2', s)  # Add space before uppercase letters
    return ''.join(word.capitalize() for word in s.split())  # Capitalize each word and join them

def get_schema(url):
    try:
        response = REQUESTS.urlopen(url, timeout=TIMEOUT).read()
        schema = json.loads(response.decode('utf-8'))
        return schema
    except Exception as e:
        print_error(f"Error fetching schema from {url}: {e}")
        return None
    
def parse_schema(schema):
    schema_tables = schema.get("tables", []) if schema else []
    print_debug(f"Found {len(schema_tables)} tables in the schema.")
    schema_reducers = schema.get("reducers", []) if schema else []
    print_debug(f"Found {len(schema_reducers)} reducers in the schema.")
    typespace = Typespace(schema.get("typespace", {}))
    schema_types = schema.get("types", []) if schema else []
    schema_types.sort(key=lambda x: int(x.get('ty')))
    types = [] * len(schema_types)

    #Create type tokens
    for type_info in schema_types:
        type_name = type_info.get('name', {}).get('name', None)
        type_data = {
            "name": type_name,
        }
        if TYPE_MAP.get(type_name, None) is not None:
            type_data["gd_native"] = True
        if type_name is None:
            print_error(f"Type name not found for {type_info}")
            exit(1)
        ty = int(type_info.get('ty', -1))
        if ty == -1:
            print_error(f"Type ID not found for {type_info}")
            exit(1)
            
        struct = typespace.types.get(ty).get('Product', None)
        enum = typespace.types.get(ty).get('Sum', None)
        if struct:
            elements = []
            for element in struct.get('elements', []):
                data = {
                    "name": element.get('name', {}).get('some', None),
                }
                field_type = element.get('algebraic_type', {})
                if field_type.get('Product', None) is not None:
                    field_type = field_type.get('Product', {}).get('elements', [])[0].get('name', {}).get('some', None)
                elif field_type.get('Array', None) is not None:
                    data["is_array"] = True
                    field_type = field_type.get('Array', {})
                    field_type = next(iter(field_type))
                elif field_type.get('Sum', None) is not None:
                    sum = field_type.get('Sum', {})
                    some = sum.get('variants', [])[0]
                    if is_sum_option(sum):
                        data['is_option'] = True                                        
                    field_type = some.get('algebraic_type', {})
                    field_type = next(iter(field_type))
                elif field_type.get('Ref', None) is not None:
                    field_type = schema_types[field_type.get('Ref', -1)].get('name', {}).get('name', None)
                else:
                    field_type = next(iter(field_type))
                data['type'] = field_type
                elements.append(data)
            TYPE_MAP[type_name] = type_name
            META_TYPE_MAP[type_name] = type_name
            type_data['struct'] = elements
            types.append(type_data)
        elif enum:
            elements = []
            for variant in enum.get('variants', []):
                data = {
                    "name": variant.get('name', {}).get('some', None),
                }
                variant_type = variant.get('algebraic_type', {})
                if variant_type.get('Product', None) is not None:
                    variant = variant_type.get('Product', {}).get('elements', [])
                    if len(variant) >= 1:
                        variant_type = variant[0].get('name', {}).get('some', None)
                    else:
                        variant_type = None
                elif variant_type.get('Array', None) is not None:
                    data["is_array"] = True
                    variant_type = variant_type.get('Array', {})
                    variant_type = next(iter(variant_type))
                elif variant_type.get('Sum', None) is not None:
                    sum = variant_type.get('Sum', {})
                    some = sum.get('variants', [])[0]
                    if is_sum_option(sum):
                        data['is_option'] = True                                        
                    variant_type = some.get('algebraic_type', {})
                    variant_type = next(iter(variant_type))
                elif variant_type.get('Ref', None) is not None:
                    variant_type = schema_types[variant_type.get('Ref', -1)].get('name', {}).get('name', None)
                else:
                    variant_type = next(iter(variant_type))
                if variant_type is not None:
                    data['type'] = variant_type
                elements.append(data)
            TYPE_MAP[type_name] = type_name
            META_TYPE_MAP[type_name] = 'enum'
            type_data['enum'] = elements
            types.append(type_data)

    #Set table info for types
    for table in schema_tables:
        table_name = table.get('name', None)
        ref = table.get('product_type_ref', None)
        if ref is None or table_name is None: continue
        table_type = types[ref]
        table_type['table_name'] = table_name
        primary_key = table.get('primary_key')
        if len(primary_key) == 1:
            table_type['primary_key'] = primary_key[0]
    
    reducers = []
    for reducer in schema_reducers:
        if reducer.get('lifecycle', {}).get('some', None) is not None: continue
        reducer_name = reducer.get('name', None)
        reducer_params = []
        for param in reducer.get('params', {}).get('elements', []):
            data = {
                "name": param.get('name', {}).get('some', None),
            }
            param_type = param.get('algebraic_type', {})
            if param_type.get('Product', None) is not None:
                param_type = param_type.get('Product', {}).get('elements', [])[0].get('name', {}).get('some', None)
            elif param_type.get('Array', None) is not None:
                param_type = param_type.get('Array', {})
                param_type = next(iter(param_type))
                data["is_array"] = True
            elif param_type.get('Ref', None) is not None:
                param_type = schema_types[param_type.get('Ref', -1)].get('name', {}).get('name', None)
            elif param_type.get('Sum', None) is not None:
                sum = param_type.get('Sum', {})
                some = sum.get('variants', [])[0]
                if is_sum_option(sum):
                    data['is_option'] = True                                        
                param_type = some.get('algebraic_type', {})
                param_type = next(iter(param_type))
            else:
                param_type = next(iter(param_type))
            data['type'] = param_type
            reducer_params.append(data)
        reducers.append({"name": reducer_name, "params": reducer_params})
    parsed_schema = {
        "types": types, 
        "tables": schema_tables, 
        "reducers": reducers,
        "type_map": TYPE_MAP,
        "meta_type_map": META_TYPE_MAP
    }
    return parsed_schema

def save_schema(schema):
    name = schema.get('module', None) 
    if schema and name:
        # Save the schema to a file
        with open(f"{name}_schema.json", "w") as f:
            json.dump(schema, f, indent=2)
        print_info(f"Schema saved to {name}_schema.json")
    else:
        print_error("Failed to retrieve schema.")

def is_sum_option(sum):
    variants = sum.get('variants', [])
    if len(variants) != 2:
        return False
    elif variants[0].get('name', {}).get('some', "") != "some":
        return False
    elif variants[1].get('name', {}).get('some', "") != "none":
        return False
    return True

def load_env():
    path = os.path.join(os.path.dirname(__file__), '.env.json')
    global SERVER_ADDRESS, PORT, MODULE
    if os.path.exists(path):
        try:
            with open(path, 'r') as f:
                file_obj = json.loads(f.read())
                for key, value in file_obj.items():
                    match key:
                        case 'SERVER_ADDRESS':
                            SERVER_ADDRESS = value
                        case 'PORT':
                            PORT = value
                        case 'MODULE':
                            MODULE = value
        except Exception as e:
            print_error(f"Failed to load environment variables: {e}")
    else:
        print_info(f"Environment file not found at {path}")

def generate_directories():
    out_path = os.path.join(os.path.dirname(__file__), OUT_PATH)
    if not os.path.exists(out_path):
        os.makedirs(out_path)
    tables_path = os.path.join(out_path, "tables")
    if not os.path.exists(tables_path):
        os.makedirs(tables_path)
    types_path = os.path.join(out_path, "spacetime_types")
    if not os.path.exists(types_path):
        os.makedirs(types_path)

def build_gdscript_from_schema(schema):
    for _type in schema.get("types", []):
        if _type.get("gd_native", False): continue
        print_debug(f"Generating GDScript for type: {_type.get('name')}")
        table = _type.get("table_name", None)
        struct = _type.get("struct", None)
        enum = _type.get("enum", None)
        if struct:
            folder_path = "spacetime_types"
            if table:
                folder_path = "tables"
            content = generate_struct_gdscript(_type)
            output_file_name = f"{to_lower_snake_case(_type.get('name'))}.gd"
            output_file_path = os.path.join(OUT_PATH, folder_path, output_file_name)
            try:
                with open(output_file_path, 'w', encoding='utf-8') as f:
                    f.write(content)
            except Exception as e:
                print_error(f"Failed to write to file {output_file_path}: {e}")
        elif enum:
            folder_path = "spacetime_types"
            content = generate_enum_gdscript(_type)
            output_file_name = f"{to_lower_snake_case(_type.get('name'))}.gd"
            output_file_path = os.path.join(OUT_PATH, folder_path, output_file_name)
            try:
                with open(output_file_path, 'w', encoding='utf-8') as f:
                    f.write(content)
            except Exception as e:
                print_error(f"Failed to write to file {output_file_path}: {e}")
    generate_reducers_gdscript(schema)

def generate_reducers_gdscript(schema):
    module_name = schema.get('module')
    print_debug(f"Generating GDScript for module: {module_name}")
    content = f"""#Do not edit this file, it is generated automatically.
class_name {to_pascal_case(module_name)}Reducer extends Resource\n\n"""
    
    for reducer in schema.get("reducers", []):
        # params_str = ", ".join([f"{p.get('name', None)}: {TYPE_MAP.get(p['type'], 'TypeError')}" for p in reducer['params']])
        params_str = ""
        for p in reducer.get('params', []):
            name = p.get('name', None)
            _type = TYPE_MAP.get(p.get('type', None), None)
            if p.get('is_array', False):
                _type = f"Array[{_type}]"
            params_str += f"{name}: {_type}, "
        if params_str == "":
            params_str = "cb: Callable = func(_t: TransactionUpdateData): pass"
        else:
            params_str += "cb: Callable = func(_t: TransactionUpdateData): pass"
        param_names = ", ".join([f"{p.get('name', None)}" for p in reducer['params']])
        param_types = ", ".join([f'"{META_TYPE_MAP.get(p['type'], "")}"' for p in reducer['params']])
        # param_types = param_types.replace('"None"', "null")
        reducer_name = reducer.get('name', None)
        content += f"""static func {reducer_name}({params_str}) -> void:
\tvar id = SpacetimeDB.call_reducer("{reducer_name}", [{param_names}], [{param_types}])
\tvar result = await SpacetimeDB.wait_for_reducer_response(id)
\tcb.call(result)\n
"""
    output_file_name = f"reducers_{module_name}.gd"
    output_file_path = os.path.join(OUT_PATH, output_file_name)
    try:
        with open(output_file_path, 'w', encoding='utf-8') as f:
            f.write(content)
    except Exception as e:
        print_error(f"Failed to write to file {output_file_path}: {e}")

def generate_enum_gdscript(enum_data):
    enum_name = enum_data.get('name', None)
    enum_values = enum_data.get('enum', [])
    default_value = enum_values[0].get('name', None)
    variant_types = "["
    enum_names = ""
    for value in enum_values:
        enum_names += f"""\t{value['name']},\n"""
        _type = META_TYPE_MAP.get(value.get('type', None), None)
        # if _type == "enum":
        #     _type = "enum_" + value.get('type', None)
        if value.get('is_array', False):
            variant_types += f""""vec_{_type}", """
        elif _type is None:
            variant_types += f'"", '
        else:
            variant_types += f""""{_type}", """
    variant_types = variant_types[:-2] + "]"
    enum_names = enum_names[:-2]

    
    gd_script_content = f"""#Do not edit this file, it is generated automatically.
class_name {enum_name} extends Resource

const enum_sub_classes: Array = {variant_types}
var value: int = {default_value}
var data: Variant

enum {{
{enum_names}
}}

static func parse(i: int) -> String:
\tmatch i:
"""
    for i, value in enumerate(enum_values):
        gd_script_content += f"""\t\t{i}: return \"{value.get('name', None)}\"\n"""
    gd_script_content += """\t\t_:
\t\t\tprinterr("Enum does not have value for %d. This is out of bounds." % i)
\t\t\treturn "Unknown"\n\n"""

    gd_script_content += f"""static func create(type: int, _data: Variant = null) -> {enum_name}:
\tvar result = {enum_name}.new()
\tresult.value = type
\tresult.data = _data
\treturn result\n\n"""
    
    for value in enum_values:
        value_name = value.get('name', None)
        value_type = TYPE_MAP.get(value.get('type', None), None)
        if value_type == None:
            gd_script_content += f"""static func create_{to_lower_snake_case(value_name)}() -> {enum_name}:
\treturn create({value_name})\n\n"""
            continue
        if value.get('is_array', False):
            value_type = f"Array[{value_type}]"
        gd_script_content += f"""static func create_{to_lower_snake_case(value_name)}(_data: {value_type}) -> {enum_name}:
\treturn create({value_name}, _data)\n\n"""

    return gd_script_content

def generate_struct_gdscript(struct_data):
    struct_name = struct_data.get('name', None)
    fields = struct_data.get('struct', [])
    meta_data = []
    table_name = struct_data.get('table_name', None)
    if table_name is not None:
        meta_data.append(f"""set_meta("table_name", "{table_name}")""")
        primary_key = struct_data.get('primary_key', None)
        if primary_key is not None and isinstance(primary_key, int):
            key_name = fields[primary_key].get('name', None)
            meta_data.append(f"""set_meta("primary_key", "{key_name}")""")
    gd_script_content = f"""#Do not edit this file, it is generated automatically.
class_name {struct_name} extends Resource\n\n"""
    class_fields = []
    for field in fields:
        name = field.get('name', None)
        field_type = TYPE_MAP.get(field.get('type', None))
        if field.get('is_array', False):
            field_type = f"Array[{field_type}]"
        if field.get('is_option', False):
            match OPTION_HANDLING:
                case RustOptionHandling.IGNORE:
                    print_warning(f"Field '{name}' is optional but will be ignored due to current OPTION_HANDLING setting.")
                    continue
                case RustOptionHandling.USE_GODOT_OPTION:
                    field_type = f"Option"
        meta = META_TYPE_MAP.get(field.get('type', None))
        if meta is not None:
            meta_data.append(f"""set_meta("bsatn_type_{name}", "{meta}")""")
        gd_script_content += f"@export var {name}: {field_type}\n"
        class_fields.append(f"{name}: {field_type}")
    gd_script_content += "\nfunc _init():\n"
    for data in meta_data:
        gd_script_content += f"\t{data}\n"
    gd_script_content += "\tpass\n\n"
    gd_script_content += f"""static func create({', '.join("_" + c for c in class_fields)}) -> {struct_name}:
\tvar result = {struct_name}.new()"""
    for field in fields:
        name = field.get('name', None)
        gd_script_content += f"""\n\tresult.{name} = _{name}"""
    gd_script_content += "\n\treturn result\n\n"
    return gd_script_content

def generate_main_reducer():
    content = f"""#Do not edit this file, it is generated automatically.
class_name Reducers extends Resource\n\n"""
    for module in MODULE:
        content += f"""const {to_pascal_case(module)} = preload("res://{OUT_PATH}/reducers_{module}.gd")\n"""
    try:
        with open(os.path.join(OUT_PATH, "reducers.gd"), 'w', encoding='utf-8') as f:
            f.write(content)
    except Exception as e:
        print_error(f"Failed to write to file {os.path.join(OUT_PATH, 'reducers.gd')}: {e}")

def main():
    load_env()
    generate_directories()
    global MODULE
    if not isinstance(MODULE, list): MODULE = [MODULE]
    for mod in MODULE:
        url = f"http://{SERVER_ADDRESS}:{PORT}/v1/database/{mod}/schema?version=9"
        print_debug(f"Getting schema from {url}")
        download_schema = get_schema(url)
        if download_schema is None:
            print_error("Failed to retrieve schema.\nExiting...")
            exit(1)
        schema = parse_schema(download_schema)
        schema["module"] = mod
        save_schema(schema)
        build_gdscript_from_schema(schema)
    generate_main_reducer()

if __name__ == "__main__": main()