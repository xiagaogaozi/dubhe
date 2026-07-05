@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe local readiness check
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\check-local-dubhe.ps1"
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo The check found blocking items. Send the output above to the developer.
) else (
  echo Check finished.
)
echo.
pause
exit /b %DUBHE_EXIT%
