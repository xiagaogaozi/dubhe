@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe delivery pack verification
echo.
echo This verifies the latest Dubhe delivery ZIP path, SHA256, required installers, and checksum manifest.
echo Run Prepare-Dubhe-Delivery.cmd first if this window reports that no delivery summary exists.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\verify-delivery-pack.ps1" -OpenReport
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Delivery verification needs attention. Send the output above and %DUBHE_ROOT%.dubhe-run\delivery-verification.txt to the developer.
) else (
  echo Delivery verification completed.
)
echo.
pause
exit /b %DUBHE_EXIT%
