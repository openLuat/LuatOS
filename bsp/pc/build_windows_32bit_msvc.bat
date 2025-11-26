
xmake clean -a
set VM_64bit=0
set LUAT_USE_GUI=n
xmake g --pkg_searchdirs=%cd%\pkgs
xmake f -a x86 -y
@REM xmake f -m debug
xmake -y
