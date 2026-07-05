@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe user kit builder
echo.
echo This gathers current installers, APKs, guides, checks, and this-PC launchers into .dubhe-run\user-kits.
echo The kit is for this PC/internal testing. Production release still requires signing, cloud sync, licensed data, and broker adapters.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\build-user-kit.ps1" -OpenFolder
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo User kit build failed. Send the output above to the developer.
) else (
  echo User kit build completed.
)
echo.
pause
exit /b %DUBHE_EXIT%
