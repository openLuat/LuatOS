
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

# xmake 构建 CMake 包时设置了 CMAKE_FIND_USE_CMAKE_SYSTEM_PATH=0，但编译器默认
# 仍能看到 /usr/include/samplerate.h。若 SDL2 找到头文件却找不到 32 位库，就会在
# 链接时报 undefined reference to src_new。这里显式指定 32 位的 SampleRate 配置。
# 需要先安装对应包：Arch lib32-libsamplerate，Debian libsamplerate0-dev:i386。
if [ -z "${SampleRate_DIR:-}" ]; then
	for samplerate_dir in \
		/usr/lib32/cmake/SampleRate \
		/usr/lib/i386-linux-gnu/cmake/SampleRate; do
		if [ -f "$samplerate_dir/SampleRateConfig.cmake" ]; then
			SampleRate_DIR="$samplerate_dir"
			export SampleRate_DIR
			break
		fi
	done
fi

sh "$(dirname "$0")/build_with_summary.sh" --platform linux --arch i386 --vm64 0 --gui n --mode "$MODE" --configure-mode debug $CLEAN_FLAG
