xmake clean -a
export VM_64bit=1
xmake f -p linux  -a i386
xmake -w