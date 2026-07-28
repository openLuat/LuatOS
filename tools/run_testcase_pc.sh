#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="$ROOT/bsp/pc/build/out/luatos-lua.exe"
COMMON="$ROOT/testcase/common/scripts"
LIBS="$ROOT/script/libs"
OUTDIR="$ROOT/pc_test_results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

TESTS_FILE="$OUTDIR/tests.txt"
find "$ROOT/testcase" -type f -name main.lua -path '*/scripts/*' | sed 's|/scripts/main\.lua$||' | grep -v 'testcase/common$' | sort > "$TESTS_FILE"

PASS=0
FAIL=0
TIMEOUT=0
CRASH=0
UNKNOWN=0

TOTAL=$(wc -l < "$TESTS_FILE")
INDEX=0

while IFS= read -r t; do
    INDEX=$((INDEX+1))
    name="${t#$ROOT/testcase/}"
    logfile="$OUTDIR/${name//\//__}.log"
    printf '[%d/%d] Running %s ...\n' "$INDEX" "$TOTAL" "$name"
    timeout 60s "$EXE" "$COMMON" "$LIBS" "$t/scripts" > "$logfile" 2>&1
    rc=$?
    if [ $rc -eq 124 ]; then
        printf 'TIMEOUT %s\n' "$name"
        TIMEOUT=$((TIMEOUT+1))
    elif [ $rc -ne 0 ]; then
        printf 'CRASH(exit=%d) %s\n' "$rc" "$name"
        CRASH=$((CRASH+1))
    else
        if grep -q '### OVERALL_PASS ###' "$logfile"; then
            printf 'PASS %s\n' "$name"
            PASS=$((PASS+1))
        elif grep -q '### OVERALL_FAIL ###' "$logfile"; then
            printf 'FAIL %s\n' "$name"
            FAIL=$((FAIL+1))
        else
            printf 'UNKNOWN %s\n' "$name"
            UNKNOWN=$((UNKNOWN+1))
        fi
    fi
done < "$TESTS_FILE"

{
    echo "===== Summary ====="
    echo "Total: $TOTAL"
    echo "PASS: $PASS"
    echo "FAIL: $FAIL"
    echo "TIMEOUT: $TIMEOUT"
    echo "CRASH: $CRASH"
    echo "UNKNOWN: $UNKNOWN"
} | tee "$OUTDIR/summary.txt"
