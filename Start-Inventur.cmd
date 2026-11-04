@echo off
rem Startet die Inventur mit Administratorrechten (UAC-Abfrage) und umgeht die
rem Execution Policy nur fuer diesen einen Aufruf.
rem Fragt nach dem Kundennamen erst nach der Rechteerhoehung, damit nichts
rem durch den Neustart verloren geht.
setlocal
set "SCRIPT=%~dp0Invoke-Inventur.ps1"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

rem fltmc klappt nur mit Adminrechten und braucht anders als "net session"
rem keinen Serverdienst.
fltmc >nul 2>&1
if not errorlevel 1 goto elevated

rem Eigenen Pfad als Umgebungsvariable uebergeben, damit Zeichen wie ' oder !
rem im Pfad den PowerShell-Aufruf nicht brechen.
set "INVENTUR_CMD=%~f0"
"%PS%" -NoProfile -Command "Start-Process -FilePath $env:INVENTUR_CMD -Verb RunAs"
exit /b

:elevated
rem Nur Systemmodule laden, nicht die aus dem Dokumente-Ordner des Benutzers
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"

echo Inventur von %COMPUTERNAME%
echo.
set "KUNDE="
set /p "KUNDE=Kundenname (Enter = ohne): "

setlocal EnableDelayedExpansion
rem Anfuehrungszeichen entfernen, sonst bricht der Aufruf
if defined KUNDE set "KUNDE=!KUNDE:"=!"
:trim
rem Ein Backslash am Ende wuerde das schliessende Anfuehrungszeichen entwerten
if defined KUNDE if "!KUNDE:~-1!"=="\" (
    set "KUNDE=!KUNDE:~0,-1!"
    goto trim
)

echo.
if defined KUNDE (
    "%PS%" -NoProfile -ExecutionPolicy Bypass -File "!SCRIPT!" -Kunde "!KUNDE!"
) else (
    "%PS%" -NoProfile -ExecutionPolicy Bypass -File "!SCRIPT!"
)
echo.
pause
