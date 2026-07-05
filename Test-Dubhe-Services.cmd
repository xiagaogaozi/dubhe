@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe external services live check
echo.
echo This checks configured AI and news services through Dubhe Core.
echo It may make minimal provider requests when keys are configured.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\test-external-services.ps1" -Live
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo External service check needs attention. If Core is not running, double-click Start-Dubhe.cmd first.
) else (
  echo External service check completed.
)
echo.
pause
exit /b %DUBHE_EXIT%
