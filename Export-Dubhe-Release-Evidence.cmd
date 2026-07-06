@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe release evidence pack
echo.
echo This exports a Chinese evidence pack for the latest delivery ZIP,
echo installer verification, four-platform gaps, local check, and production readiness.
echo It does not mark Dubhe production-ready.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\export-release-evidence.ps1" -StartCore -OpenFolder
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Release evidence export failed. Send the output above to the developer.
) else (
  echo Release evidence exported. Review .dubhe-run\release-evidence.
)
echo.
pause
exit /b %DUBHE_EXIT%
