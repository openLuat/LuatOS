xmake clean -a
export VM_64bit=1
export LUAT_USE_GUI=y
xmake f -p macosx -y
xmake -w -y
