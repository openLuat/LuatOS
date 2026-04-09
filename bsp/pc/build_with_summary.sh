#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODE=${LUAT_BUILD_MODE:-summary}
ARCH=i386
VM_64BIT=1
USE_GUI=n
PLATFORM=linux
CONFIGURE_MODE=
CLEAN=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --vm64)
            VM_64BIT="$2"
            shift 2
            ;;
        --gui)
            USE_GUI="$2"
            shift 2
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --configure-mode)
            CONFIGURE_MODE="$2"
            shift 2
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

LOG_DIR="$SCRIPT_DIR/build/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pc_build_$(date +%Y%m%d_%H%M%S).log"
NOISE_PATTERN='components/(airui/lvgl9|mbedtls|mbedtls3|network/lwip22|multimedia/(amr_decode|opus)|fatfs|lfs|iconv)|lua/src/|windows kits/'

log_section() {
    echo "[pc-build] $1"
}

show_summary() {
    STEP_NAME="$1"
    TMP_FILE="$2"

    if [ "$MODE" = "full" ]; then
        cat "$TMP_FILE"
        return
    fi

    ERROR_LINES=$(grep -Ei '(: error [A-Za-z0-9]+)|(fatal error)|(\berror\b:)|(undefined reference)|(collect2: error)|(LNK[0-9]+)' "$TMP_FILE" || true)
    CORE_WARNING_LINES=$(grep -Ei '(: warning [A-Za-z0-9]+)|(\bwarning\b:)' "$TMP_FILE" | grep -Eiv "$NOISE_PATTERN" || true)
    NOISE_WARNING_COUNT=$(grep -Ei '(: warning [A-Za-z0-9]+)|(\bwarning\b:)' "$TMP_FILE" | grep -Eic "$NOISE_PATTERN" || true)

    if [ -n "$ERROR_LINES" ]; then
        ERROR_COUNT=$(printf '%s\n' "$ERROR_LINES" | sed '/^$/d' | wc -l | tr -d ' ')
        log_section "$STEP_NAME failed with $ERROR_COUNT error line(s)"
        printf '%s\n' "$ERROR_LINES"
    elif [ -n "$CORE_WARNING_LINES" ]; then
        WARNING_COUNT=$(printf '%s\n' "$CORE_WARNING_LINES" | sed '/^$/d' | wc -l | tr -d ' ')
        log_section "$STEP_NAME emitted $WARNING_COUNT visible warning line(s)"
        WARNING_CODES=$(printf '%s\n' "$CORE_WARNING_LINES" | grep -Eo '[A-Za-z]+[0-9]+' | tr '[:lower:]' '[:upper:]' | awk '{count[$0]++} END {for (k in count) print count[k], k}' | sort -nr | head -n 8 || true)
        if [ -n "$WARNING_CODES" ]; then
            log_section "$STEP_NAME warning codes (top 8)"
            printf '%s\n' "$WARNING_CODES"
        fi
        log_section "$STEP_NAME sample warnings (up to 12 lines)"
        printf '%s\n' "$CORE_WARNING_LINES" | head -n 12
        if [ "$WARNING_COUNT" -gt 12 ] 2>/dev/null; then
            log_section "$STEP_NAME omitted $((WARNING_COUNT - 12)) additional visible warning line(s); see $LOG_FILE"
        fi
    else
        log_section "$STEP_NAME completed without visible warnings"
    fi

    if [ "$NOISE_WARNING_COUNT" -gt 0 ] 2>/dev/null; then
        log_section "$STEP_NAME suppressed $NOISE_WARNING_COUNT third-party warning line(s); see $LOG_FILE"
    fi
}

run_step() {
    STEP_NAME="$1"
    shift

    TMP_FILE=$(mktemp)
    log_section "$STEP_NAME: xmake $*"
    if xmake "$@" >"$TMP_FILE" 2>&1; then
        STATUS=0
    else
        STATUS=$?
    fi

    {
        printf '=== %s: xmake %s ===\n' "$STEP_NAME" "$*"
        cat "$TMP_FILE"
    } >>"$LOG_FILE"

    show_summary "$STEP_NAME" "$TMP_FILE"
    rm -f "$TMP_FILE"

    if [ "$STATUS" -ne 0 ]; then
        log_section "$STEP_NAME failed; check full log: $LOG_FILE"
        exit "$STATUS"
    fi
}

cd "$SCRIPT_DIR"
export VM_64bit="$VM_64BIT"
export LUAT_USE_GUI="$USE_GUI"

log_section "mode=$MODE clean=$CLEAN arch=$ARCH vm64=$VM_64BIT gui=$USE_GUI platform=$PLATFORM"
log_section "full log: $LOG_FILE"

if [ "$CLEAN" -eq 1 ] || [ "${LUAT_BUILD_CLEAN:-0}" = "1" ]; then
    run_step clean clean -a
fi

if [ -n "$CONFIGURE_MODE" ]; then
    run_step configure f -p "$PLATFORM" -a "$ARCH" -m "$CONFIGURE_MODE" -y
else
    run_step configure f -p "$PLATFORM" -a "$ARCH" -y
fi

run_step build -y
log_section "Build completed successfully"