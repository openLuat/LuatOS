xmake clean -a
export VM_64bit=1
export LUAT_USE_GUI=y
xmake f -p linux  -a i386 -y
xmake -w -y
