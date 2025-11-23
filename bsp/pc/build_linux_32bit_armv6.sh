
# ubuntu下所需要安装的软件
# apt install gcc-multilib apt install g++-multilib

xmake clean -a
export VM_64bit=0
export LUAT_USE_GUI=n
xmake f -p linux  -a armv6 -m debug
xmake -w -y
