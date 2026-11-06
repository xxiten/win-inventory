# Changelog

Alle nennenswerten Änderungen an win-inventory. Die Versionen folgen
[Semantic Versioning](https://semver.org/lang/de/). Zum Format gehört auch die Gliederung
des Reports (Abschnitte und ihre Reihenfolge): Ab 1.0 ändert sie sich nur noch mit einer
neuen Hauptversion oder, wenn nur etwas dazukommt, mit einer neuen Nebenversion.

Der Release-Workflow übernimmt den Abschnitt der jeweiligen Version als Release-Notes.

## [0.9.2] – 2026-11-06

### Behoben
- Kunde, Station oder Techniker mit „-“ am Anfang brachen die Inventur ab. Die Werte gehen jetzt
  als Umgebungsvariablen an PowerShell, auch aus `Start-Inventur.cmd`; Anführungszeichen und
  Backslashes bleiben dabei unverändert.
- Eingaben nur aus Leerzeichen erzeugten eine leere Station in der Überschrift.
- Adapter ohne IPv4-Adresse zeigten „/“ in der IPv4-Spalte.
- Ein in Anführungszeichen eingefügter Ordner („Als Pfad kopieren“) galt als nicht beschreibbar.
- Fiel der Windows-Lizenzdienst aus, stand im Office-Abschnitt „Nicht verfügbar“ unter
  gültigen Microsoft-365-Daten.

### Geändert
- Der Lizenzdienst wird nur noch einmal abgefragt, das spart einige Sekunden je Inventur.

### Sicherheit
- `[` und `]` in Werten werden entschärft, damit sich keine Links oder Bilder in den Report
  einschleusen lassen (z. B. über Programmnamen, die jeder Benutzer setzen kann).
- Der geschützte Temp-Ordner gehört ausdrücklich den Administratoren.
- Die Versionsabfrage meldet sich nicht mehr mit dem Windows-Konto am Proxy an.

## [0.9.1] – 2026-11-06

### Neu
- Hinweis auf neue Versionen: Die Exe fragt beim Start im Hintergrund bei GitHub nach der
  neuesten Version. Gibt es eine neuere, erscheint oben im Fenster ein Hinweis mit
  „Herunterladen“ (lädt die neue `Inventur.exe` über den Browser) und „Was ist neu?“.
  Ohne Internet bleibt der Hinweis einfach aus. Inventurdaten werden dabei nicht übertragen.

## [0.9.0] – 2026-11-04

### Neu
- Abschnitt **Netzwerk**: alle Adapter mit Status, MAC-Adresse und Geschwindigkeit sowie die
  IP-Konfiguration der verbundenen Adapter (IPv4, DHCP, Gateway, DNS-Server, IPv6).
- Abschnitt **Microsoft 365 / Office**: Produkt, Version, Architektur, Update-Kanal und
  Lizenzart von Click-to-Run-Installationen sowie Dauerlizenzen (Office 2016–2024) mit Status.
- Automatische Tests (`tests\Invoke-Tests.ps1`): Hilfsfunktionen, feste Gliederung des
  Reports und die Exe. In CI läuft dabei eine komplette Inventur über die Exe mit Adminrechten.
- Dieser Changelog.

## [0.8.4] – 2026-11-04

### Neu
- Feld **Station** für einen sprechenden Namen des Arbeitsplatzes, z. B. „PC Sonja“. Steht in
  der Überschrift: „Inventur PC Sonja (RECHNER)“.

### Geändert
- Report-Kopf: Überschrift und Tabelle (Kunde, Station, Techniker, Datum, Version) statt
  YAML-Frontmatter, damit der Report in jedem Markdown-Viewer gut aussieht.
- Systemsprache ist die Installationssprache von Windows, nicht das Regionsformat.
- Gerätetyp erkennt Tablets und Server-Varianten.

### Behoben
- Firewall zeigt die tatsächlich wirksamen Einstellungen, auch aus Gruppenrichtlinien.
- Programme von Entra-ID-Benutzern fehlten.
- Markdown-Zeichen in Werten (z. B. `\\server`, `<Unknown>`, `*`) verfälschten die Anzeige.
- Exe im Hauptverzeichnis eines Laufwerks speicherte den Report im falschen Ordner.
- Backslash am Ende von Kunde oder Techniker brachte die Übergabe durcheinander.
- `Start-Inventur.cmd` hing in einer Schleife, wenn der Serverdienst deaktiviert ist.

### Sicherheit
- Das Skript liegt während des Laufs in einem Ordner, auf den nur Administratoren zugreifen.
- PowerShell lädt nur Systemmodule. Report, Ordner und Website öffnen ohne Adminrechte.

## [0.8.3] – 2026-11-04

### Neu
- Programmsymbol (Klemmbrett aus Microsoft Fluent UI Emoji).
- MIT-Lizenz.

### Entfernt
- Anleitung für HTML/PDF mit Pandoc und `report.css`: Das Tool erzeugt den Markdown-Report.

## [0.8.2] – 2026-11-04

### Neu
- Netixx-Branding: Titel „Netixx Windows Inventory“, Version und Copyright in der Fußzeile.

### Behoben
- Bei 125/150 % Anzeigeskalierung wuchs das Fenster nicht mit, Texte wurden abgeschnitten.

## [0.8.1] – 2026-11-04

### Behoben
- Die Exe startete nicht bei Regionsformaten ohne eigene Codepage, z. B. „Deutsch (Italien)“.

## [0.8.0] – 2026-11-04

Erste veröffentlichte Version: Inventur-Skript mit Markdown-Report, `Inventur.exe` mit
Oberfläche, `Start-Inventur.cmd` und Release per GitHub Actions.
