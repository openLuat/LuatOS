
# ubuntu下所需要安装的软件
# apt install gcc-multilib apt install g++-multilib

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

sh "$(dirname "$0")/build_with_summary.sh" --platform linux --arch i386 --vm64 0 --gui n --mode "$MODE" --configure-mode debug $CLEAN_FLAG
