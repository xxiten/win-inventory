<#
.SYNOPSIS
    Inventur eines Windows-10/11-Rechners als Markdown-Report.

.DESCRIPTION
    Sammelt Hardware, Betriebssystem, Sicherheit, Peripherie, Benutzer/Lizenz und
    installierte Software (klassisch + Store) und schreibt einen Markdown-Report.

    Läuft mit Windows PowerShell 5.1 (Bordmittel), keine zusätzlichen Module.
    Als Administrator ausfuehren - sonst fehlen u. a. BitLocker, TPM, Secure Boot
    und die Store-Apps aller Benutzer (der Report vermerkt das).

.PARAMETER OutputPath
    Zieldatei oder Zielordner. Standard: Ordner des Skripts,
    Dateiname Inventur_<RECHNER>_<yyyy-MM-dd>.md

.PARAMETER Kunde
    Optionaler Kundenname für den Report-Kopf.

.PARAMETER Techniker
    Optionaler Name des Technikers, der die Inventur durchführt.

.PARAMETER IncludeProductKey
    Gibt den im Firmware hinterlegten OEM-Produktschlüssel vollständig aus.
    Standard: nur die letzten 5 Zeichen.

.PARAMETER NoStoreApps
    Store-/Appx-Apps nicht auflisten.

.EXAMPLE
    .\Invoke-Inventur.ps1 -Kunde "Muster GmbH" -Techniker "Max Mustermann"
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$Kunde,
    [string]$Techniker,
    [switch]$IncludeProductKey,
    [switch]$NoStoreApps
)


$ErrorActionPreference = 'Stop'
$ScriptVersion = '0.8.4'

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

$script:md = New-Object System.Collections.Generic.List[string]
$script:hinweise = New-Object System.Collections.Generic.List[string]

function Add-Line { param([string]$Text = '') $script:md.Add($Text) }

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
    # Zeichen, die Tabellenspalten, Hervorhebung, Code oder HTML auslösen
    return $s -replace '([|*_`<])', '\$1'
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

Add-Line "# Inventur $env:COMPUTERNAME"
Add-Line
$kopf = [ordered]@{}
if ($Kunde) { $kopf['Kunde'] = $Kunde }
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
    $data['Betriebssystem']     = $os.Caption
    $data['Version']            = $displayVersion
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
    Add-Table (Get-Cim Win32_LogicalDisk -Filter 'DriveType=3') ([ordered]@{
        'Laufwerk'    = 'DeviceID'
        'Bezeichnung' = 'VolumeName'
        'Dateisystem' = 'FileSystem'
        'Größe'     = { param($v) Format-Bytes $v.Size }
        'Frei'        = { param($v) Format-Bytes $v.FreeSpace }
        'Frei %'      = { param($v) if ($v.Size) { '{0:N0} %' -f ($v.FreeSpace / $v.Size * 100) } }
    })
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
            $data['Akku-Gesundheit']     = '{0:N0} %' -f ($now100 / $design * 100)
        }
        Add-KeyValueTable $data
    }
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
    } else {
        $ev = @(Get-Cim Win32_EncryptableVolume -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption')
        Add-Table $ev ([ordered]@{
            'Laufwerk' = 'DriveLetter'
            'Schutz'   = { param($v) switch ($v.ProtectionStatus) { 0 { 'Aus' } 1 { 'Ein' } default { 'unbekannt' } } }
        })
    }
}

Invoke-Section 'Virenschutz' -Level 3 {
    try {
        $av = @(Get-Cim AntiVirusProduct -Namespace 'root\SecurityCenter2')
        Add-Table $av ([ordered]@{
            'Produkt'     = 'displayName'
            'Aktiv'       = { param($a) $h = '{0:X6}' -f [int]$a.productState; if ($h.Substring(2, 2) -in '10', '11') { 'Ja' } else { 'Nein' } }
            'Signaturen'  = { param($a) $h = '{0:X6}' -f [int]$a.productState; if ($h.Substring(4, 2) -eq '00') { 'aktuell' } else { 'veraltet' } }
        }) -Empty '_Kein Virenschutz im Sicherheitscenter registriert._'
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
    Add-Table (Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop) ([ordered]@{
        'Profil'      = 'Name'
        'Aktiv'       = { param($f) "$($f.Enabled)" -eq 'True' }
        'Eingehend'   = 'DefaultInboundAction'
        'Ausgehend'   = 'DefaultOutboundAction'
    })
}

Invoke-Section 'Windows Update' -Level 3 {
    $hf = @(Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending)
    $last = if ($hf) { $hf[0].InstalledOn } else { $null }
    $data = [ordered]@{ 'Letztes Update installiert' = if ($last) { $last.ToString('dd.MM.yyyy') } else { 'unbekannt' } }
    if ($last) { $data['Tage seit letztem Update'] = [int]($now - $last).TotalDays }
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
    Add-Table (Get-LocalUser -ErrorAction Stop | Sort-Object Name) ([ordered]@{
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
    $winAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
    $lic = @(Get-Cim SoftwareLicensingProduct -Filter "ApplicationID='$winAppId' AND PartialProductKey IS NOT NULL")
    $statusText = @{ 0 = 'Nicht lizenziert'; 1 = 'Aktiviert'; 2 = 'Kulanzzeit (OOB)'; 3 = 'Kulanzzeit (OOT)'; 4 = 'Nicht-Original-Kulanz'; 5 = 'Benachrichtigung'; 6 = 'Erweiterte Kulanz' }
    foreach ($l in $lic) {
        $channel = 'unbekannt'
        if ($l.Description -match 'OEM') { $channel = 'OEM' }
        elseif ($l.Description -match 'VOLUME_KMSCLIENT') { $channel = 'Volumen (KMS)' }
        elseif ($l.Description -match 'VOLUME_MAK') { $channel = 'Volumen (MAK)' }
        elseif ($l.Description -match 'RETAIL') { $channel = 'Retail / Digitale Lizenz' }
        Add-KeyValueTable ([ordered]@{
            'Edition'          = $l.Name
            'Lizenzkanal'      = $channel
            'Status'           = $statusText[[int]$l.LicenseStatus]
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
# Hinweise einfügen & schreiben
# ---------------------------------------------------------------------------

if ($script:hinweise.Count -gt 0) {
    $block = New-Object System.Collections.Generic.List[string]
    foreach ($h in $script:hinweise) { $block.Add("> **Hinweis:** $h") }
    $block.Add('')
    $script:md.InsertRange($headerIndex, $block)
}

$dir = Split-Path -Parent $OutputPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
[System.IO.File]::WriteAllLines($OutputPath, $script:md, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host "Report geschrieben: $OutputPath" -ForegroundColor Green
