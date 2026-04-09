
@echo off
setlocal enabledelayedexpansion

set "MODE=%LUAT_BUILD_MODE%"
if not defined MODE set "MODE=summary"
set "CLEAN_FLAG="

if /i "%~1"=="full" set "MODE=full"
if /i "%~2"=="full" set "MODE=full"
if /i "%~1"=="clean" set "CLEAN_FLAG=-Clean"
if /i "%~2"=="clean" set "CLEAN_FLAG=-Clean"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_with_summary.ps1" -Arch x86 -Vm64 1 -Gui n -Mode %MODE% %CLEAN_FLAG%
exit /b %errorlevel%
