@echo off
rem Startet die Inventur mit Administratorrechten (UAC-Abfrage) und umgeht die
rem Execution Policy nur fuer diesen einen Aufruf.
rem Fragt nach Kunde und Station erst nach der Rechteerhoehung, damit nichts
rem durch den Neustart verloren geht.
setlocal
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
rem Die Eingaben gehen als Umgebungsvariablen an PowerShell. So bleibt jeder Text ein
rem Wert, auch mit Anfuehrungszeichen, Backslash oder "-" am Anfang.
set "INVENTUR_SCRIPT=%~dp0Invoke-Inventur.ps1"
set "INVENTUR_KUNDE="
set "INVENTUR_STATION="
set /p "INVENTUR_KUNDE=Kundenname (Enter = ohne): "
set /p "INVENTUR_STATION=Station, z. B. PC Sonja oder Empfang 1 (Enter = ohne): "

echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "& $env:INVENTUR_SCRIPT -Kunde $env:INVENTUR_KUNDE -Station $env:INVENTUR_STATION"
echo.
pause
