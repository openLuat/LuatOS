@echo off
REM Wrapper script to invoke PowerShell build script
REM Self-relocates to the script directory before execution

pushd "%~dp0"
powershell.exe -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
set BUILD_EXIT=%ERRORLEVEL%
popd
exit /b %BUILD_EXIT%
