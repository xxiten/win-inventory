# win-inventory

Inventur für Windows-10/11-Rechner per PowerShell. Das Skript erfasst Hardware, Sicherheit,
Benutzer, Lizenz und installierte Software und schreibt alles in einen sauberen Markdown-Report.

- Läuft mit **Windows PowerShell 5.1**, das auf jedem Windows 10/11 vorinstalliert ist.
- Braucht **keine Installation, keine Module und kein Internet**.
- **Liest nur** und ändert nichts am System.

## Schnellstart mit Inventur.exe

1. **[Inventur.exe herunterladen](https://github.com/xxiten/win-inventory/releases/latest/download/Inventur.exe)**
   (immer die neueste Version, ältere unter [Releases](https://github.com/xxiten/win-inventory/releases))
   und auf den Zielrechner kopieren, z. B. per USB-Stick.
2. Doppelklicken und die Abfrage nach Administratorrechten bestätigen.
3. **Kunde**, bei Bedarf **Station** (z. B. „PC Sonja“ oder „Empfang 1“) und **Techniker** eintragen.
   Der Techniker wird für den nächsten Start gemerkt.
4. Bei Bedarf Zielordner und Optionen anpassen, dann *Inventur starten*.
5. Nach etwa einer Minute ist der Report fertig. *Report öffnen* bzw. *Ordner öffnen* führen direkt hin.

Standard-Zielordner ist der Ordner der Exe, also z. B. der USB-Stick. Ist der schreibgeschützt,
wird der Desktop vorgeschlagen. Der Dateiname ist `Inventur_<RECHNER>_<Datum>.md`.

Ganz oben im Report stehen die **Befunde**: was der Techniker angehen sollte, etwa Windows 10
ohne Updates (mit der Angabe, ob Windows 11 möglich ist), ein Notebook ohne BitLocker, fehlender
Virenschutz, eine volle Platte oder Bluescreens.

**Mehrere Rechner eines Kunden:** Mit dem USB-Stick von PC zu PC gehen und überall denselben
Kunden eintragen. Ab dem zweiten Rechner liegt auf dem Stick zusätzlich
`Sammelbericht_<Kunde>.md`: eine Tabelle aller Rechner mit Modell, CPU, RAM, Windows,
Windows-11-Tauglichkeit und Anzahl der Befunde, darunter die Befunde je Rechner. Er wird bei
jeder Inventur neu geschrieben, je Rechner zählt der neueste Report.

Gibt es eine neuere Version, zeigt die Exe oben einen gelben Hinweis. *Herunterladen* lädt die
neue `Inventur.exe` über den Browser, *Was ist neu?* öffnet die Release-Notes. Ohne Internet
erscheint einfach kein Hinweis.

> Die Exe ist **nicht digital signiert**. Windows zeigt deshalb bei der UAC-Abfrage
> „Unbekannter Herausgeber“, und SmartScreen kann beim ersten Start warnen
> (*Weitere Informationen → Trotzdem ausführen*). Mit einem Code-Signing-Zertifikat
> verschwinden beide Hinweise.

**Ohne Exe:** Repo als ZIP herunterladen und `Start-Inventur.cmd` doppelklicken. Der Starter
fragt im Konsolenfenster nach Kunde und Station.

## Dateien

| Datei | Zweck |
|---|---|
| `Invoke-Inventur.ps1` | Das Inventur-Skript, steckt auch eingebettet in der Exe |
| `src/InventurLauncher.cs` | Quellcode der Exe (Oberfläche, startet das eingebettete Skript) |
| `src/app.manifest` | Manifest der Exe: fordert Adminrechte an |
| `src/app.ico` | Programmsymbol der Exe (16–256 px) |
| `build.ps1` | Baut `dist\Inventur.exe` |
| `Start-Inventur.cmd` | Alternative ohne Exe: holt Adminrechte, fragt nach Kunde und Station und startet das Skript |
| `tests/` | Automatische Tests (`Invoke-Tests.ps1`, dazu `LauncherTests.cs` für die Exe) |
| `CHANGELOG.md` | Änderungen je Version; daraus entstehen die Release-Notes |

## Was erfasst wird

| Abschnitt | Inhalt |
|---|---|
| Befunde | Kritisch: Windows 10 ohne ESU (mit Windows-11-Tauglichkeit), Office 2016/2019/2021, kein aktiver Virenschutz, defekter Datenträger, Notebook ohne BitLocker. Warnung: BitLocker aus, alte Signaturen, Firewall aus, Update älter als 45 Tage, Gastkonto, Laufwerk unter 10 % frei, Akku unter 60 %, Bluescreens, Datenträgerfehler, gehäufte Abschaltungen |
| Übersicht | Hersteller, Modell, Seriennummer, UUID, Gerätetyp, CPU, RAM, Windows-Edition, -Version und -Build, unter Windows 10 die Windows-11-Tauglichkeit, Installationsdatum, Laufzeit, angemeldeter Benutzer |
| Hardware | CPU, RAM (Module, belegte Slots, max. Ausbau), Mainboard, BIOS/UEFI, physische Datenträger (Typ, Bus, Zustand, Seriennummer), Laufwerke mit Füllstand, Stabilität (Bluescreens, unerwartete Abschaltungen, Datenträgerfehler der letzten 30 Tage) |
| Peripherie & Grafik | Grafikkarten (Speicher, Treiber, Auflösung), Monitore (Hersteller, Modell, Seriennummer, Baujahr), Drucker, Akku-Gesundheit |
| Netzwerk | Adapter (Status, MAC-Adresse, Geschwindigkeit), IP-Konfiguration der verbundenen Adapter (IPv4, DHCP, Gateway, DNS-Server, IPv6) |
| Sicherheit | TPM, Secure Boot, VBS/Credential Guard, BitLocker je Laufwerk, Virenschutz und Defender-Details, Firewall-Profile, letzte Updates, ausstehender Neustart |
| Benutzer & Lizenz | AD-Domäne oder Arbeitsgruppe, Entra-ID-Beitritt mit Mandant, MDM/Intune, lokale Benutzer und Administratoren, Windows-Lizenz (Kanal, Status, maskierter Schlüssel) |
| Installierte Software | Microsoft 365 / Office (Produkt, Version, Update-Kanal, Lizenzart), klassische Programme (64/32 Bit, maschinenweit und pro Benutzer) und Store-Apps, jeweils ohne Systemkomponenten |

Kann ein Abschnitt nicht gelesen werden, steht im Report *Nicht verfügbar* mit dem Grund,
und das Skript läuft weiter.

## Aufruf mit Parametern

Ohne Oberfläche, z. B. für eigene Automatisierung, lässt sich das Skript direkt in einer
PowerShell aufrufen, die als Administrator läuft:

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-Inventur.ps1 -Kunde "Muster GmbH" -Station "Empfang 1" -Techniker "Max Mustermann"
```

| Parameter | Bedeutung |
|---|---|
| `-Kunde "Name"` | Kundenname im Report-Kopf; Grundlage für den Sammelbericht im Zielordner |
| `-Station "Name"` | Sprechender Name des Arbeitsplatzes, z. B. „PC Sonja“; steht in der Überschrift vor dem Rechnernamen |
| `-Techniker "Name"` | Name des Technikers im Report-Kopf |
| `-OutputPath <Datei oder Ordner>` | Ziel des Reports (Standard: Ordner des Skripts) |
| `-IncludeProductKey` | OEM-Schlüssel aus der Firmware vollständig ausgeben (Standard: nur die letzten 5 Zeichen) |
| `-NoStoreApps` | Store-Apps weglassen |

Ohne Administratorrechte läuft das Skript ebenfalls durch. Dann fehlen aber u. a. BitLocker,
TPM, Secure Boot und die Store-Apps anderer Benutzer. Der Report weist oben darauf hin.

## Exe bauen

Auf jedem Windows-Rechner, ohne Visual Studio oder .NET SDK:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

`build.ps1` nutzt den in Windows enthaltenen C#-Compiler des .NET Framework 4.x und bettet
`Invoke-Inventur.ps1` in die Exe ein. Änderungen am Skript landen also erst nach einem neuen
Build in der Exe.

Tests, ohne Zusatzmodule. Mit Adminrechten gestartet, läuft dabei auch eine komplette Inventur
über die Exe:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Invoke-Tests.ps1
```

Den Rest erledigt GitHub Actions (`.github/workflows/build.yml`):

- Jeder Push auf `main` baut die Exe auf einem Windows-Runner, führt das Skript und die Tests
  aus und stellt Exe und Test-Report unter *Actions* als Download bereit.
- Ein Release mit der Exe entsteht über *Actions → Build → Run workflow*: im Feld
  *Release anlegen* die Version eintragen, z. B. `0.9.0`. Sie muss zu `$ScriptVersion` in
  `Invoke-Inventur.ps1` passen, und `CHANGELOG.md` braucht einen Abschnitt dafür. Der wird
  zu den Release-Notes. Ein gepushter Tag `v*` funktioniert ebenso.

## Datenschutz

Der Report enthält Seriennummern, Benutzernamen und den Entra-Mandanten. Er ist wie andere
Kundendokumentation zu behandeln. Produktschlüssel werden standardmäßig maskiert, und
erzeugte Reports (`Inventur_*`, `Sammelbericht_*`) sind per `.gitignore` vom Repo ausgeschlossen.

Das Tool überträgt keine Inventurdaten. Die einzige Netzwerkverbindung ist die Versionsabfrage
der Exe beim Start: ein Abruf der Release-Liste bei GitHub, wie ein Browseraufruf. GitHub sieht
dabei nur die öffentliche IP-Adresse des Standorts.

## Status

Aktuelle Version siehe [Releases](https://github.com/xxiten/win-inventory/releases), Änderungen
im [CHANGELOG](CHANGELOG.md). Getestet bei jedem Build auf einem Windows-Server-Runner und auf
zwei Windows-11-Rechnern. Vor 1.0 stehen noch Testläufe unter Windows 10, auf Entra-ID-Rechnern
und auf Notebooks mit BitLocker aus. Rückmeldungen bitte als Issue.

## Lizenz

MIT, siehe [LICENSE](LICENSE). Das Programmsymbol `src/app.ico` stammt aus
[Fluent UI Emoji](https://github.com/microsoft/fluentui-emoji) von Microsoft und steht ebenfalls
unter MIT-Lizenz, siehe [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
