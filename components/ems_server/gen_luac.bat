@echo off
setlocal EnableDelayedExpansion
set "SCRIPT_DIR=%~dp0"
set "SUFFIX=%~1"
set "LUAT_EMS_LUAC_SUFFIX=%SUFFIX%"

if "%SUFFIX%"=="64" (
    set "DEFAULT_LUATOS_EXE=%SCRIPT_DIR%..\..\bsp\pc\build\out64\luatos-lua.exe"
) else (
    set "DEFAULT_LUATOS_EXE=%SCRIPT_DIR%..\..\bsp\pc\build\out\luatos-lua.exe"
)
if not defined LUATOS_LUA_EXE (
    set "LUATOS_LUA_EXE=%DEFAULT_LUATOS_EXE%"
)

:: On Windows prefer the PC simulator directly (most reliable).
:: If it is missing, fall back to Git Bash / MSYS2 / Cygwin.
if exist "%LUATOS_LUA_EXE%" goto :run_with_luatos
goto :run_with_bash

:: ----------------------------------------------------------------------
:: Use luatos-lua.exe (PC simulator) to run gen_luac.lua.
:: ----------------------------------------------------------------------
:run_with_luatos
set "LUATOS_EXE=%LUATOS_LUA_EXE%"
set "TMP_DIR=%TEMP%\gen_luac_%RANDOM%"

mkdir "%TMP_DIR%"
copy /Y "%SCRIPT_DIR%ems.lua" "%TMP_DIR%\ems.lua" >nul
copy /Y "%SCRIPT_DIR%gen_luac.lua" "%TMP_DIR%\main.lua" >nul

:: luatos-lua.exe runs main.lua with TMP_DIR as VFS root.
cd /d "%SCRIPT_DIR%"
set "LUATOS_EMS_DIR=%TMP_DIR%"
"%LUATOS_EXE%" "%TMP_DIR%" > "%TMP_DIR%\output.txt" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"

findstr /C:"SUCCESS" "%TMP_DIR%\output.txt" >nul
if errorlevel 1 (
    echo ERROR: luac generation failed
    type "%TMP_DIR%\output.txt"
    rmdir /S /Q "%TMP_DIR%"
    exit /b 1
)

if not exist "%SCRIPT_DIR%src" mkdir "%SCRIPT_DIR%src"
copy /Y "%TMP_DIR%\src\luat_ems_server_luac_%SUFFIX%.c" "%SCRIPT_DIR%src\" >nul
rmdir /S /Q "%TMP_DIR%"
echo Generated: %SCRIPT_DIR%src\luat_ems_server_luac_%SUFFIX%.c
exit /b 0

:: ----------------------------------------------------------------------
:: Use bash (Git Bash / MSYS2 / Cygwin / WSL) to run gen_luac.sh.
:: ----------------------------------------------------------------------
:run_with_bash
:: Prefer WSL bash (System32/bash.exe) over Git Bash because WSL usually has lua5.3.
set "BASH_EXE="
if exist "%SystemRoot%\System32\bash.exe" (
    set "BASH_EXE=%SystemRoot%\System32\bash.exe"
) else (
    for /f "delims=" %%i in ('where bash.exe 2^>nul') do (
        if not defined BASH_EXE set "BASH_EXE=%%i"
    )
)

if not defined BASH_EXE (
    echo ERROR: neither luatos-lua.exe nor bash.exe found.
    echo Please build the PC simulator or install Git Bash.
    exit /b 1
)

:: Convert the .sh path to POSIX style for bash.
set "SH_PATH=%SCRIPT_DIR%gen_luac.sh"
set "IS_WSL=0"
if not "!BASH_EXE:System32=!"=="!BASH_EXE!" set "IS_WSL=1"
if not "!BASH_EXE:WindowsApps=!"=="!BASH_EXE!" set "IS_WSL=1"

if "%IS_WSL%"=="1" goto :run_with_wsl

:: Git Bash / MSYS2 / Cygwin path conversion for gen_luac.sh
set "CYGPATH_EXE=%BASH_EXE:\bash.exe=\cygpath.exe%"
set "CYGPATH_EXE=!CYGPATH_EXE:\usr\bin\bash.exe=\usr\bin\cygpath.exe!"
if exist "!CYGPATH_EXE!" (
    "!CYGPATH_EXE!" -u "!SH_PATH!" > "%TEMP%\ems_sh_path.txt"
    set /p SH_PATH=<"%TEMP%\ems_sh_path.txt"
    del "%TEMP%\ems_sh_path.txt" 2>nul
) else (
    set "SH_PATH=!SH_PATH:\=/!"
)

set "LUAT_EMS_LUAC_SUFFIX=%SUFFIX%"
"%BASH_EXE%" "!SH_PATH!"
exit /b !errorlevel!

:: ----------------------------------------------------------------------
:: Use WSL bash + lua5.3 (64-bit only, because WSL lua5.3 is 64-bit).
:: ----------------------------------------------------------------------
:run_with_wsl
if not "%SUFFIX%"=="64" (
    echo ERROR: 32-bit luac requires a 32-bit Lua interpreter. Please build or specify luatos-lua.exe.
    exit /b 1
)
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "wsl wslpath -u '%SCRIPT_DIR:\=/%'"`) do set "WSL_DIR=%%p"
"%BASH_EXE%" -c "cd '!WSL_DIR!' && export LUAT_EMS_LUAC_SUFFIX='%SUFFIX%' && export LUATOS_EMS_DIR=. && lua5.3 gen_luac.lua"
exit /b !errorlevel!
