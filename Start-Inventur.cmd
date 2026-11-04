@echo off
rem Startet die Inventur mit Administratorrechten (UAC-Abfrage) und umgeht die
rem Execution Policy nur fuer diesen einen Aufruf.
rem Fragt nach Kunde und Station erst nach der Rechteerhoehung, damit nichts
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
set "STATION="
set /p "KUNDE=Kundenname (Enter = ohne): "
set /p "STATION=Station, z. B. PC Sonja oder Empfang 1 (Enter = ohne): "

setlocal EnableDelayedExpansion
call :bereinigen KUNDE
call :bereinigen STATION
set "ARGS="
if defined KUNDE set "ARGS=!ARGS! -Kunde "!KUNDE!""
if defined STATION set "ARGS=!ARGS! -Station "!STATION!""

echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "!SCRIPT!" !ARGS!
echo.
pause
exit /b

:bereinigen
rem Anfuehrungszeichen entfernen, sonst bricht der Aufruf. Ein Backslash am Ende
rem wuerde das schliessende Anfuehrungszeichen entwerten.
if not defined %1 exit /b
set "WERT=!%1:"=!"
:bereinigen_ende
if defined WERT if "!WERT:~-1!"=="\" (
    set "WERT=!WERT:~0,-1!"
    goto bereinigen_ende
)
set "%1=!WERT!"
exit /b
