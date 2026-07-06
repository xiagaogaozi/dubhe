@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe delivery pack builder
echo.
echo This builds the latest Dubhe user kit ZIP and writes the delivery summary to .dubhe-run.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\prepare-delivery.ps1" -OpenFolder
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Delivery build failed. Send the output above to the developer.
) else (
  echo Delivery pack completed. Open .dubhe-run\LATEST-DUBHE-DELIVERY.txt for the ZIP path and SHA256.
)
echo.
pause
exit /b %DUBHE_EXIT%
