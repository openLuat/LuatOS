#!/usr/bin/env python3
"""Regenerate luat_inline_libs_source.c from script/corelib/*.lua.

This produces a source-level inline library array so that the firmware can
load sys.lua / sysplus.lua as plain text instead of precompiled luac, which
avoids size_t mismatch errors on 64-bit platforms.
"""

import os
import glob

CORELIB_DIR = "script/corelib"
OUTPUT_PATH = "luat/vfs/luat_inline_libs_source.c"

def write_byte_array(f, name, data):
    f.write(f"const char {name}[] = {{\n\n")
    for i in range(0, len(data), 16):
        chunk = data[i:i+16]
        hex_vals = ", ".join(f"0x{b:02X}" for b in chunk)
        f.write(f"{hex_vals}, \n")
    f.write("};\n\n")

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    corelib = os.path.join(repo_root, CORELIB_DIR)
    output = os.path.join(repo_root, OUTPUT_PATH)

    lua_files = sorted(glob.glob(os.path.join(corelib, "*.lua")))
    if not lua_files:
        raise RuntimeError(f"no .lua files found in {corelib}")

    with open(output, "w", encoding="utf-8", newline="\r\n") as f:
        f.write('#include "luat_base.h"\n')
        f.write('#include "luat_fs.h"\n')
        f.write('#include "luat_luadb.h"\n')
        f.write("\n")

        file_entries = []
        for path in lua_files:
            filename = os.path.basename(path)
            stem = os.path.splitext(filename)[0]
            with open(path, "rb") as src:
                data = src.read()

            f.write(f"//------- {filename}\n")
            arr_name = f"luat_inline2_{stem}_source"
            write_byte_array(f, arr_name, data)
            file_entries.append((filename, len(data), arr_name))

        f.write("const luadb_file_t luat_inline2_libs_source[] = {\n")
        for filename, size, arr_name in file_entries:
            f.write(f'   {{.name="{filename}",.size={size}, .ptr={arr_name}}},\n')
        f.write('   {.name="",.size=0,.ptr=NULL}\n')
        f.write("};\n")

    print(f"Generated {OUTPUT_PATH} with {len(lua_files)} file(s)")

if __name__ == "__main__":
    main()
