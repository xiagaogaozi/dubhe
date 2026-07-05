@echo off
set "DUBHE_ROOT=%~dp0"

echo Stop Dubhe Core
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\start-local-dubhe.ps1" -StopCoreOnly -StopAllCoreInstances
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Stop failed. Send the error above to the developer.
) else (
  echo Dubhe Core stop was requested.
)
echo.
pause
exit /b %DUBHE_EXIT%
