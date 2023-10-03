
# ubuntu下所需要安装的软件
# apt install gcc-multilib apt install g++-multilib

xmake clean -a
export VM_64bit=0
xmake f -p linux  -a i386
xmake -w