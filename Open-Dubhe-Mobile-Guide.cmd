@echo off
set "DUBHE_ROOT=%~dp0"

echo Dubhe mobile connection guide
echo.
echo A Chinese guide will open in Notepad. Keep this window open for live paths and URLs.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUBHE_ROOT%scripts\show-mobile-guide.ps1" -OpenNotepad
set "DUBHE_EXIT=%ERRORLEVEL%"

echo.
if not "%DUBHE_EXIT%"=="0" (
  echo Failed to open the mobile guide. Send the error above to the developer.
) else (
  echo Mobile guide opened.
)
echo.
pause
exit /b %DUBHE_EXIT%
