@echo off
rem Startet die Inventur mit Administratorrechten (UAC-Abfrage) und umgeht die
rem Execution Policy nur fuer diesen einen Aufruf.
setlocal
set "SCRIPT=%~dp0Invoke-Inventur.ps1"

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
echo.
pause
