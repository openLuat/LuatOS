#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Suffix for the output file, e.g. "32" or "64". Empty means the legacy name.
SUFFIX="${LUAT_EMS_LUAC_SUFFIX:-}"
export LUAT_EMS_LUAC_SUFFIX="$SUFFIX"

# Lua interpreter to use. Defaults depend on the requested suffix:
# - 32-bit (or legacy) output uses the 32-bit PC simulator build.
# - 64-bit output uses the 64-bit PC simulator build if present,
#   otherwise falls back to a system lua5.3 (which must be 64-bit).
if [ -z "${LUATOS_LUA_EXE:-}" ]; then
    if [ "$SUFFIX" == "64" ]; then
        LUATOS_EXE="$SCRIPT_DIR/../../bsp/pc/build/out64/luatos-lua.exe"
    else
        LUATOS_EXE="$SCRIPT_DIR/../../bsp/pc/build/out/luatos-lua.exe"
    fi
else
    LUATOS_EXE="$LUATOS_LUA_EXE"
fi

TMP_DIR="/tmp/gen_luac_$$"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR"
cp "$SCRIPT_DIR/ems.lua" "$TMP_DIR/ems.lua"
cp "$SCRIPT_DIR/gen_luac.lua" "$TMP_DIR/main.lua"

# Build the output file name
OUT_NAME="luat_ems_server_luac"
if [ -n "$SUFFIX" ]; then
    OUT_NAME="${OUT_NAME}_${SUFFIX}"
fi
OUT_FILE="$SCRIPT_DIR/src/${OUT_NAME}.c"

run_with_luatos() {
    if [ ! -f "$LUATOS_EXE" ]; then
        return 1
    fi
    echo "Using $LUATOS_EXE to generate luac..." >&2
    cd "$SCRIPT_DIR"
    env LUATOS_EMS_DIR="$TMP_DIR" "$LUATOS_EXE" "$TMP_DIR" >"$TMP_DIR/output.txt" 2>&1
    grep -q "SUCCESS" "$TMP_DIR/output.txt"
}

run_with_lua53() {
    if ! command -v lua5.3 >/dev/null 2>&1; then
        return 1
    fi
    echo "Using lua5.3 to generate luac..." >&2
    cd "$TMP_DIR"
    env LUATOS_EMS_DIR="$TMP_DIR" lua5.3 main.lua >"$TMP_DIR/output.txt" 2>&1
    grep -q "SUCCESS" "$TMP_DIR/output.txt"
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
    cd "$TMP_DIR"
    env LUATOS_EMS_DIR="$TMP_DIR" lua main.lua >"$TMP_DIR/output.txt" 2>&1
    grep -q "SUCCESS" "$TMP_DIR/output.txt"
}

if [ "$SUFFIX" == "64" ]; then
    if run_with_luatos || run_with_lua53 || run_with_lua; then
        :
    else
        echo "WARNING: No suitable Lua interpreter found (luatos-lua.exe, lua5.3, lua 5.3)" >&2
        echo "Skipping luac generation. Using pre-generated file if exists." >&2
        if [ -f "$OUT_FILE" ]; then
            echo "Pre-generated file exists: $OUT_FILE" >&2
            exit 0
        else
            echo "ERROR: No pre-generated file found at $OUT_FILE" >&2
            exit 1
        fi
    fi
else
    if run_with_luatos; then
        :
    else
        echo "WARNING: No suitable 32-bit Lua interpreter found (luatos-lua.exe)" >&2
        echo "Skipping luac generation. Using pre-generated file if exists." >&2
        if [ -f "$OUT_FILE" ]; then
            echo "Pre-generated file exists: $OUT_FILE" >&2
            exit 0
        else
            echo "ERROR: No pre-generated file found at $OUT_FILE" >&2
            exit 1
        fi
    fi
fi

if [ ! -f "$TMP_DIR/src/${OUT_NAME}.c" ]; then
    echo "ERROR: expected output file not created: $TMP_DIR/src/${OUT_NAME}.c" >&2
    exit 1
fi

mkdir -p "$SCRIPT_DIR/src"
cp "$TMP_DIR/src/${OUT_NAME}.c" "$OUT_FILE"
echo "Generated: $OUT_FILE" >&2
