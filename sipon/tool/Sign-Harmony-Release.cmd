@echo off
setlocal
title Sipon HarmonyOS Release Signing
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0sign_harmony_release.ps1"
set "SIGN_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %SIGN_EXIT%
