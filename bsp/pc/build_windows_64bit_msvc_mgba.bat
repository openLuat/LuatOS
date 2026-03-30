@echo off
setlocal enabledelayedexpansion

echo Building LuatOS-PC with mGBA support...

xmake clean -a
set VM_64bit=1
set LUAT_USE_GUI=y
set LUAT_USE_MGBA=y
xmake f -a x86 -y -p windows --toolchain=msvc
if !errorlevel! neq 0 exit /b !errorlevel!
xmake g --pkg_searchdirs=%cd%\pkgs
if !errorlevel! neq 0 exit /b !errorlevel!

xmake -y
if !errorlevel! neq 0 exit /b !errorlevel!

echo Build completed successfully!
echo mGBA support enabled.
exit /b 0