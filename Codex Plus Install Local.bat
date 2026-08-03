@echo off
setlocal

rem Launch the local installer from a checked-out repo.
rem Double-click this file from the repo root or place a shortcut to it on the desktop.

set "REPO_ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%install.ps1" -LocalDev %*
exit /b %ERRORLEVEL%
