@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe mobile connection card
echo.
echo This restarts Dubhe Core for phones on the same Wi-Fi, then opens a local connection card.
echo The card includes the Core URL, Android APK path, and a QR code when the local QR tool is available.
echo Windows Firewall may ask for permission; choose private network access.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\start-local-dubhe.ps1" -AllowLan -RestartCore -SkipDesktop
set "DUBHE_EXIT=%ERRORLEVEL%"

if not "%DUBHE_EXIT%"=="0" (
  echo.
  echo LAN Core startup failed. Send the output above to the developer, or check %DUBHE_ROOT%.dubhe-run\core.err.log
  echo.
  pause
  exit /b %DUBHE_EXIT%
)

echo.
echo Creating mobile connection card...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\show-mobile-connect.ps1" -OpenHtml
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Mobile connection card needs attention. Send the output above to the developer.
) else (
  echo Mobile connection card opened. Keep this PC and the phone on the same Wi-Fi.
)
echo.
pause
exit /b %DUBHE_EXIT%
