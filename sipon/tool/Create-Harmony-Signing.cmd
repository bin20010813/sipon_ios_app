@echo off
setlocal
title Sipon HarmonyOS Signing Preparation
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0create_harmony_signing.ps1"
set "SIGN_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %SIGN_EXIT%
