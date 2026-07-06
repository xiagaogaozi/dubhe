@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe CI artifact importer
echo.
echo Put downloaded GitHub Actions artifact ZIPs or folders into .dubhe-run\ci-artifacts first.
echo This imports Windows/macOS/iOS/Android package artifacts into the expected build folders,
echo then rebuilds the latest delivery ZIP and runs delivery verification.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\import-ci-artifacts.ps1" -PrepareDelivery -VerifyDelivery -OpenReport -OpenFolder
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo CI artifact import needs attention. Put artifact ZIPs into .dubhe-run\ci-artifacts and try again.
) else (
  echo CI artifact import completed.
)
echo.
pause
exit /b %DUBHE_EXIT%
