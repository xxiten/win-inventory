# win-inventory

Inventur für Windows-10/11-Rechner per PowerShell. Das Skript erfasst Hardware, Sicherheit,
Benutzer, Lizenz und installierte Software und schreibt alles in einen Markdown-Report. Daraus
wird mit Pandoc ein sauberer HTML- oder PDF-Bericht für den Kunden.

- Läuft mit **Windows PowerShell 5.1**, das auf jedem Windows 10/11 vorinstalliert ist.
- Braucht **keine Installation, keine Module und kein Internet**.
- **Liest nur** und ändert nichts am System.

## Schnellstart

1. Repo als ZIP herunterladen (*Code → Download ZIP*) und auf den Zielrechner kopieren, z. B. per USB-Stick.
2. ZIP entpacken und **`Start-Inventur.cmd`** doppelklicken.
3. Die Abfrage nach Administratorrechten bestätigen.
4. Kundennamen eingeben, oder mit Enter ohne Kundennamen fortfahren.
5. Der Report liegt danach im selben Ordner als `Inventur_<RECHNER>_<Datum>.md`.

> Warnt Windows SmartScreen beim Start, weil die Datei aus dem Internet stammt:
> *Weitere Informationen → Trotzdem ausführen*, oder vorher in den Dateieigenschaften
> der ZIP-Datei *Zulassen* anhaken.

## Dateien

| Datei | Zweck |
|---|---|
| `Invoke-Inventur.ps1` | Das Inventur-Skript |
| `Start-Inventur.cmd` | Starter per Doppelklick: holt Adminrechte, fragt nach dem Kundennamen und startet das Skript |
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

Für alle Optionen das Skript direkt in einer PowerShell aufrufen, die als Administrator läuft:

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-Inventur.ps1 -Kunde "Muster GmbH"
```

| Parameter | Bedeutung |
|---|---|
| `-Kunde "Name"` | Kundenname im Report-Kopf |
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

## Datenschutz

Der Report enthält Seriennummern, Benutzernamen und den Entra-Mandanten. Er ist wie andere
Kundendokumentation zu behandeln. Produktschlüssel werden standardmäßig maskiert, und
erzeugte Reports (`Inventur_*`) sind per `.gitignore` vom Repo ausgeschlossen.

## Status

Version 1.0.0. Noch nicht auf echten Rechnern getestet. Rückmeldungen von Testläufen unter
Windows 10 und 11 bitte als Issue.
