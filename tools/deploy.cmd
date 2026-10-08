@echo off
rem ---------------------------------------------------------------------------
rem  Double-clickable deploy for the CNC controller.
rem
rem  Make a desktop shortcut: right-click this file, Send to, Desktop.
rem  Pass a different address by editing BOARD below, or as an argument.
rem ---------------------------------------------------------------------------
setlocal

set BOARD=192.168.0.23
if not "%~1"=="" set BOARD=%~1

cd /d "%~dp0.."

echo ===========================================================
echo  Deploy to FluidNC at %BOARD%
echo  Repo: %CD%
echo ===========================================================
echo.

where git >nul 2>&1
if errorlevel 1 (
    echo git not found on PATH - skipping the update check.
    echo.
) else (
    echo Checked out:
    git log --oneline -1
    echo.
    echo Checking GitHub for updates...
    git pull --ff-only
    echo.
    echo Now at:
    git log --oneline -1
    echo.
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" -Board %BOARD%

echo.
echo ===========================================================
pause
