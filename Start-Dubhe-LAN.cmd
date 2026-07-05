@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe LAN startup for phone/tablet
echo.
echo This will restart Dubhe Core so phones on the same Wi-Fi can connect.
echo Windows Firewall may ask for permission; choose private network access.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\start-local-dubhe.ps1" -AllowLan -RestartCore -RunCheck
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo LAN startup failed. Send the error above to the developer, or check %DUBHE_ROOT%.dubhe-run\core.err.log
  echo.
  pause
  exit /b %DUBHE_EXIT%
)

echo Dubhe LAN startup was requested. Use the mobile Core URL shown above on the phone login page.
echo.
pause
exit /b %DUBHE_EXIT%
