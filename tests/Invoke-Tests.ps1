<#
.SYNOPSIS
    Tests für win-inventory, ohne Zusatzmodule (läuft mit Windows PowerShell 5.1).

.DESCRIPTION
    - Skript lässt sich unter 5.1 parsen
    - Hilfsfunktionen (ConvertTo-MdCell, Format-Bytes)
    - Sammelbericht aus mehreren Test-Reports
    - Gliederung eines fertigen Reports (-ReportPath): Kopf, feste Liste der Überschriften,
      Form der Befunde und Lesbarkeit für den Sammelbericht
    - Exe-Launcher (tests\LauncherTests.cs): Quoting, Pfade, Icon; mit Adminrechten zusätzlich
      ein kompletter Inventurlauf über die Exe inkl. geschütztem Temp-Ordner

.PARAMETER ReportPath
    Report, erzeugt mit -Kunde, -Station und -Techniker und ohne -NoStoreApps.

.PARAMETER SkipLauncher
    Den Launcher-Test auslassen.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tests\Invoke-Tests.ps1
#>
param([string]$ReportPath, [switch]$SkipLauncher)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'Invoke-Inventur.ps1'
$script:failures = 0

function Assert-Equal([string]$Name, $Expected, $Actual) {
    if ("$Expected" -ceq "$Actual") { Write-Host "OK      $Name" }
    else {
        $script:failures++
        Write-Host "FEHLER  $Name" -ForegroundColor Red
        Write-Host "        erwartet: [$Expected]"
        Write-Host "        bekommen: [$Actual]"
    }
}

# --- Skript parsen und Hilfsfunktionen laden, ohne die Inventur auszuführen -------------

$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
Assert-Equal 'Invoke-Inventur.ps1 ohne Parserfehler' 0 $parseErrors.Count
foreach ($name in 'ConvertTo-MdCell', 'Format-Bytes', 'Read-MdReport', 'Write-Sammelbericht') {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
$version = [regex]::Match($ast.Extent.Text, "(?m)^\`$ScriptVersion = '([^']+)'").Groups[1].Value

# --- ConvertTo-MdCell -------------------------------------------------------------------

$cases = @(
    @('\\printsrv\Buchhaltung', '\\\printsrv\Buchhaltung'),
    @('NETIXX\Domain Admins',   'NETIXX\Domain Admins'),
    @('<Unknown>',              '\<Unknown>'),
    @('A | B',                  'A \| B'),
    @('*fett* _kursiv_',        '\*fett\* \_kursiv\_'),
    @('Code `x`',               'Code \`x\`'),
    @('pfad\*',                 'pfad\\\*'),
    @('![x](https://e.x/p.png) [Update](https://e.x)', '!\[x\](https://e.x/p.png) \[Update\](https://e.x)'),
    @("Zeile1`r`nZeile2 ",      'Zeile1 Zeile2')
)
foreach ($c in $cases) { Assert-Equal "ConvertTo-MdCell $($c[0] -replace '\s+', ' ')" $c[1] (ConvertTo-MdCell $c[0]) }
Assert-Equal 'ConvertTo-MdCell $null'  ''       (ConvertTo-MdCell $null)
Assert-Equal 'ConvertTo-MdCell $true'  'Ja'     (ConvertTo-MdCell $true)
Assert-Equal 'ConvertTo-MdCell $false' 'Nein'   (ConvertTo-MdCell $false)
Assert-Equal 'ConvertTo-MdCell Datum'  '04.11.2026 09:05' (ConvertTo-MdCell (Get-Date -Year 2026 -Month 11 -Day 4 -Hour 9 -Minute 5))

# --- Format-Bytes (Zahlformat folgt der Kultur, daher Vergleich mit -f) -------------------

Assert-Equal 'Format-Bytes 0'     ''                       (Format-Bytes 0)
Assert-Equal 'Format-Bytes 1 KB'  ('{0:N1} KB' -f 1)       (Format-Bytes 1KB)
Assert-Equal 'Format-Bytes 1,5 GB' ('{0:N1} GB' -f 1.5)    (Format-Bytes 1.5GB)

# --- Sammelbericht ----------------------------------------------------------------------
# Kunde mit "|" (steht im Report entschärft), ein älterer Stand desselben Rechners, ein
# Report von vor 0.10.0 ohne Befunde und ein anderer Kunde, der nicht hineingehört

function New-TestReport([string]$Datei, [string]$Kunde, [string]$Station, [string]$Rechner, [string]$Os, [string]$Upgrade, $Befunde, [int]$Alter) {
    $z = @("# Inventur $Station ($Rechner)", '', '| Kunde | Station | Techniker | Erfasst am | Skriptversion |', '|---|---|---|---|---|',
           "| $Kunde | $Station | T | 01.11.2026 10:00 | 0.10.0 |", '')
    if ($null -ne $Befunde) { $z += '## Befunde', ''; $z += $Befunde; $z += '' }
    $z += '## Übersicht', '', '| Eigenschaft | Wert |', '|---|---|', "| Rechnername | $Rechner |", '| Hersteller | Dell Inc. |',
          '| Modell | OptiPlex 3060 |', "| Betriebssystem | Microsoft $Os |", '| Version | 22H2 |'
    if ($Upgrade) { $z += "| Windows-11-Upgrade | $Upgrade |" }
    $z += '', '## Hardware', ''
    [IO.File]::WriteAllLines($Datei, [string[]]$z, (New-Object Text.UTF8Encoding $false))
    (Get-Item -LiteralPath $Datei).LastWriteTime = (Get-Date).AddDays(-$Alter)
}
$sb = Join-Path ([IO.Path]::GetTempPath()) ('win-inventory-sammel-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sb | Out-Null
try {
    $k = 'Müller & Söhne \| Co'
    New-TestReport "$sb\Inventur_PC01_2026-11-01.md" $k 'Empfang 1' 'PC01' 'Windows 11 Pro' '' @('_Keine Befunde._') 1
    New-TestReport "$sb\Inventur_PC02_2026-01-01.md" $k 'ALTER STAND' 'PC02' 'Windows 10 Pro' '' @() 300
    New-TestReport "$sb\Inventur_PC02_2026-11-01.md" $k 'Buchhaltung' 'PC02' 'Windows 10 Pro' 'nicht möglich (TPM 2.0)' @(
        '- **Kritisch:** Windows 10 bekommt keine Updates mehr.', '- **Warnung:** A', '- **Warnung:** B') 1
    New-TestReport "$sb\Inventur_PC03_2026-11-01.md" 'Andere AG' 'Lager' 'PC03' 'Windows 11 Pro' '' @() 1
    New-TestReport "$sb\Inventur_PC04_2026-03-01.md" $k 'Chef' 'PC04' 'Windows 11 Pro' '' $null 200
    $p = Write-Sammelbericht $sb 'Müller & Söhne | Co'
    Assert-Equal 'Sammelbericht Dateiname' 'Sammelbericht_Müller & Söhne _ Co.md' (Split-Path -Leaf $p)
    $s = @(Get-Content -LiteralPath $p -Encoding UTF8)
    Assert-Equal 'Sammelbericht Titel' '# Sammelbericht Müller & Söhne \| Co' $s[0]
    Assert-Equal 'Sammelbericht Zusammenfassung' '3 Rechner, davon 1 mit kritischen Befunden und 1 ohne Upgrade-Möglichkeit auf Windows 11.' $s[2]
    Assert-Equal 'Sammelbericht Zeilen (neuester Stand je Rechner, nach Station)' 'Buchhaltung / Chef / Empfang 1' (
        ($s | Where-Object { $_ -match '^\| (?!Station |---)' } | ForEach-Object { ($_ -split ' \| ')[0].Substring(2) }) -join ' / ')
    Assert-Equal 'Sammelbericht Windows 10' '| Buchhaltung | PC02 | Dell Inc. OptiPlex 3060 |  |  | Windows 10 Pro 22H2 | nicht möglich (TPM 2.0) | 1 | 2 | 01.11.2026 10:00 |' $s[6]
    Assert-Equal 'Sammelbericht alter Report ohne Befunde' '| Chef | PC04 | Dell Inc. OptiPlex 3060 |  |  | Windows 11 Pro 22H2 | installiert |  |  | 01.11.2026 10:00 |' $s[7]
    Assert-Equal 'Sammelbericht Befunde je Rechner' '## Befunde / ### Buchhaltung (PC02)' (($s | Where-Object { $_ -match '^##' }) -join ' / ')
    Assert-Equal 'Sammelbericht nur ab zwei Rechnern' '' "$(Write-Sammelbericht $sb 'Andere AG')"
}
finally { Remove-Item -LiteralPath $sb -Recurse -Force -ErrorAction SilentlyContinue }

# --- Gliederung des Reports -------------------------------------------------------------
# Die Überschriften sind das Format des Reports. Bewusste Änderungen: Liste hier anpassen
# und in CHANGELOG.md vermerken.

if ($ReportPath) {
    $lines = Get-Content -LiteralPath $ReportPath -Encoding UTF8
    Assert-Equal 'Report beginnt mit "# Inventur"' $true ($lines[0] -like '# Inventur *')
    Assert-Equal 'Report-Kopf Spalten' '| Kunde | Station | Techniker | Erfasst am | Skriptversion |' $lines[2]
    Assert-Equal 'Report-Kopf Version' $version (($lines[4] -split '\|')[5].Trim())
    $expected = @(
        '## Befunde', '## Übersicht'
        '## Hardware', '### Prozessor', '### Arbeitsspeicher', '### Mainboard & Firmware', '### Datenträger', '### Stabilität'
        '## Peripherie & Grafik', '### Grafik', '### Monitore', '### Drucker', '### Akku'
        '## Netzwerk', '### Adapter', '### IP-Konfiguration'
        '## Sicherheit', '### Plattform', '### BitLocker', '### Virenschutz', '### Firewall', '### Windows Update'
        '## Benutzer & Lizenz', '### Domäne & Anmeldung', '### Lokale Benutzer', '### Lokale Administratoren', '### Windows-Lizenz'
        '## Installierte Software', '### Microsoft 365 / Office', '### Programme', '### Store-Apps'
    )
    $actual = @($lines | Where-Object { $_ -match '^#{2,3} ' })
    Assert-Equal 'Report-Gliederung' ($expected -join ' / ') ($actual -join ' / ')

    # Befunde: Kritisch vor Warnung, sonst nur "_Keine Befunde._"
    $befunde = @()
    for ($i = [array]::IndexOf($lines, '## Befunde') + 1; $i -lt $lines.Count -and $lines[$i] -notlike '## *'; $i++) {
        if ($lines[$i]) { $befunde += $lines[$i] }
    }
    $form = @($befunde | ForEach-Object { if ($_ -match '^- \*\*(Kritisch|Warnung):\*\* \S') { $Matches[1] } elseif ($_ -eq '_Keine Befunde._') { 'keine' } else { "FALSCH: $_" } })
    $sortiert = @($form | Where-Object { $_ -eq 'Kritisch' }) + @($form | Where-Object { $_ -ne 'Kritisch' })
    Assert-Equal 'Report-Befunde Form und Reihenfolge' ($sortiert -join ', ') ($form -join ', ')

    $r = Read-MdReport $ReportPath
    Assert-Equal 'Report lesbar für Sammelbericht' $env:COMPUTERNAME $r.Werte['Rechnername']
    Assert-Equal 'Report Übersicht mit Prozessor und RAM' $true ([bool]$r.Werte['Prozessor'] -and [bool]$r.Werte['Arbeitsspeicher'])
    Assert-Equal 'Report Befunde gelesen' $befunde.Count ($r.Befunde.Count + [int]($befunde -contains '_Keine Befunde._'))
}

# --- Exe-Launcher -----------------------------------------------------------------------

if (-not $SkipLauncher) {
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    $name = 'win-inventory-tests-' + [guid]::NewGuid().ToString('N')
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
             ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($admin) {
        # Mit Adminrechten laufen Test-Exe und echo.ps1 erhöht. Im %TEMP% des Benutzers könnte ein
        # Prozess ohne Adminrechte sie vorher austauschen, daher wie im Launcher ein Ordner, auf den
        # nur SYSTEM und Administratoren zugreifen.
        $sec = New-Object System.Security.AccessControl.DirectorySecurity
        $sec.SetOwner((New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        $sec.SetAccessRuleProtection($true, $false)
        foreach ($sid in 'S-1-5-18', 'S-1-5-32-544') {
            $sec.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                (New-Object System.Security.Principal.SecurityIdentifier($sid)), 'FullControl',
                'ContainerInherit, ObjectInherit', 'None', 'Allow')))
        }
        $work = Join-Path ([Environment]::GetFolderPath('Windows')) "Temp\$name"
        [void][IO.Directory]::CreateDirectory($work, $sec)
    } else {
        $work = Join-Path ([IO.Path]::GetTempPath()) $name
        New-Item -ItemType Directory -Path $work | Out-Null
    }
    try {
        & $csc /nologo /target:exe /platform:anycpu /codepage:65001 `
            "/win32icon:$root\src\app.ico" `
            "/resource:$scriptPath,Invoke-Inventur.ps1" `
            /reference:System.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll `
            /main:WinInventory.LauncherTests "/out:$work\LauncherTests.exe" `
            "$root\src\InventurLauncher.cs" "$PSScriptRoot\LauncherTests.cs"
        Assert-Equal 'LauncherTests kompiliert' 0 $LASTEXITCODE
        if ($LASTEXITCODE -eq 0) {
            & "$work\LauncherTests.exe" $work
            $script:failures += $LASTEXITCODE
        }
    }
    finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:failures -eq 0) { Write-Host 'Alle Tests bestanden.' -ForegroundColor Green }
else { Write-Host "$($script:failures) Test(s) fehlgeschlagen." -ForegroundColor Red }
exit $script:failures
