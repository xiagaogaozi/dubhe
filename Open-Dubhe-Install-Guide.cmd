@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe install package guide
echo.
echo A Chinese four-platform guide will open in Notepad. Keep this window open for live paths and URLs.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\show-install-guide.ps1" -OpenNotepad
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Failed to open the install guide. Send the error above to the developer.
) else (
  echo Install guide opened.
)
echo.
pause
exit /b %DUBHE_EXIT%
