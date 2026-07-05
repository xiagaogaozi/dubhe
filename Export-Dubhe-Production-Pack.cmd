@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe production launch pack
echo.
echo This creates a Chinese action pack for production blockers, owners, evidence, and next steps.
echo It does not mark Dubhe production-ready; it helps the team finish the missing work.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\export-production-pack.ps1" -StartCore -OpenFolder
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Production pack export failed. Send the output above to the developer.
) else (
  echo Production pack exported. Review .dubhe-run\production-pack.
)
echo.
pause
exit /b %DUBHE_EXIT%
