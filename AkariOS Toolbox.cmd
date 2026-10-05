@echo off
REM ============================================================
REM  AkariOS Ultimate Toolbox
REM
REM  Launches the WPF front end. WPF needs an STA thread, and
REM  powershell.exe only defaults to STA in v3+, so -STA is
REM  explicit rather than assumed.
REM
REM  Everything resolves relative to this file, so the toolbox
REM  can be dropped in any folder and run from anywhere.
REM ============================================================

setlocal
cd /d "%~dp0"

if not exist "GUI\Main.ps1" (
    echo GUI\Main.ps1 not found next to this launcher.
    echo Expected: %~dp0GUI\Main.ps1
    pause
    exit /b 1
)

start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0GUI\Main.ps1"

endlocal