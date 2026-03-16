
@echo off
setlocal enabledelayedexpansion

xmake clean -a
set VM_64bit=1
set LUAT_USE_GUI=y
xmake f -a x86 -y -p windows --toolchain=msvc
if !errorlevel! neq 0 exit /b !errorlevel!
xmake g --pkg_searchdirs=%cd%\pkgs
if !errorlevel! neq 0 exit /b !errorlevel!

@REM xmake f -m debug
xmake -y
if !errorlevel! neq 0 exit /b !errorlevel!

echo Build completed successfully!
exit /b 0
