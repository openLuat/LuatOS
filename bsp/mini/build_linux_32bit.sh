
# ubuntu下所需要安装的软件
# apt install gcc-multilib apt install g++-multilib

xmake clean -a
xmake f -p linux -a i386 --luavm_64bit=false
xmake -w