@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe GitHub Actions authorization
echo.
echo This asks GitHub CLI to add workflow scope, which is required
echo before Dubhe can push .github\workflows package builders.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\authorize-github-workflow-scope.ps1" -OpenReport
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo GitHub Actions authorization needs attention. Review .dubhe-run\github-workflow-scope-authorization.txt.
) else (
  echo GitHub Actions authorization completed. You can now run Activate-Dubhe-GitHub-Actions.cmd.
)
echo.
pause
exit /b %DUBHE_EXIT%
