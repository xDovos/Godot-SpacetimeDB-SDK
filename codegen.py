import os
import re
import argparse

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
    "Timestamp": "int",
}
META_TYPE_MAP = {
    "Timestamp": "i64",
    "u64": "u64",
    "i64": "i64",
}
TABLE_REGEX = re.compile(r'#\[table\(name\s*=\s*(?P<name>\w+)(?:,\s*public)?\)\]')
STRUCT_START_REGEX = re.compile(r'pub\s+struct\s+(?P<struct_name>\w+)\s*\{')
FIELD_REGEX = re.compile(r'^\s*(?P<field_name>\w+)\s*:\s*(?P<field_type>[\w:]+),?\s*$')
PRIMARY_KEY_REGEX = re.compile(r'#\[primary_key(?:.*)?\]')

# --- Функции ---

def parse_rust_struct(lines):
    field_is_primary = False 
    fields = []
    for i, line in enumerate(lines):
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        if PRIMARY_KEY_REGEX.search(line):
            field_is_primary = True
        field_match = FIELD_REGEX.match(line)
        if field_match:
            field_info = field_match.groupdict()
            field_name = field_info['field_name']
            field_type = field_info['field_type']
            field_info['is_primary'] = field_is_primary
            fields.append(field_info)
            if field_is_primary:
                 field_is_primary = False
        elif line == "}":
            break
            pass
    return fields


def generate_gdscript(table_name, fields):
    gd_fields = []
    meta_lines = [f'	set_meta("table_name", "{table_name}")']
    primary_key_field = None

    for field in fields:
        rust_type = field['field_type']
        field_name = field['field_name']
        gd_type = TYPE_MAP.get(rust_type, 'Variant')

        gd_fields.append(f"@export var {field_name}: {gd_type}")

        if field.get('is_primary', False):
            if primary_key_field:
                 print(f"Предупреждение: Найдено несколько #[primary_key] для таблицы {table_name}. Используется последний: {field_name}")
            primary_key_field = field_name

        if rust_type in META_TYPE_MAP:
            meta_lines.append(f'	set_meta("bsatn_type_{field_name}", "{META_TYPE_MAP[rust_type]}")')

    if primary_key_field:
        meta_lines.insert(1, f'	set_meta("primary_key", "{primary_key_field}")')
    else:
        print(f"Предупреждение: Primary key не найден для таблицы {table_name}") 

    meta_block = "\n".join(meta_lines) if meta_lines else ""
    init_func = f"""
func _init():
{meta_block}
	pass"""
    if not meta_block:
        init_func = init_func.replace("\n\tpass","pass")

    script_content = f"""extends Resource
class_name {table_name.capitalize()}

{ "\n".join(gd_fields) }
{init_func}
"""
    return script_content.strip() + "\n"


def process_file(filepath):
    """
    Обрабатывает один файл lib.rs.
    """
    print(f"--- Обработка файла: {filepath} ---")
    generated_files = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        print(f"Файл {filepath} успешно прочитан, строк: {len(lines)}")
    except Exception as e:
        print(f"Ошибка чтения файла {filepath}: {e}")
        return generated_files

    current_table_name = None
    current_struct_name = None
    struct_lines_buffer = []
    in_struct = False

    for i, line in enumerate(lines):
        line_stripped = line.strip()

        if in_struct:
            struct_lines_buffer.append(line)
            if line_stripped == "}":
                fields = parse_rust_struct(struct_lines_buffer)
                if fields:
                    gd_script_content = generate_gdscript(current_table_name, fields)
                    output_filename = f"{current_table_name}.gd"
                    output_path = os.path.join(os.path.dirname(filepath), output_filename)
                    try:
                        with open(output_path, 'w', encoding='utf-8') as outfile:
                            outfile.write(gd_script_content)
                        generated_files.append(output_path)
                    except Exception as e:
                        print(f"Ошибка записи файла {output_path}: {e}")
                else:
                    print(f"  Не удалось спарсить поля для структуры {current_struct_name}")

                in_struct = False
                current_table_name = None
                current_struct_name = None
                struct_lines_buffer = []
            continue

        table_match = TABLE_REGEX.search(line_stripped)
        if table_match:
            current_table_name = table_match.group('name')
            found_struct = False
            for j in range(i + 1, len(lines)):
                 next_line_stripped = lines[j].strip()
                 if not next_line_stripped or next_line_stripped.startswith("//"):
                     continue
                 struct_match = STRUCT_START_REGEX.match(next_line_stripped)
                 if struct_match:
                     current_struct_name = struct_match.group('struct_name')
                     in_struct = True
                     struct_lines_buffer = []
                     found_struct = True
                     break
                 else:
                     current_table_name = None
                     break
            if not found_struct and current_table_name:
                 current_table_name = None
    return generated_files

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Генерирует GDScript Resource файлы из Rust структур SpacetimeDB.")
    parser.add_argument(
        "search_dir",
        nargs='?',
        default=".",
        help="Директория для рекурсивного поиска файлов lib.rs (по умолчанию: текущая директория)."
    )
    args = parser.parse_args()

    start_dir = args.search_dir
    abs_start_dir = os.path.abspath(start_dir)

    if not os.path.isdir(abs_start_dir):
        print(f"ОШИБКА: Указанный путь не является директорией: {abs_start_dir}")
        exit(1)

    all_generated_files = []
    found_lib_rs = False
    for root, dirs, files in os.walk(abs_start_dir):
        dirs[:] = [d for d in dirs if d not in ['target', '.git', '.vscode', 'generated_gd']]
        if "lib.rs" in files:
            found_lib_rs = True
            filepath = os.path.join(root, "lib.rs")
            generated = process_file(filepath) # Вызов измененной функции
            all_generated_files.extend(generated)

    if not found_lib_rs:
         print(f"Файлы 'lib.rs' не найдены в директории {abs_start_dir} и ее подпапках.")

    if not all_generated_files and found_lib_rs:
        print("Файлы lib.rs найдены, но не удалось найти структуры с #[table(...)] или сгенерировать GDScript файлы.")
    elif all_generated_files:
        print("\nГенерация завершена.")
        print("Сгенерированные файлы:")
        for fname in all_generated_files:
            print(f"- {fname}")
    else:
         pass

    print("--- Завершение работы скрипта ---")