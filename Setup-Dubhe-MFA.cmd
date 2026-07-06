@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe local MFA setup
echo.
echo This creates a local TOTP setup card and writes the required values to config\dubhe.local.env.
echo Restart Dubhe Core after setup.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\setup-local-mfa.ps1" -OpenReport
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo MFA setup failed. Send the output above to the developer.
) else (
  echo MFA setup completed. Restart Dubhe, then use the 6-digit code from your authenticator app.
)
echo.
pause
exit /b %DUBHE_EXIT%
