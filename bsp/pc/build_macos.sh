MODE=${LUAT_BUILD_MODE:-summary}
CLEAN_FLAG=

for arg in "$@"; do
	if [ "$arg" = "full" ]; then
		MODE=full
	fi
	if [ "$arg" = "clean" ]; then
		CLEAN_FLAG=--clean
	fi
done

sh "$(dirname "$0")/build_with_summary.sh" --platform macosx --arch i386 --vm64 1 --gui n --mode "$MODE" $CLEAN_FLAG
