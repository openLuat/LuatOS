#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LUATOS_EXE="$SCRIPT_DIR/../../bsp/pc/build/out/luatos-lua.exe"
TMP_DIR="/tmp/gen_luac_$$"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR"
cp "$SCRIPT_DIR/ems.lua" "$TMP_DIR/ems.lua"
cp "$SCRIPT_DIR/gen_luac.lua" "$TMP_DIR/main.lua"

run_with_luatos() {
    if [ ! -f "$LUATOS_EXE" ]; then
        return 1
    fi
    echo "Using luatos-lua.exe to generate luac..." >&2
    cd "$SCRIPT_DIR"
    OUTPUT=$("$LUATOS_EXE" "$TMP_DIR" 2>&1 || true)
    return 0
}

run_with_lua53() {
    if ! command -v lua5.3 >/dev/null 2>&1; then
        return 1
    fi
    echo "Using lua5.3 to generate luac..." >&2
    cd "$SCRIPT_DIR"
    OUTPUT=$(cd "$TMP_DIR" && lua5.3 main.lua 2>&1 || true)
    return 0
}

run_with_lua() {
    if ! command -v lua >/dev/null 2>&1; then
        return 1
    fi
    local ver
    ver=$(lua -e 'print(_VERSION)' 2>/dev/null | head -c 10)
    if [ "$ver" != "Lua 5.3" ]; then
        return 1
    fi
    echo "Using lua to generate luac..." >&2
    cd "$SCRIPT_DIR"
    OUTPUT=$(cd "$TMP_DIR" && lua main.lua 2>&1 || true)
    return 0
}

if run_with_luatos || run_with_lua53 || run_with_lua; then
    :
else
    echo "WARNING: No suitable Lua interpreter found (luatos-lua.exe, lua5.3, lua 5.3)" >&2
    echo "Skipping luac generation. Using pre-generated file if exists." >&2
    if [ -f "$SCRIPT_DIR/src/luat_ems_server_luac.c" ]; then
        echo "Pre-generated file exists: src/luat_ems_server_luac.c" >&2
        exit 0
    else
        echo "ERROR: No pre-generated file found at src/luat_ems_server_luac.c" >&2
        exit 1
    fi
fi

# Verify SUCCESS marker
if ! echo "$OUTPUT" | grep -q "SUCCESS"; then
    echo "ERROR: luac generation failed" >&2
    echo "$OUTPUT" >&2
    exit 1
fi

# Filter log prefixes: first two fields are [timestamp] [id]
C_ARRAY=$(echo "$OUTPUT" | awk 'NF>=3 {for(i=3;i<=NF;i++) printf "%s ", $i; print ""}')

# Extract lines between Auto-generated and SUCCESS
C_ARRAY=$(echo "$C_ARRAY" | sed -n '/\/\/ Auto-generated/,/SUCCESS/p' | sed '/SUCCESS/d')

if [ -z "$C_ARRAY" ]; then
    echo "ERROR: failed to extract C array from output" >&2
    exit 1
fi

mkdir -p "$SCRIPT_DIR/src"
echo "$C_ARRAY" > "$SCRIPT_DIR/src/luat_ems_server_luac.c"
echo "Generated: $SCRIPT_DIR/src/luat_ems_server_luac.c" >&2
