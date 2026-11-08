<#
.SYNOPSIS
    Inventur eines Windows-10/11-Rechners als Markdown-Report.

.DESCRIPTION
    Sammelt Hardware, Betriebssystem, Sicherheit, Peripherie, Benutzer/Lizenz und
    installierte Software (klassisch + Store) und schreibt einen Markdown-Report.
    Oben im Report stehen die Befunde (Kritisch/Warnung), die sich daraus ergeben.

    Läuft mit Windows PowerShell 5.1 (Bordmittel), keine zusätzlichen Module.
    Als Administrator ausfuehren - sonst fehlen u. a. BitLocker, TPM, Secure Boot
    und die Store-Apps aller Benutzer (der Report vermerkt das).

.PARAMETER OutputPath
    Zieldatei oder Zielordner. Standard: Ordner des Skripts,
    Dateiname Inventur_<RECHNER>_<yyyy-MM-dd>.md

.PARAMETER Kunde
    Optionaler Kundenname für den Report-Kopf. Liegen im Zielordner Reports von mindestens
    zwei Rechnern dieses Kunden, entsteht dort zusätzlich Sammelbericht_<Kunde>.md.

.PARAMETER Station
    Optionaler sprechender Name des Arbeitsplatzes, z. B. "PC Sonja" oder
    "Empfang 1". Steht in der Überschrift vor dem Rechnernamen.

.PARAMETER Techniker
    Optionaler Name des Technikers, der die Inventur durchführt.

.PARAMETER IncludeProductKey
    Gibt den im Firmware hinterlegten OEM-Produktschlüssel vollständig aus.
    Standard: nur die letzten 5 Zeichen.

.PARAMETER NoStoreApps
    Store-/Appx-Apps nicht auflisten.

.EXAMPLE
    .\Invoke-Inventur.ps1 -Kunde "Muster GmbH" -Station "Empfang 1" -Techniker "Max Mustermann"
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$Kunde,
    [string]$Station,
    [string]$Techniker,
    [switch]$IncludeProductKey,
    [switch]$NoStoreApps
)


$ErrorActionPreference = 'Stop'
$ScriptVersion = '0.10.0'

# Eingaben nur aus Leerzeichen zählen als leer (z. B. aus Start-Inventur.cmd)
$Kunde = "$Kunde".Trim()
$Station = "$Station".Trim()
$Techniker = "$Techniker".Trim()

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

$script:md = New-Object System.Collections.Generic.List[string]
$script:hinweise = New-Object System.Collections.Generic.List[string]
$script:befunde = New-Object System.Collections.Generic.List[object]

function Add-Line { param([string]$Text = '') $script:md.Add($Text) }

function Add-Befund {
    # Für den Abschnitt "Befunde" oben im Report. Text ohne Markdown, er wird dort entschärft.
    param([ValidateSet('Kritisch', 'Warnung')][string]$Stufe, [string]$Text)
    if (-not ($script:befunde | Where-Object { $_.Text -eq $Text })) {
        $script:befunde.Add([pscustomobject]@{ Stufe = $Stufe; Text = $Text })
    }
}

function ConvertTo-MdCell {
    # Wert für eine Tabellenzelle: einzeilig, Markdown-Sonderzeichen entschärft
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToString('dd.MM.yyyy HH:mm') }
    if ($Value -is [bool]) { if ($Value) { return 'Ja' } else { return 'Nein' } }
    $s = ([string]$Value -replace '[\r\n]+', ' ').Trim()
    # Backslash nur vor Satzzeichen verdoppeln, sonst verschluckt Markdown ihn (\\server).
    # "DOMÄNE\Benutzer" bleibt so lesbar.
    $s = $s -replace '\\(?=[!-/:-@\[-`{-~])', '\\'
    # Zeichen, die Tabellenspalten, Hervorhebung, Code, HTML, Links oder Bilder auslösen.
    # Programmnamen u. ä. kann jeder Benutzer setzen; ohne [ ] ließen sich Links einschleusen.
    return $s -replace '([|*_`<\[\]])', '\$1'
}

function Add-KeyValueTable {
    # Zwei-Spalten-Tabelle aus geordneter Hashtable
    param([System.Collections.IDictionary]$Data)
    Add-Line '| Eigenschaft | Wert |'
    Add-Line '|---|---|'
    foreach ($k in $Data.Keys) {
        Add-Line ('| {0} | {1} |' -f (ConvertTo-MdCell $k), (ConvertTo-MdCell $Data[$k]))
    }
    Add-Line
}

function Add-Table {
    # Tabelle aus Objekten; Columns = geordnete Hashtable Überschrift -> Property/Scriptblock
    param(
        [object[]]$Rows,
        [System.Collections.IDictionary]$Columns,
        [string]$Empty = '_Keine Einträge gefunden._'
    )
    $Rows = @($Rows | Where-Object { $null -ne $_ })
    if ($Rows.Count -eq 0) { Add-Line $Empty; Add-Line; return }
    Add-Line ('| ' + (($Columns.Keys | ForEach-Object { ConvertTo-MdCell $_ }) -join ' | ') + ' |')
    Add-Line ('|' + (($Columns.Keys | ForEach-Object { '---' }) -join '|') + '|')
    foreach ($r in $Rows) {
        $cells = foreach ($h in $Columns.Keys) {
            $sel = $Columns[$h]
            if ($sel -is [scriptblock]) { $v = & $sel $r } else { $v = $r.$sel }
            ConvertTo-MdCell $v
        }
        Add-Line ('| ' + ($cells -join ' | ') + ' |')
    }
    Add-Line
}

function Invoke-Section {
    # Führt einen Abschnitt aus; Fehler werden im Report vermerkt statt abzubrechen
    param([string]$Title, [scriptblock]$Body, [int]$Level = 2)
    Add-Line ('{0} {1}' -f ('#' * $Level), $Title)
    Add-Line
    Write-Host "  - $Title"
    try { & $Body }
    catch {
        Add-Line ('_Nicht verfügbar: {0}_' -f (ConvertTo-MdCell $_.Exception.Message))
        Add-Line
    }
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -le 0) { return '' }
    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt $units.Count - 1) { $Bytes /= 1024; $i++ }
    return ('{0:N1} {1}' -f $Bytes, $units[$i])
}

function Get-Cim {
    param([string]$Class, [string]$Namespace = 'root\cimv2', [string]$Filter)
    $p = @{ ClassName = $Class; Namespace = $Namespace; ErrorAction = 'Stop' }
    if ($Filter) { $p.Filter = $Filter }
    Get-CimInstance @p
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}

function ConvertFrom-WmiString {
    # WmiMonitorID liefert Strings als UInt16-Arrays
    param($Array)
    if (-not $Array) { return '' }
    (($Array | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '').Trim()
}

function Get-YesNo { param($Value) if ($null -eq $Value) { 'unbekannt' } elseif ($Value) { 'Ja' } else { 'Nein' } }

function Read-MdReport {
    # Liest Kopf, Übersicht und Befunde eines Reports dieses Skripts (für den Sammelbericht).
    # Tabellenzellen sind mit " | " getrennt, ein "|" im Wert steht als "\|" da.
    # Die Werte bleiben entschärft und gehen so in den Sammelbericht.
    param([string]$Path)
    $lines = [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)
    if ($lines.Count -lt 5 -or $lines[0] -notlike '# Inventur *' -or $lines[2] -notlike '| * |' -or $lines[4] -notlike '| * |') { return }
    $zellen = { param($l) @($l.Substring(2, $l.Length - 4) -split ' \| ') }
    $werte = @{}
    $kopf = & $zellen $lines[2]; $kopfWerte = & $zellen $lines[4]
    for ($i = 0; $i -lt $kopf.Count; $i++) { $werte[$kopf[$i]] = $kopfWerte[$i] }
    $befunde = $null; $abschnitt = ''
    foreach ($l in $lines) {
        if ($l -like '## *') {
            $abschnitt = $l.Substring(3)
            if ($abschnitt -eq 'Befunde') { $befunde = New-Object System.Collections.Generic.List[string] }
        }
        elseif ($abschnitt -eq 'Übersicht' -and $l -like '| * |') {
            $kv = & $zellen $l
            if ($kv.Count -eq 2) { $werte[$kv[0]] = $kv[1] }
        }
        elseif ($abschnitt -eq 'Befunde' -and $l -like '- *') { $befunde.Add($l) }
    }
    [pscustomobject]@{ Titel = $lines[0].Substring(11); Werte = $werte; Befunde = $befunde }
}

function Write-Sammelbericht {
    # Fasst die Reports eines Kunden in einem Ordner zusammen, je Rechner den neuesten.
    # Gibt den Pfad zurück; bei weniger als zwei Rechnern entsteht nichts.
    param([string]$Ordner, [string]$Kunde)
    $kundeMd = ConvertTo-MdCell $Kunde
    $neueste = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $Ordner -Filter 'Inventur_*.md' -File | Sort-Object LastWriteTime)) {
        $r = Read-MdReport $f.FullName
        if ($r -and $r.Werte['Kunde'] -eq $kundeMd -and $r.Werte['Rechnername']) { $neueste[$r.Werte['Rechnername']] = $r }
    }
    if ($neueste.Count -lt 2) { return }
    $reports = @($neueste.Values | Sort-Object { $_.Werte['Station'] }, { $_.Werte['Rechnername'] })
    # Reports vor 0.10.0 haben keine Befunde: Anzahl dann leer statt 0
    $anzahl = { param($r, $stufe) if ($null -ne $r.Befunde) { @(@($r.Befunde) -match ('^- \*\*{0}:' -f $stufe)).Count } }

    $zeilen = New-Object System.Collections.Generic.List[string]
    $zeilen.Add("# Sammelbericht $kundeMd")
    $zeilen.Add('')
    $zeilen.Add(('{0} Rechner, davon {1} mit kritischen Befunden und {2} ohne Upgrade-Möglichkeit auf Windows 11.' -f $reports.Count,
        @($reports | Where-Object { (& $anzahl $_ 'Kritisch') -gt 0 }).Count,
        @($reports | Where-Object { $_.Werte['Windows-11-Upgrade'] -like 'nicht möglich*' }).Count))
    $zeilen.Add('')
    $zeilen.Add('| Station | Rechner | Modell | Prozessor | RAM | Windows | Windows 11 | Kritisch | Warnungen | Erfasst am |')
    $zeilen.Add('|---|---|---|---|---|---|---|---|---|---|')
    foreach ($r in $reports) {
        $w = $r.Werte
        $modell = if ($w['Modellbezeichnung']) { $w['Modellbezeichnung'] } else { $w['Modell'] }
        $win11 = if ($w['Betriebssystem'] -like '*Windows 11*') { 'installiert' } else { $w['Windows-11-Upgrade'] }
        $zellen = @($w['Station'], $w['Rechnername'], "$($w['Hersteller']) $modell".Trim(), $w['Prozessor'], $w['Arbeitsspeicher'],
            ("$($w['Betriebssystem']) $($w['Version'])" -replace '^Microsoft ', '').Trim(), $win11,
            (& $anzahl $r 'Kritisch'), (& $anzahl $r 'Warnung'), $w['Erfasst am'])
        $zeilen.Add('| ' + ($zellen -join ' | ') + ' |')
    }
    $zeilen.Add('')
    $mitBefunden = @($reports | Where-Object { $_.Befunde.Count -gt 0 })
    if ($mitBefunden.Count -gt 0) {
        $zeilen.Add('## Befunde')
        $zeilen.Add('')
        foreach ($r in $mitBefunden) { $zeilen.Add("### $($r.Titel)"); $zeilen.Add(''); $zeilen.AddRange($r.Befunde); $zeilen.Add('') }
    }
    $pfad = Join-Path $Ordner ('Sammelbericht_{0}.md' -f ($Kunde -replace '[\x00-\x1f\\/:*?"<>|]', '_').TrimEnd('. '))
    [IO.File]::WriteAllLines($pfad, $zeilen, (New-Object System.Text.UTF8Encoding($false)))
    $pfad
}

# ---------------------------------------------------------------------------
# Vorbereitung
# ---------------------------------------------------------------------------

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $script:hinweise.Add('Das Skript lief **ohne Administratorrechte**. BitLocker, TPM, Secure Boot, Akku-Details und Store-Apps anderer Benutzer können fehlen.')
    Write-Warning 'Keine Administratorrechte - einige Abschnitte bleiben unvollständig.'
}

$now = Get-Date
$cs = Get-Cim Win32_ComputerSystem
$os = Get-Cim Win32_OperatingSystem
$bios = Get-Cim Win32_BIOS
$csp = $null; try { $csp = Get-Cim Win32_ComputerSystemProduct } catch { }

# Windows- und Office-Lizenzen stehen im selben Lizenzdienst. Die Abfrage dauert mehrere
# Sekunden, daher einmal für beide Abschnitte; ein Fehler wird dort gemeldet.
$lizenzen = $null; $lizenzFehler = $null
try { $lizenzen = @(Get-Cim SoftwareLicensingProduct -Filter 'PartialProductKey IS NOT NULL') }
catch { $lizenzFehler = $_.Exception.Message }
$lizenzStatus = @{ 0 = 'Nicht lizenziert'; 1 = 'Aktiviert'; 2 = 'Kulanzzeit (OOB)'; 3 = 'Kulanzzeit (OOT)'; 4 = 'Nicht-Original-Kulanz'; 5 = 'Benachrichtigung'; 6 = 'Erweiterte Kulanz' }

if (-not $OutputPath) { $OutputPath = $PSScriptRoot }
if (-not $OutputPath) { $OutputPath = (Get-Location).Path }
# Wie PowerShell auflösen (relativ zum aktuellen Ordner, "~"); das Schreiben über .NET
# kennt nur den Prozessordner und würde sonst woanders landen.
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath -PathType Container) {
    $OutputPath = Join-Path $OutputPath ('Inventur_{0}_{1}.md' -f $env:COMPUTERNAME, $now.ToString('yyyy-MM-dd'))
}

Write-Host "Inventur von $env:COMPUTERNAME ..."

# ---------------------------------------------------------------------------
# Kopf: Überschrift und Eckdaten der Inventur
# ---------------------------------------------------------------------------

$titel = if ($Station) { '{0} ({1})' -f (ConvertTo-MdCell $Station), $env:COMPUTERNAME } else { $env:COMPUTERNAME }
Add-Line "# Inventur $titel"
Add-Line
$kopf = [ordered]@{}
if ($Kunde) { $kopf['Kunde'] = $Kunde }
if ($Station) { $kopf['Station'] = $Station }
if ($Techniker) { $kopf['Techniker'] = $Techniker }
$kopf['Erfasst am'] = $now
$kopf['Skriptversion'] = $ScriptVersion
$kopfSpalten = [ordered]@{}
foreach ($k in $kopf.Keys) { $kopfSpalten[$k] = $k }
Add-Table @([pscustomobject]$kopf) $kopfSpalten

$headerIndex = $script:md.Count   # Hinweise werden später hier eingefügt

# ---------------------------------------------------------------------------
# Übersicht
# ---------------------------------------------------------------------------

Invoke-Section 'Übersicht' {
    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = '{0}.{1}' -f (Get-RegValue $cv 'CurrentBuild'), (Get-RegValue $cv 'UBR')
    $displayVersion = Get-RegValue $cv 'DisplayVersion'
    if (-not $displayVersion) { $displayVersion = Get-RegValue $cv 'ReleaseId' }
    $uptime = $now - $os.LastBootUpTime

    $data = [ordered]@{}
    $data['Rechnername']        = $env:COMPUTERNAME
    $data['Hersteller']         = $cs.Manufacturer
    $data['Modell']             = $cs.Model
    if ($csp -and $csp.Version -and $csp.Version -notmatch 'System Version|To be filled') { $data['Modellbezeichnung'] = $csp.Version }
    $data['Seriennummer']       = $bios.SerialNumber
    if ($csp -and $csp.UUID) { $data['UUID'] = $csp.UUID }
    # PCSystemTypeEx statt PCSystemType: nur dort steht 8 für Tablet (Slate)
    $data['Gerätetyp']         = switch ($cs.PCSystemTypeEx) {
        1 { 'Desktop' } 2 { 'Notebook' } 3 { 'Workstation' } { $_ -in 4, 5, 7 } { 'Server' }
        6 { 'Appliance' } 8 { 'Tablet' } default { 'unbekannt' }
    }
    $data['Prozessor']          = $(try { (@(Get-Cim Win32_Processor)[0]).Name.Trim() } catch { $null })
    $data['Arbeitsspeicher']    = Format-Bytes $cs.TotalPhysicalMemory
    $data['Betriebssystem']     = $os.Caption
    $data['Version']            = $displayVersion
    # Windows 10 bekommt seit 14.10.2025 keine Updates mehr, außer mit ESU (LTSC hat eigene Fristen).
    # Ob Windows 11 geht, bewertet Windows selbst in der Kompatibilitätsprüfung; die neueste zählt.
    if ($os.Caption -match 'Windows 10' -and $os.Caption -notmatch 'LTS') {
        $upgrade = 'unbekannt'
        $ind = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators' -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object { $_.PSObject.Properties['UpgEx'] } |
            Sort-Object { [int64]$_.Timestamp } | Select-Object -Last 1
        if ($ind -and $ind.UpgEx -in 'Green', 'Yellow') { $upgrade = 'möglich' }
        elseif ($ind -and $ind.UpgEx -eq 'Red') {
            $gruende = @(@($ind.RedReason) -split '[\s,;]+' | Where-Object { $_ -and $_ -ne 'None' } | ForEach-Object {
                switch -Regex ($_) { '^Cpu' { 'Prozessor' } '^Tpm' { 'TPM 2.0' } 'SecureBoot|Uefi' { 'Secure Boot' }
                                     'Memory' { 'Arbeitsspeicher' } 'SystemDrive' { 'Speicherplatz' } default { $_ } }
            } | Select-Object -Unique)
            $upgrade = 'nicht möglich'
            if ($gruende) { $upgrade += ' ({0})' -f ($gruende -join ', ') }
        }
        $data['Windows-11-Upgrade'] = $upgrade
        if (@($lizenzen | Where-Object { $_.Name -match '\bESU\b' -and $_.LicenseStatus -eq 1 }).Count -gt 0) {
            Add-Befund 'Warnung' "Windows 10 bekommt nur noch über ESU Sicherheitsupdates. Upgrade auf Windows 11: $upgrade."
        } else {
            Add-Befund 'Kritisch' "Windows 10 bekommt seit 14.10.2025 keine Sicherheitsupdates mehr. Upgrade auf Windows 11: $upgrade."
        }
    }
    $data['Build']              = $build
    $data['Architektur']        = $os.OSArchitecture
    # Installationssprache von Windows, nicht das Regionsformat des ausführenden Kontos
    $data['Systemsprache']      = $(try { [Globalization.CultureInfo]::GetCultureInfo([int]$os.OSLanguage).Name } catch { "$($os.OSLanguage)" })
    $data['Installiert am']     = $os.InstallDate
    $data['Letzter Start']      = $os.LastBootUpTime
    $data['Laufzeit']           = '{0} Tage {1} Std.' -f $uptime.Days, $uptime.Hours
    $data['Angemeldeter Benutzer'] = $cs.UserName
    $data['Ausgeführt als']     = '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME
    Add-KeyValueTable $data
}

# ---------------------------------------------------------------------------
# Hardware
# ---------------------------------------------------------------------------

Add-Line '## Hardware'
Add-Line

Invoke-Section 'Prozessor' -Level 3 {
    Add-Table (Get-Cim Win32_Processor) ([ordered]@{
        'Modell'    = { param($p) $p.Name.Trim() }
        'Kerne'     = 'NumberOfCores'
        'Threads'   = 'NumberOfLogicalProcessors'
        'Max. Takt' = { param($p) '{0:N2} GHz' -f ($p.MaxClockSpeed / 1000) }
        'Sockel'    = 'SocketDesignation'
    })
}

Invoke-Section 'Arbeitsspeicher' -Level 3 {
    $mods = @(Get-Cim Win32_PhysicalMemory)
    $arrays = @(Get-Cim Win32_PhysicalMemoryArray)
    $slots = ($arrays | Measure-Object -Property MemoryDevices -Sum).Sum
    $maxKb = ($arrays | Measure-Object -Property MaxCapacity -Sum).Sum
    Add-KeyValueTable ([ordered]@{
        'Gesamt'         = Format-Bytes $cs.TotalPhysicalMemory
        'Belegte Slots'  = '{0} von {1}' -f $mods.Count, $slots
        'Max. Ausbau'    = if ($maxKb) { Format-Bytes ($maxKb * 1KB) } else { 'unbekannt' }
    })
    Add-Table $mods ([ordered]@{
        'Slot'        = 'DeviceLocator'
        'Größe'     = { param($m) Format-Bytes $m.Capacity }
        'Takt'        = { param($m) if ($m.Speed) { "$($m.Speed) MT/s" } }
        'Hersteller'  = 'Manufacturer'
        'Teilenummer' = { param($m) "$($m.PartNumber)".Trim() }
        'Seriennummer'= 'SerialNumber'
    })
}

Invoke-Section 'Mainboard & Firmware' -Level 3 {
    $bb = Get-Cim Win32_BaseBoard
    $fw = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control' 'PEFirmwareType'
    $fwText = switch ($fw) { 1 { 'Legacy BIOS' } 2 { 'UEFI' } default { $null } }
    if (-not $fwText) {
        # Fallback: Confirm-SecureBootUEFI gibt es nur auf UEFI-Systemen
        try { Confirm-SecureBootUEFI -ErrorAction Stop | Out-Null; $fwText = 'UEFI' }
        catch [System.PlatformNotSupportedException] { $fwText = 'Legacy BIOS' }
        catch { $fwText = 'unbekannt' }
    }
    Add-KeyValueTable ([ordered]@{
        'Mainboard-Hersteller' = $bb.Manufacturer
        'Mainboard-Modell'     = $bb.Product
        'Mainboard-Seriennr.'  = $bb.SerialNumber
        'BIOS-Hersteller'      = $bios.Manufacturer
        'BIOS-Version'         = $bios.SMBIOSBIOSVersion
        'BIOS-Datum'           = $(if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('dd.MM.yyyy') })
        'Firmware-Modus'       = $fwText
    })
}

Invoke-Section 'Datenträger' -Level 3 {
    $disks = $null
    try { $disks = @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object DeviceId) } catch { }
    if ($disks) {
        Add-Table $disks ([ordered]@{
            'Nr.'          = 'DeviceId'
            'Modell'       = 'FriendlyName'
            'Typ'          = 'MediaType'
            'Bus'          = 'BusType'
            'Größe'      = { param($d) Format-Bytes $d.Size }
            'Zustand'      = 'HealthStatus'
            'Seriennummer' = { param($d) "$($d.SerialNumber)".Trim() }
        })
        foreach ($d in $disks) {
            if ("$($d.HealthStatus)" -in 'Warning', 'Unhealthy') {
                Add-Befund 'Kritisch' ('Datenträger {0} meldet den Zustand {1}.' -f $d.FriendlyName, $d.HealthStatus)
            }
        }
    } else {
        Add-Table (Get-Cim Win32_DiskDrive) ([ordered]@{
            'Modell'       = 'Model'
            'Schnittstelle'= 'InterfaceType'
            'Größe'      = { param($d) Format-Bytes $d.Size }
            'Seriennummer' = { param($d) "$($d.SerialNumber)".Trim() }
        })
    }

    Add-Line '**Laufwerke**'
    Add-Line
    $volumes = @(Get-Cim Win32_LogicalDisk -Filter 'DriveType=3')
    Add-Table $volumes ([ordered]@{
        'Laufwerk'    = 'DeviceID'
        'Bezeichnung' = 'VolumeName'
        'Dateisystem' = 'FileSystem'
        'Größe'     = { param($v) Format-Bytes $v.Size }
        'Frei'        = { param($v) Format-Bytes $v.FreeSpace }
        'Frei %'      = { param($v) if ($v.Size) { '{0:N0} %' -f ($v.FreeSpace / $v.Size * 100) } }
    })
    foreach ($v in $volumes) {
        if ($v.Size -and $v.FreeSpace / $v.Size -lt 0.1) {
            Add-Befund 'Warnung' ('Laufwerk {0} hat nur noch {1:N0} % frei.' -f $v.DeviceID, ($v.FreeSpace / $v.Size * 100))
        }
    }
}

Invoke-Section 'Stabilität' -Level 3 {
    # Ereignisprotokoll System; Kernel-Power 41 kommt auch bei Stromausfall, daher erst ab 3
    $arten = [ordered]@{
        'Bluescreens'               = @{ ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; Ab = 1 }
        'Unerwartete Abschaltungen' = @{ ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; Ab = 3 }
        'Datenträgerfehler'         = @{ ProviderName = 'disk'; Id = 7, 51; Ab = 1 }
    }
    $data = [ordered]@{}
    foreach ($art in $arten.Keys) {
        $a = $arten[$art]
        $ev = @()
        try { $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = $a.ProviderName; Id = $a.Id; StartTime = $now.AddDays(-30) } -ErrorAction Stop) }
        catch { if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw } }
        $data[$art] = if ($ev.Count) { '{0} (zuletzt {1})' -f $ev.Count, $ev[0].TimeCreated.ToString('dd.MM.yyyy') } else { '0' }
        if ($ev.Count -ge $a.Ab) { Add-Befund 'Warnung' ('{0} in den letzten 30 Tagen: {1}.' -f $art, $ev.Count) }
    }
    Add-Line 'Ereignisse der letzten 30 Tage.'
    Add-Line
    Add-KeyValueTable $data
}

# ---------------------------------------------------------------------------
# Peripherie & Grafik
# ---------------------------------------------------------------------------

Add-Line '## Peripherie & Grafik'
Add-Line

Invoke-Section 'Grafik' -Level 3 {
    # AdapterRAM ist UInt32 (max. 4 GB) - echten Wert aus der Registry holen
    $vram = @{}
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    Get-ChildItem $classKey -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($p -and $p.PSObject.Properties['DriverDesc'] -and $p.PSObject.Properties['HardwareInformation.qwMemorySize']) {
            $vram[$p.DriverDesc] = [double]$p.'HardwareInformation.qwMemorySize'
        }
    }
    Add-Table (Get-Cim Win32_VideoController) ([ordered]@{
        'Grafikkarte'  = 'Name'
        'Speicher'     = { param($g) if ($vram.ContainsKey($g.Name)) { Format-Bytes $vram[$g.Name] } else { Format-Bytes $g.AdapterRAM } }
        'Treiber'      = 'DriverVersion'
        'Treiberdatum' = { param($g) if ($g.DriverDate) { $g.DriverDate.ToString('dd.MM.yyyy') } }
        'Auflösung'   = { param($g) if ($g.CurrentHorizontalResolution) { '{0} x {1}' -f $g.CurrentHorizontalResolution, $g.CurrentVerticalResolution } }
    })
}

Invoke-Section 'Monitore' -Level 3 {
    Add-Table (Get-Cim WmiMonitorID -Namespace 'root\wmi') ([ordered]@{
        'Hersteller'   = { param($m) ConvertFrom-WmiString $m.ManufacturerName }
        'Modell'       = { param($m) ConvertFrom-WmiString $m.UserFriendlyName }
        'Seriennummer' = { param($m) ConvertFrom-WmiString $m.SerialNumberID }
        'Baujahr'      = 'YearOfManufacture'
        'Aktiv'        = 'Active'
    })
}

Invoke-Section 'Drucker' -Level 3 {
    Add-Table (Get-Cim Win32_Printer | Sort-Object Name) ([ordered]@{
        'Name'     = 'Name'
        'Treiber'  = 'DriverName'
        'Anschluss'= 'PortName'
        'Standard' = 'Default'
        'Netzwerk' = 'Network'
        'Freigegeben' = 'Shared'
    })
}

Invoke-Section 'Akku' -Level 3 {
    $bat = @(Get-Cim Win32_Battery)
    if ($bat.Count -eq 0) { Add-Line '_Kein Akku vorhanden._'; Add-Line; return }
    $static = @(); $full = @()
    try { $static = @(Get-Cim BatteryStaticData -Namespace 'root\wmi') } catch { }
    try { $full   = @(Get-Cim BatteryFullChargedCapacity -Namespace 'root\wmi') } catch { }
    for ($i = 0; $i -lt $bat.Count; $i++) {
        $b = $bat[$i]
        $data = [ordered]@{
            'Bezeichnung' = $b.Name
            'Ladestand'   = "$($b.EstimatedChargeRemaining) %"
        }
        if ($i -lt $static.Count -and $i -lt $full.Count -and $static[$i].DesignedCapacity) {
            $design = $static[$i].DesignedCapacity
            $now100 = $full[$i].FullChargedCapacity
            $data['Hersteller']          = $static[$i].ManufactureName
            $data['Design-Kapazität']   = '{0:N0} mWh' -f $design
            $data['Aktuelle Kapazität'] = '{0:N0} mWh' -f $now100
            $gesundheit = $now100 / $design * 100
            $data['Akku-Gesundheit']     = '{0:N0} %' -f $gesundheit
            if ($gesundheit -gt 0 -and $gesundheit -lt 60) {
                Add-Befund 'Warnung' ('Der Akku hat nur noch {0:N0} % seiner ursprünglichen Kapazität.' -f $gesundheit)
            }
        }
        Add-KeyValueTable $data
    }
}

# ---------------------------------------------------------------------------
# Netzwerk
# ---------------------------------------------------------------------------

Add-Line '## Netzwerk'
Add-Line

Invoke-Section 'Adapter' -Level 3 {
    $adapterStatus = @{ 'Up' = 'verbunden'; 'Disconnected' = 'getrennt'; 'Disabled' = 'deaktiviert'; 'Not Present' = 'nicht vorhanden' }
    Add-Table @(Get-NetAdapter -ErrorAction Stop | Sort-Object Name) ([ordered]@{
        'Name'            = 'Name'
        'Beschreibung'    = 'InterfaceDescription'
        'Status'          = { param($a) $s = "$($a.Status)"; if ($adapterStatus.ContainsKey($s)) { $adapterStatus[$s] } else { $s } }
        'MAC-Adresse'     = 'MacAddress'
        'Geschwindigkeit' = { param($a) if ("$($a.Status)" -eq 'Up') { $a.LinkSpeed } }
    })
}

Invoke-Section 'IP-Konfiguration' -Level 3 {
    # Nur verbundene Adapter. Ein Adapter ohne IPv4 liefert $null statt einer leeren Liste.
    $configs = @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { "$($_.NetAdapter.Status)" -eq 'Up' } | Sort-Object InterfaceAlias)
    Add-Table $configs ([ordered]@{
        'Adapter'    = 'InterfaceAlias'
        'IPv4'       = { param($c) (@($c.IPv4Address) | Where-Object { $_ } | ForEach-Object { '{0}/{1}' -f $_.IPAddress, $_.PrefixLength }) -join ', ' }
        'DHCP'       = { param($c) if ($c.NetIPv4Interface) { "$($c.NetIPv4Interface.Dhcp)" -eq 'Enabled' } }
        'Gateway'    = { param($c) ($c.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) -join ', ' }
        'DNS-Server' = { param($c) ($c.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) -join ', ' }
        'IPv6'       = { param($c) ($c.IPv6Address | Where-Object { $_.IPAddress -notlike 'fe80*' } | ForEach-Object { $_.IPAddress }) -join ', ' }
    }) -Empty '_Kein verbundener Netzwerkadapter._'
}

# ---------------------------------------------------------------------------
# Sicherheit
# ---------------------------------------------------------------------------

Add-Line '## Sicherheit'
Add-Line

Invoke-Section 'Plattform' -Level 3 {
    $data = [ordered]@{}

    # TPM
    try {
        $tpm = Get-Cim Win32_Tpm -Namespace 'root\cimv2\Security\MicrosoftTpm'
        if ($tpm) {
            $data['TPM vorhanden']  = 'Ja'
            $data['TPM-Version']    = ($tpm.SpecVersion -split ',')[0].Trim()
            $data['TPM aktiviert']  = Get-YesNo $tpm.IsEnabled_InitialValue
            $data['TPM-Hersteller'] = '{0} ({1})' -f $tpm.ManufacturerIdTxt, $tpm.ManufacturerVersion
        } else { $data['TPM vorhanden'] = 'Nein' }
    } catch { $data['TPM'] = if ($isAdmin) { 'nicht abfragbar' } else { 'nur als Administrator abfragbar' } }

    # Secure Boot
    try {
        $data['Secure Boot'] = if (Confirm-SecureBootUEFI -ErrorAction Stop) { 'Aktiv' } else { 'Inaktiv' }
    } catch [System.PlatformNotSupportedException] {
        $data['Secure Boot'] = 'nicht unterstützt (Legacy BIOS)'
    } catch {
        $data['Secure Boot'] = if ($isAdmin) { 'nicht abfragbar' } else { 'nur als Administrator abfragbar' }
    }

    # Virtualisierungsbasierte Sicherheit
    try {
        $dg = Get-Cim Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard'
        $data['VBS'] = switch ($dg.VirtualizationBasedSecurityStatus) { 0 { 'Aus' } 1 { 'Aktiviert, nicht aktiv' } 2 { 'Aktiv' } default { 'unbekannt' } }
        $data['Credential Guard'] = Get-YesNo (@($dg.SecurityServicesRunning) -contains 1)
    } catch { }

    Add-KeyValueTable $data
}

Invoke-Section 'BitLocker' -Level 3 {
    $vols = $null
    try { $vols = @(Get-BitLockerVolume -ErrorAction Stop) } catch { }
    if ($vols) {
        Add-Table $vols ([ordered]@{
            'Laufwerk'       = 'MountPoint'
            'Schutz'         = { param($v) if ("$($v.ProtectionStatus)" -eq 'On') { 'Ein' } else { 'Aus' } }
            'Status'         = 'VolumeStatus'
            'Verschlüsselt' = { param($v) "$($v.EncryptionPercentage) %" }
            'Methode'        = 'EncryptionMethod'
            'Schutzmethoden' = { param($v) (@($v.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ', ') }
        })
        $sys = $vols | Where-Object { $_.MountPoint -eq $env:SystemDrive } | Select-Object -First 1
        $sysAus = $sys -and "$($sys.ProtectionStatus)" -ne 'On'
    } else {
        $ev = @(Get-Cim Win32_EncryptableVolume -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption')
        Add-Table $ev ([ordered]@{
            'Laufwerk' = 'DriveLetter'
            'Schutz'   = { param($v) switch ($v.ProtectionStatus) { 0 { 'Aus' } 1 { 'Ein' } default { 'unbekannt' } } }
        })
        $sys = $ev | Where-Object { $_.DriveLetter -eq $env:SystemDrive } | Select-Object -First 1
        $sysAus = $sys -and $sys.ProtectionStatus -eq 0
    }
    if ($sysAus) {
        if ($cs.PCSystemTypeEx -in 2, 8) { Add-Befund 'Kritisch' "Mobiles Gerät ohne Verschlüsselung: BitLocker ist auf $env:SystemDrive aus." }
        else { Add-Befund 'Warnung' "BitLocker ist auf dem Systemlaufwerk $env:SystemDrive aus." }
    }
}

Invoke-Section 'Virenschutz' -Level 3 {
    try {
        $av = @(Get-Cim AntiVirusProduct -Namespace 'root\SecurityCenter2')
        # productState hexadezimal: Byte 2 = Echtzeitschutz an (10/11), Byte 3 = Signaturen aktuell (00)
        $avAktiv = { param($a) ('{0:X6}' -f [int]$a.productState).Substring(2, 2) -in '10', '11' }
        $avAktuell = { param($a) ('{0:X6}' -f [int]$a.productState).Substring(4, 2) -eq '00' }
        Add-Table $av ([ordered]@{
            'Produkt'     = 'displayName'
            'Aktiv'       = $avAktiv
            'Signaturen'  = { param($a) if (& $avAktuell $a) { 'aktuell' } else { 'veraltet' } }
        }) -Empty '_Kein Virenschutz im Sicherheitscenter registriert._'
        $aktiv = @($av | Where-Object { & $avAktiv $_ })
        if ($aktiv.Count -eq 0) { Add-Befund 'Kritisch' 'Kein aktiver Virenschutz.' }
        elseif (-not ($aktiv | Where-Object { & $avAktuell $_ })) { Add-Befund 'Warnung' 'Die Virensignaturen sind veraltet.' }
    } catch { Add-Line '_Sicherheitscenter nicht abfragbar._'; Add-Line }

    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        Add-Line '**Microsoft Defender**'
        Add-Line
        Add-KeyValueTable ([ordered]@{
            'Dienst aktiv'           = Get-YesNo $mp.AMServiceEnabled
            'Echtzeitschutz'         = Get-YesNo $mp.RealTimeProtectionEnabled
            'Manipulationsschutz'    = Get-YesNo $mp.IsTamperProtected
            'Modus'                  = $mp.AMRunningMode
            'Produktversion'         = $mp.AMProductVersion
            'Signaturen vom'         = $mp.AntivirusSignatureLastUpdated
            'Letzter Schnellscan'    = $mp.QuickScanEndTime
        })
    } catch { }
}

Invoke-Section 'Firewall' -Level 3 {
    # ActiveStore = tatsächlich wirksame Einstellungen inkl. Gruppenrichtlinien
    $fwProfile = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    Add-Table $fwProfile ([ordered]@{
        'Profil'      = 'Name'
        'Aktiv'       = { param($f) "$($f.Enabled)" -eq 'True' }
        'Eingehend'   = 'DefaultInboundAction'
        'Ausgehend'   = 'DefaultOutboundAction'
    })
    $aus = @($fwProfile | Where-Object { "$($_.Enabled)" -ne 'True' } | ForEach-Object { $_.Name })
    if ($aus.Count -gt 0) { Add-Befund 'Warnung' ('Die Windows-Firewall ist aus (Profil {0}).' -f ($aus -join ', ')) }
}

Invoke-Section 'Windows Update' -Level 3 {
    $hf = @(Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending)
    $last = if ($hf) { $hf[0].InstalledOn } else { $null }
    $data = [ordered]@{ 'Letztes Update installiert' = if ($last) { $last.ToString('dd.MM.yyyy') } else { 'unbekannt' } }
    if ($last) {
        $tage = [int]($now - $last).TotalDays
        $data['Tage seit letztem Update'] = $tage
        if ($tage -gt 45) { Add-Befund 'Warnung' "Das letzte Windows-Update wurde vor $tage Tagen installiert." }
    }
    $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
               (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
    $data['Neustart ausstehend'] = Get-YesNo $pending
    Add-KeyValueTable $data
    Add-Line '**Zuletzt installierte Updates (max. 10)**'
    Add-Line
    Add-Table ($hf | Select-Object -First 10) ([ordered]@{
        'KB'           = 'HotFixID'
        'Typ'          = 'Description'
        'Installiert'  = { param($h) $h.InstalledOn.ToString('dd.MM.yyyy') }
    })
}

# ---------------------------------------------------------------------------
# Benutzer & Lizenz
# ---------------------------------------------------------------------------

Add-Line '## Benutzer & Lizenz'
Add-Line

Invoke-Section 'Domäne & Anmeldung' -Level 3 {
    $data = [ordered]@{}
    if ($cs.PartOfDomain) { $data['AD-Domäne'] = $cs.Domain } else { $data['Arbeitsgruppe'] = $cs.Workgroup }
    try {
        $ds = & (Join-Path ([Environment]::SystemDirectory) 'dsregcmd.exe') /status 2>$null
        $get = { param($k) $l = $ds | Where-Object { $_ -match "^\s*$k\s*:" } | Select-Object -First 1; if ($l) { ($l -split ':', 2)[1].Trim() } }
        $yesNo = { param($v) switch ($v) { 'YES' { 'Ja' } 'NO' { 'Nein' } default { $v } } }
        $data['Entra ID (Azure AD) beigetreten'] = & $yesNo (& $get 'AzureAdJoined')
        $tn = & $get 'TenantName'; if ($tn) { $data['Entra-Mandant'] = $tn }
        $data['AD-Domäne beigetreten'] = & $yesNo (& $get 'DomainJoined')
        $mdm = & $get 'MdmUrl'; if ($mdm) { $data['MDM (z. B. Intune)'] = $mdm }
    } catch { }
    Add-KeyValueTable $data
}

Invoke-Section 'Lokale Benutzer' -Level 3 {
    $users = @(Get-LocalUser -ErrorAction Stop | Sort-Object Name)
    if ($users | Where-Object { $_.SID.Value -like '*-501' -and $_.Enabled }) { Add-Befund 'Warnung' 'Das Gastkonto ist aktiv.' }
    Add-Table $users ([ordered]@{
        'Name'              = 'Name'
        'Vollständiger Name' = 'FullName'
        'Aktiv'             = 'Enabled'
        'Letzte Anmeldung'  = 'LastLogon'
        'Kennwort gesetzt'  = 'PasswordLastSet'
        'Kennwort läuft ab' = { param($u) if ($u.PasswordExpires) { $u.PasswordExpires } else { 'nie' } }
    })
}

Invoke-Section 'Lokale Administratoren' -Level 3 {
    $sid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $members = $null
    try {
        $members = @(Get-LocalGroupMember -SID $sid -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Typ = "$($_.ObjectClass)"; Quelle = "$($_.PrincipalSource)" } })
    } catch {
        # Get-LocalGroupMember scheitert an verwaisten SIDs / Entra-Konten -> ADSI-Fallback
        $groupName = $sid.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
        $grp = [ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group"
        $members = @($grp.Invoke('Members') | ForEach-Object {
            $path = $_.GetType().InvokeMember('AdsPath', 'GetProperty', $null, $_, $null)
            $cls  = $_.GetType().InvokeMember('Class', 'GetProperty', $null, $_, $null)
            [pscustomobject]@{ Name = ($path -replace '^WinNT://', '' -replace '/', '\'); Typ = $cls; Quelle = '' } })
    }
    Add-Table $members ([ordered]@{ 'Mitglied' = 'Name'; 'Typ' = 'Typ'; 'Quelle' = 'Quelle' })
}

Invoke-Section 'Windows-Lizenz' -Level 3 {
    if ($lizenzFehler) { throw $lizenzFehler }
    $winAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
    $lic = @($lizenzen | Where-Object { $_.ApplicationID -eq $winAppId })
    foreach ($l in $lic) {
        $channel = 'unbekannt'
        if ($l.Description -match 'OEM') { $channel = 'OEM' }
        elseif ($l.Description -match 'VOLUME_KMSCLIENT') { $channel = 'Volumen (KMS)' }
        elseif ($l.Description -match 'VOLUME_MAK') { $channel = 'Volumen (MAK)' }
        elseif ($l.Description -match 'RETAIL') { $channel = 'Retail / Digitale Lizenz' }
        Add-KeyValueTable ([ordered]@{
            'Edition'          = $l.Name
            'Lizenzkanal'      = $channel
            'Status'           = $lizenzStatus[[int]$l.LicenseStatus]
            'Teil-Produktkey'  = 'XXXXX-XXXXX-XXXXX-XXXXX-' + $l.PartialProductKey
        })
    }
    if ($lic.Count -eq 0) { Add-Line '_Keine Windows-Lizenz gefunden._'; Add-Line }

    $oa3 = (Get-Cim SoftwareLicensingService).OA3xOriginalProductKey
    if ($oa3) {
        $shown = if ($IncludeProductKey) { $oa3 } else { 'XXXXX-XXXXX-XXXXX-XXXXX-' + $oa3.Substring($oa3.Length - 5) }
        Add-KeyValueTable ([ordered]@{ 'OEM-Key in Firmware' = $shown })
    }
}

# ---------------------------------------------------------------------------
# Software
# ---------------------------------------------------------------------------

Add-Line '## Installierte Software'
Add-Line

Invoke-Section 'Microsoft 365 / Office' -Level 3 {
    $found = $false
    $c2r = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $ids = Get-RegValue $c2r 'ProductReleaseIds'
    if ($ids) {
        $found = $true
        $names = @{
            'O365ProPlusRetail'  = 'Microsoft 365 Apps for enterprise'
            'O365BusinessRetail' = 'Microsoft 365 Apps for business'
            'O365HomePremRetail' = 'Microsoft 365 Family/Single'
        }
        # Update-Kanal steckt als GUID in der CDN-Adresse; UpdateChannel (Richtlinie) hat Vorrang
        $channels = @{
            '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Aktueller Kanal'
            '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'Aktueller Kanal (Vorschau)'
            '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'Monatlicher Enterprise-Kanal'
            '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'Halbjährlicher Enterprise-Kanal'
            'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'Halbjährlicher Enterprise-Kanal (Vorschau)'
            '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'Beta-Kanal'
        }
        $url = Get-RegValue $c2r 'UpdateChannel'
        if (-not $url) { $url = Get-RegValue $c2r 'CDNBaseUrl' }
        $channel = 'unbekannt'
        if ($url -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
            $channel = if ($channels.ContainsKey($Matches[1])) { $channels[$Matches[1]] } else { $Matches[1] }
        }
        $products = foreach ($id in ($ids -split ',')) {
            if ($names.ContainsKey($id)) { '{0} ({1})' -f $names[$id], $id } else { $id }
        }
        $lizenz = if ($ids -match 'O365') { 'Abonnement, lizenziert über die Anmeldung des Benutzers' }
                  elseif ($ids -match 'Volume') { 'Volumenlizenz' } else { 'Einzelplatzlizenz (Retail)' }
        Add-KeyValueTable ([ordered]@{
            'Produkt'      = $products -join ', '
            'Version'      = Get-RegValue $c2r 'VersionToReport'
            'Architektur'  = Get-RegValue $c2r 'Platform'
            'Update-Kanal' = $channel
            'Lizenzart'    = $lizenz
            'Gemeinsame Computeraktivierung' = (Get-RegValue $c2r 'SharedComputerLicensing') -eq '1'
        })
    }
    # Dauerlizenzen (Office 2016-2024, Volumen/Retail) stehen im Windows-Lizenzdienst. Die
    # "Grace"-Einträge der Abos zeigen dort "Benachrichtigung", obwohl Office lizenziert ist.
    if ($lizenzFehler) {
        # Click-to-Run-Daten oben bleiben gültig; nur der Lizenzstatus fehlt
        if (-not $found) { throw $lizenzFehler }
        Add-Line ('_Lizenzstatus nicht abfragbar: {0}_' -f (ConvertTo-MdCell $lizenzFehler))
        Add-Line
        return
    }
    $officeAppId = '0ff1ce15-a989-479d-af46-f275c6370663'
    $lic = @($lizenzen | Where-Object { $_.ApplicationID -eq $officeAppId -and $_.Name -notmatch 'O365' })
    if ($lic.Count -gt 0) {
        $found = $true
        Add-Table $lic ([ordered]@{
            'Lizenz'          = 'Name'
            'Status'          = { param($l) $lizenzStatus[[int]$l.LicenseStatus] }
            'Teil-Produktkey' = { param($l) 'XXXXX-XXXXX-XXXXX-XXXXX-' + $l.PartialProductKey }
        })
        # Ohne Updates: Office 2016 und 2019 seit 14.10.2025, Office 2021 seit 13.10.2026
        foreach ($l in $lic) {
            if ($l.LicenseStatus -eq 1 -and $l.Name -match '^Office (16|19|21),' -and $l.Name -notmatch 'Subscription') {
                Add-Befund 'Kritisch' ('Office 20{0} bekommt keine Sicherheitsupdates mehr.' -f $Matches[1])
            }
        }
    }
    if (-not $found) { Add-Line '_Kein Microsoft 365 / Office gefunden._'; Add-Line }
}

Invoke-Section 'Programme' -Level 3 {
    $sources = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*';             Scope = 'Alle Benutzer' }
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'Alle Benutzer (32-Bit)' }
    )
    # Benutzerinstallationen aller aktuell geladenen Profile (u. a. angemeldeter Benutzer)
    Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-[\d-]+$' } | ForEach-Object {   # 12-1 = Entra-ID-Konten
            $sidStr = $_.PSChildName
            $user = $sidStr
            try { $user = (New-Object System.Security.Principal.SecurityIdentifier($sidStr)).Translate([System.Security.Principal.NTAccount]).Value } catch { }
            $sources += @{ Path = "Registry::HKEY_USERS\$sidStr\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"; Scope = "Benutzer $user" }
        }

    $apps = foreach ($src in $sources) {
        Get-ItemProperty -Path $src.Path -ErrorAction SilentlyContinue | Where-Object {
            $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -and
            -not ($_.PSObject.Properties['SystemComponent'] -and $_.SystemComponent -eq 1) -and
            -not ($_.PSObject.Properties['ParentKeyName'] -and $_.ParentKeyName) -and
            -not ($_.PSObject.Properties['ReleaseType'] -and $_.ReleaseType -match 'Update|Hotfix')
        } | ForEach-Object {
            $date = $null
            if ($_.PSObject.Properties['InstallDate'] -and $_.InstallDate -match '^\d{8}$') {
                try { $date = [datetime]::ParseExact($_.InstallDate, 'yyyyMMdd', $null).ToString('dd.MM.yyyy') } catch { }
            }
            [pscustomobject]@{
                Name       = "$($_.DisplayName)".Trim()
                Version    = if ($_.PSObject.Properties['DisplayVersion']) { "$($_.DisplayVersion)" } else { '' }
                Hersteller = if ($_.PSObject.Properties['Publisher']) { "$($_.Publisher)" } else { '' }
                Datum      = $date
                Bereich    = $src.Scope
            }
        }
    }
    $apps = @($apps | Sort-Object Name, Version -Unique)
    Add-Line ('{0} Programme gefunden.' -f $apps.Count)
    Add-Line
    Add-Table $apps ([ordered]@{
        'Name' = 'Name'; 'Version' = 'Version'; 'Hersteller' = 'Hersteller'; 'Installiert' = 'Datum'; 'Bereich' = 'Bereich'
    })
}

if (-not $NoStoreApps) {
    Invoke-Section 'Store-Apps' -Level 3 {
        $p = @{ ErrorAction = 'Stop' }
        if ($isAdmin) { $p.AllUsers = $true }
        $appx = @(Get-AppxPackage @p | Where-Object {
            -not $_.IsFramework -and -not $_.NonRemovable -and "$($_.SignatureKind)" -ne 'System' -and -not $_.IsResourcePackage
        } | Sort-Object Name -Unique)
        Add-Line ('{0} Apps gefunden{1}.' -f $appx.Count, $(if ($isAdmin) { ' (alle Benutzer)' } else { ' (nur aktueller Benutzer)' }))
        Add-Line
        Add-Table $appx ([ordered]@{
            'Paket'      = 'Name'
            'Version'    = 'Version'
            'Herausgeber'= { param($a) if ($a.Publisher -match 'CN=([^,]+)') { $Matches[1] } else { $a.Publisher } }
            'Quelle'     = 'SignatureKind'
        })
    }
}

# ---------------------------------------------------------------------------
# Hinweise und Befunde unter den Kopf, schreiben, Sammelbericht
# ---------------------------------------------------------------------------

$block = New-Object System.Collections.Generic.List[string]
foreach ($h in $script:hinweise) { $block.Add("> **Hinweis:** $h") }
if ($script:hinweise.Count -gt 0) { $block.Add('') }
$block.Add('## Befunde')
$block.Add('')
foreach ($stufe in 'Kritisch', 'Warnung') {
    foreach ($b in $script:befunde) { if ($b.Stufe -eq $stufe) { $block.Add(('- **{0}:** {1}' -f $stufe, (ConvertTo-MdCell $b.Text))) } }
}
if ($script:befunde.Count -eq 0) { $block.Add('_Keine Befunde._') }
$block.Add('')
$script:md.InsertRange($headerIndex, $block)

$dir = Split-Path -Parent $OutputPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
[System.IO.File]::WriteAllLines($OutputPath, $script:md, (New-Object System.Text.UTF8Encoding($false)))

$kritisch = @($script:befunde | Where-Object { $_.Stufe -eq 'Kritisch' }).Count
Write-Host ''
Write-Host ('Befunde: {0} kritisch, {1} Warnung(en)' -f $kritisch, ($script:befunde.Count - $kritisch))
Write-Host "Report geschrieben: $OutputPath" -ForegroundColor Green

# Ein Fehler hier darf die fertige Inventur nicht als gescheitert melden
if ($Kunde) {
    try {
        $sammel = Write-Sammelbericht $dir $Kunde
        if ($sammel) { Write-Host "Sammelbericht aktualisiert: $sammel" -ForegroundColor Green }
    } catch { Write-Warning "Sammelbericht nicht erstellt: $($_.Exception.Message)" }
}
