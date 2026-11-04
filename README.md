# win-inventory

Inventur für Windows-10/11-Rechner per PowerShell. Das Skript erfasst Hardware, Sicherheit,
Benutzer, Lizenz und installierte Software und schreibt alles in einen Markdown-Report. Daraus
wird mit Pandoc ein sauberer HTML- oder PDF-Bericht für den Kunden.

- Läuft mit **Windows PowerShell 5.1**, das auf jedem Windows 10/11 vorinstalliert ist.
- Braucht **keine Installation, keine Module und kein Internet**.
- **Liest nur** und ändert nichts am System.

## Schnellstart mit Inventur.exe

1. **[Inventur.exe herunterladen](https://github.com/xxiten/win-inventory/releases/latest/download/Inventur.exe)**
   (immer die neueste Version, ältere unter [Releases](https://github.com/xxiten/win-inventory/releases))
   und auf den Zielrechner kopieren, z. B. per USB-Stick.
2. Doppelklicken und die Abfrage nach Administratorrechten bestätigen.
3. **Kunde** und **Techniker** eintragen. Der Techniker wird für den nächsten Start gemerkt.
4. Bei Bedarf Zielordner und Optionen anpassen, dann *Inventur starten*.
5. Nach etwa einer Minute ist der Report fertig. *Report öffnen* bzw. *Ordner öffnen* führen direkt hin.

Standard-Zielordner ist der Ordner der Exe, also z. B. der USB-Stick. Ist der schreibgeschützt,
wird der Desktop vorgeschlagen. Der Dateiname ist `Inventur_<RECHNER>_<Datum>.md`.

> Die Exe ist **nicht digital signiert**. Windows zeigt deshalb bei der UAC-Abfrage
> „Unbekannter Herausgeber“, und SmartScreen kann beim ersten Start warnen
> (*Weitere Informationen → Trotzdem ausführen*). Mit einem Code-Signing-Zertifikat
> verschwinden beide Hinweise.

**Ohne Exe:** Repo als ZIP herunterladen und `Start-Inventur.cmd` doppelklicken. Der Starter
fragt im Konsolenfenster nach dem Kundennamen.

## Dateien

| Datei | Zweck |
|---|---|
| `Invoke-Inventur.ps1` | Das Inventur-Skript, steckt auch eingebettet in der Exe |
| `src/InventurLauncher.cs` | Quellcode der Exe (Oberfläche, startet das eingebettete Skript) |
| `src/app.manifest` | Manifest der Exe: fordert Adminrechte an |
| `build.ps1` | Baut `dist\Inventur.exe` |
| `Start-Inventur.cmd` | Alternative ohne Exe: holt Adminrechte, fragt nach dem Kundennamen und startet das Skript |
| `report.css` | Layout für den HTML/PDF-Report (A4, Seitenzahlen, Tabellen) |

## Was erfasst wird

| Abschnitt | Inhalt |
|---|---|
| Übersicht | Hersteller, Modell, Seriennummer, UUID, Gerätetyp, Windows-Edition, -Version und -Build, Installationsdatum, Laufzeit, angemeldeter Benutzer |
| Hardware | CPU, RAM (Module, belegte Slots, max. Ausbau), Mainboard, BIOS/UEFI, physische Datenträger (Typ, Bus, Zustand, Seriennummer), Laufwerke mit Füllstand |
| Peripherie & Grafik | Grafikkarten (Speicher, Treiber, Auflösung), Monitore (Hersteller, Modell, Seriennummer, Baujahr), Drucker, Akku-Gesundheit |
| Sicherheit | TPM, Secure Boot, VBS/Credential Guard, BitLocker je Laufwerk, Virenschutz und Defender-Details, Firewall-Profile, letzte Updates, ausstehender Neustart |
| Benutzer & Lizenz | AD-Domäne oder Arbeitsgruppe, Entra-ID-Beitritt mit Mandant, MDM/Intune, lokale Benutzer und Administratoren, Windows-Lizenz (Kanal, Status, maskierter Schlüssel) |
| Installierte Software | Klassische Programme (64/32 Bit, maschinenweit und pro Benutzer) und Store-Apps, jeweils ohne Systemkomponenten |

Kann ein Abschnitt nicht gelesen werden, steht im Report *Nicht verfügbar* mit dem Grund,
und das Skript läuft weiter.

## Aufruf mit Parametern

Ohne Oberfläche, z. B. für eigene Automatisierung, lässt sich das Skript direkt in einer
PowerShell aufrufen, die als Administrator läuft:

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-Inventur.ps1 -Kunde "Muster GmbH" -Techniker "Max Mustermann"
```

| Parameter | Bedeutung |
|---|---|
| `-Kunde "Name"` | Kundenname im Report-Kopf |
| `-Techniker "Name"` | Name des Technikers im Report-Kopf |
| `-OutputPath <Datei oder Ordner>` | Ziel des Reports (Standard: Ordner des Skripts) |
| `-IncludeProductKey` | OEM-Schlüssel aus der Firmware vollständig ausgeben (Standard: nur die letzten 5 Zeichen) |
| `-NoStoreApps` | Store-Apps weglassen |

Ohne Administratorrechte läuft das Skript ebenfalls durch. Dann fehlen aber u. a. BitLocker,
TPM, Secure Boot und die Store-Apps anderer Benutzer. Der Report weist oben darauf hin.

## Report zu HTML oder PDF

Mit [Pandoc](https://pandoc.org/). Titel, Kunde und Datum übernimmt Pandoc aus dem Kopf des Reports.

```bash
# HTML: eine eigenständige Datei, CSS eingebettet
pandoc Inventur_PC01_2026-11-02.md -s --embed-resources --css report.css -o Inventur_PC01.html

# PDF über WeasyPrint: nutzt dasselbe CSS und bricht breite Tabellen sauber um
pandoc Inventur_PC01_2026-11-02.md -s --css report.css --pdf-engine=weasyprint -o Inventur_PC01.pdf
```

Ohne WeasyPrint: die HTML-Datei im Browser öffnen und über *Drucken → Als PDF speichern*
ausgeben. `report.css` enthält die passenden Druckregeln.

## Exe bauen

Auf jedem Windows-Rechner, ohne Visual Studio oder .NET SDK:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

`build.ps1` nutzt den in Windows enthaltenen C#-Compiler des .NET Framework 4.x und bettet
`Invoke-Inventur.ps1` in die Exe ein. Änderungen am Skript landen also erst nach einem neuen
Build in der Exe.

Den Rest erledigt GitHub Actions (`.github/workflows/build.yml`):

- Jeder Push auf `main` baut die Exe auf einem Windows-Runner, führt das Skript testweise aus
  und stellt Exe und Test-Report unter *Actions* als Download bereit.
- Ein Release mit der Exe entsteht über *Actions → Build → Run workflow*: im Feld
  *Release anlegen* die Version eintragen, z. B. `0.8.0`. Sie muss zu `$ScriptVersion` in
  `Invoke-Inventur.ps1` passen, sonst bricht der Lauf ab. Ein gepushter Tag `v*` funktioniert ebenso.

## Datenschutz

Der Report enthält Seriennummern, Benutzernamen und den Entra-Mandanten. Er ist wie andere
Kundendokumentation zu behandeln. Produktschlüssel werden standardmäßig maskiert, und
erzeugte Reports (`Inventur_*`) sind per `.gitignore` vom Repo ausgeschlossen.

## Status

Version 0.8.2. Das Skript läuft bei jedem Build auf einem Windows-Server-Runner, ist aber noch nicht auf echten Windows-10/11-Rechnern getestet. Rückmeldungen von Testläufen unter
Windows 10 und 11 bitte als Issue.
