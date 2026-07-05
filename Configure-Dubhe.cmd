@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe local configuration
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\configure-local-dubhe.ps1" -Guided
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Configuration failed. Send the error above to the developer.
) else (
  echo Configuration file opened. Save it, then restart Dubhe.
)
echo.
pause
exit /b %DUBHE_EXIT%
