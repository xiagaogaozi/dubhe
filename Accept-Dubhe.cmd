@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe local acceptance
echo.
echo This starts Dubhe Core if needed, then checks local readiness, smoke workflow, and configured external services.
echo Live service checks may make minimal provider requests when keys are configured.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\run-local-acceptance.ps1" -OpenReport
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Acceptance found blocking items. Send the output above and %DUBHE_ROOT%.dubhe-run\local-acceptance.txt to the developer.
) else (
  echo Acceptance completed. Review %DUBHE_ROOT%.dubhe-run\local-acceptance.txt if needed.
)
echo.
pause
exit /b %DUBHE_EXIT%
