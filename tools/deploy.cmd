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

rem  The pull below is checked with "if errorlevel 1" rather than
rem  "if %ERRORLEVEL% neq 0" -- inside a parenthesised block cmd expands
rem  %ERRORLEVEL% once, at parse time, so the latter holds the value from
rem  before git ran and the check silently never fires.
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
    if errorlevel 1 (
        echo.
        echo ===========================================================
        echo  PULL FAILED - nothing has been uploaded.
        echo.
        echo  The files on disk may be older than GitHub, and deploying
        echo  them would look exactly like success. Local edits in the
        echo  way, a diverged branch, and no network all land here.
        echo.
        echo  To deploy what is on disk anyway, skipping the pull:
        echo    powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Board %BOARD% -Restart
        echo ===========================================================
        echo.
        pause
        exit /b 1
    )
    echo.
    echo Now at:
    git log --oneline -1
    echo.
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" -Board %BOARD% -Restart

echo.
echo ===========================================================
pause
