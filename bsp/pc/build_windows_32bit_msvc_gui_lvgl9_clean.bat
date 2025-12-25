
xmake clean -a
set VM_64bit=0
set LUAT_USE_GUI=y
set LUAT_USE_LVGL9=y
xmake g --pkg_searchdirs=%cd%\pkgs
xmake f -a x86 -y
xmake -y