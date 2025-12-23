xmake clean -a
export VM_64bit=1
export LUAT_USE_GUI=n
xmake f -p macosx -y
xmake -w -y
