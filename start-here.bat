@echo off
setlocal
title Obsidian - add 2nd instance
set "DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%setup-obsidian-profile.ps1"
if errorlevel 1 (
  echo.
  echo Setup failed. Please send setup-log.txt in this folder.
  pause
)
endlocal
