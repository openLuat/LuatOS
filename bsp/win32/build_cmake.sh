# Using in msys

mkdir build
cd build
cmake -G"Unix Makefiles" ..
make -j8
echo "Done"

#编译串口库，得有rust环境
# cd ../tools/luat_uart/
# cargo build --release
# rm ../../build/luat_uart.dll
# cp -f target/release/luat_uart.dll ../../build

#下载现成的编译好的
wget https://github.com/openLuat/LuatOS/releases/download/v0.0.1/luat_uart.dll
