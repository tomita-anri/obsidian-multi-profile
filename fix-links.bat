@echo off
setlocal
title Obsidian - fix obsidian:// links
set "DIR=%~dp0"
echo.
echo Which Obsidian should handle obsidian:// links?
echo   1) the original Obsidian  (default)
echo   2) the copied one         (needs its ID, e.g. ai)
echo.
set "CHOICE="
set /p CHOICE=Enter 1 or 2 [1]:
if "%CHOICE%"=="2" goto COPY

powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%fix-uri-handler.ps1" -Target original
goto END

:COPY
set "VID="
set /p VID=ID of the copied Obsidian:
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%fix-uri-handler.ps1" -Target copy -Id "%VID%"

:END
if errorlevel 1 (
  echo.
  echo Failed. Please send fix-uri-handler-log.txt in this folder.
  pause
)
endlocal
