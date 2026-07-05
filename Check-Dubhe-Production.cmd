@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe production readiness check
echo.
echo This verifies whether Dubhe is ready for real commercial production use.
echo It is stricter than local smoke tests and is expected to fail until contracts, signing, cloud sync, identity, audit, and broker adapters are complete.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\check-production-readiness.ps1"
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Production readiness has blocking items. This is expected before final production release.
) else (
  echo Production readiness passed.
)
echo.
pause
exit /b %DUBHE_EXIT%
