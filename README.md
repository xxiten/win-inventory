# Windows-Inventur

PowerShell-Skript, das einen Windows-10/11-Rechner inventarisiert und das Ergebnis als
Markdown-Report schreibt. Aus dem Report lässt sich mit Pandoc ein HTML- oder PDF-Dokument erzeugen.

- Läuft mit **Windows PowerShell 5.1**, das auf jedem Windows 10/11 vorinstalliert ist.
- Braucht **keine zusätzlichen Module** und **keine Internetverbindung**.
- Ändert nichts am System, das Skript liest nur.

## Inhalt des Reports

| Abschnitt | Inhalt |
|---|---|
| Übersicht | Hersteller, Modell, Seriennummer, UUID, Gerätetyp, Windows-Edition/-Version/-Build, Installationsdatum, Laufzeit, angemeldeter Benutzer |
| Hardware | CPU, RAM (Module, Slots, max. Ausbau), Mainboard, BIOS/UEFI, physische Datenträger (Typ, Bus, Zustand, Seriennr.), Laufwerke mit Füllstand |
| Peripherie & Grafik | Grafikkarten (echter VRAM, Treiber), Monitore (Hersteller, Modell, Seriennr., Baujahr), Drucker, Akku-Gesundheit |
| Sicherheit | TPM, Secure Boot, VBS/Credential Guard, BitLocker je Laufwerk, Virenschutz (Security Center + Defender-Details), Firewall-Profile, letzte Updates, ausstehender Neustart |
| Benutzer & Lizenz | AD-Domäne/Arbeitsgruppe, Entra-ID-Join, Mandant, MDM, lokale Benutzer, lokale Administratoren, Windows-Lizenz (Kanal, Status, Teil-Key) |
| Installierte Software | Klassische Programme (64/32 Bit, maschinenweit und pro Benutzer), Store-Apps ohne Systemkomponenten |

## Verwendung

**Einfachster Weg:** Den Ordner auf den Rechner kopieren (z. B. per USB-Stick) und
`Start-Inventur.cmd` doppelklicken. Windows fragt nach Administratorrechten, danach liegt
`Inventur_<RECHNER>_<Datum>.md` im selben Ordner.

**Manuell** in einer PowerShell, die als Administrator läuft:

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-Inventur.ps1 -Kunde "Muster GmbH"
```

| Parameter | Bedeutung |
|---|---|
| `-Kunde "Name"` | Kundenname im Report-Kopf |
| `-OutputPath <Datei oder Ordner>` | Ziel des Reports (Standard: Ordner des Skripts) |
| `-IncludeProductKey` | OEM-Key aus der Firmware vollständig ausgeben (Standard: nur die letzten 5 Zeichen) |
| `-NoStoreApps` | Store-Apps weglassen |

Ohne Administratorrechte läuft das Skript trotzdem durch. Dann fehlen aber u. a. BitLocker,
TPM, Secure Boot und die Store-Apps anderer Benutzer. Der Report weist oben darauf hin.

## Report zu HTML / PDF

Mit [Pandoc](https://pandoc.org/):

```bash
# HTML (eigenständige Datei, CSS eingebettet)
pandoc Inventur_PC01_2026-11-02.md -s --embed-resources --css report.css -o Inventur_PC01.html

# PDF über WeasyPrint (nutzt dasselbe CSS, kommt mit breiten Tabellen gut zurecht)
pandoc Inventur_PC01_2026-11-02.md -s --css report.css --pdf-engine=weasyprint -o Inventur_PC01.pdf
```

Ohne WeasyPrint geht es auch so: die HTML-Datei im Browser öffnen und über *Drucken → Als PDF
speichern* ausgeben. `report.css` enthält dafür passende Druckregeln (A4, Seitenzahlen,
wiederholte Tabellenköpfe).

Der LaTeX-Weg von Pandoc (`-o report.pdf` ohne `--pdf-engine`) funktioniert ebenfalls,
bricht aber lange Softwarelisten und breite Tabellen weniger schön um.

## Datenschutz

Der Report enthält Seriennummern, Benutzernamen und den Entra-Mandanten. Er sollte deshalb
wie andere Kundendokumentation behandelt werden. Produktschlüssel werden standardmäßig maskiert.
