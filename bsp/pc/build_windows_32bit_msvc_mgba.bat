@echo off
setlocal enabledelayedexpansion

echo Building LuatOS-PC with mGBA support...

set "MODE=%LUAT_BUILD_MODE%"
if not defined MODE set "MODE=summary"
set "CLEAN_FLAG="

if /i "%~1"=="full" set "MODE=full"
if /i "%~2"=="full" set "MODE=full"
if /i "%~1"=="clean" set "CLEAN_FLAG=-Clean"
if /i "%~2"=="clean" set "CLEAN_FLAG=-Clean"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_with_summary.ps1" -Arch x86 -Vm64 0 -Gui y -Mgba y -Mode %MODE% %CLEAN_FLAG%
if %errorlevel% neq 0 exit /b %errorlevel%

echo mGBA support enabled.
exit /b 0