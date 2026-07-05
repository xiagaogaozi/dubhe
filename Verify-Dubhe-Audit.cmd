@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe audit chain verification
echo.
echo This checks whether the local audit log hash chain is intact.
echo Start Dubhe Core first if this window reports that Core is unavailable.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\verify-audit-chain.ps1" -OpenReport
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Audit verification needs attention. Send the output above and %DUBHE_ROOT%.dubhe-run\audit-chain-verification.txt to the developer.
) else (
  echo Audit verification completed.
)
echo.
pause
exit /b %DUBHE_EXIT%
