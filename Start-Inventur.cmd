@echo off
rem Startet die Inventur mit Administratorrechten (UAC-Abfrage) und umgeht die
rem Execution Policy nur fuer diesen einen Aufruf.
rem Fragt nach dem Kundennamen erst nach der Rechteerhoehung, damit nichts
rem durch den Neustart verloren geht.
setlocal EnableDelayedExpansion
set "SCRIPT=%~dp0Invoke-Inventur.ps1"

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Inventur von %COMPUTERNAME%
echo.
set "KUNDE="
set /p "KUNDE=Kundenname (Enter = ohne): "

if defined KUNDE (
    rem Anfuehrungszeichen entfernen, sonst bricht der Aufruf
    set "KUNDE=!KUNDE:"=!"
)

echo.
if defined KUNDE (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Kunde "!KUNDE!"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
)
echo.
pause
