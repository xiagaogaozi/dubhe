@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe GitHub Actions activator
echo.
echo This copies CI workflow templates into .github\workflows,
echo then commits and pushes them when GitHub CLI has workflow scope.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\activate-github-actions.ps1" -CommitAndPush -OpenReport
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo GitHub Actions activation needs attention. Review .dubhe-run\github-actions-activation.txt.
) else (
  echo GitHub Actions activation completed.
)
echo.
pause
exit /b %DUBHE_EXIT%
