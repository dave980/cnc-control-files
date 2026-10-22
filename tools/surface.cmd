@echo off
rem ---------------------------------------------------------------------------
rem  Double-clickable surfacing program generator.
rem
rem  Make a desktop shortcut: right-click this file, Send to, Desktop.
rem  Asks for the board size and writes a .nc file next to the repo.
rem
rem  Needs Python on the machine. For a standalone .exe that does not, see
rem  docs/surfacing.md.
rem ---------------------------------------------------------------------------
setlocal

cd /d "%~dp0.."

set "PY="
where python >nul 2>&1 && set "PY=python"
if not defined PY (
    where py >nul 2>&1 && set "PY=py"
)

if not defined PY (
    echo.
    echo Python was not found on this machine.
    echo Install it from python.org, or use the standalone surface.exe
    echo described in docs\surfacing.md.
    echo.
    pause
    exit /b 1
)

%PY% "%~dp0surface.py" %*

echo.
pause
