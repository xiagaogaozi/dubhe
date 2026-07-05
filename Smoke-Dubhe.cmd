@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe Core workflow smoke
echo.
echo This smoke test expects Dubhe Core to be running at http://127.0.0.1:8000
echo If Core is not running, double-click Start-Dubhe.cmd first.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\smoke-core-workflow.ps1"
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Smoke test failed. Send the output above and %DUBHE_ROOT%.dubhe-run\smoke-core-workflow.json to the developer.
) else (
  echo Smoke test passed.
)
echo.
pause
exit /b %DUBHE_EXIT%
