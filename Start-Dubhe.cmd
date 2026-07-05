@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe one-click startup
echo.
echo Starting Dubhe Core and opening Dubhe Desktop...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\start-local-dubhe.ps1" -RunCheck
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Startup failed. Send the error above to the developer, or check %DUBHE_ROOT%.dubhe-run\core.err.log
  echo.
  pause
  exit /b %DUBHE_EXIT%
)

echo Dubhe startup was requested. If the desktop app did not appear, check %DUBHE_ROOT%.dubhe-run\
echo.
pause
