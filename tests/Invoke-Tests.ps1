<#
.SYNOPSIS
    Tests für win-inventory, ohne Zusatzmodule (läuft mit Windows PowerShell 5.1).

.DESCRIPTION
    - Skript lässt sich unter 5.1 parsen
    - Hilfsfunktionen (ConvertTo-MdCell, Format-Bytes)
    - Gliederung eines fertigen Reports (-ReportPath): Kopf und feste Liste der Überschriften
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
foreach ($name in 'ConvertTo-MdCell', 'Format-Bytes') {
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

# --- Gliederung des Reports -------------------------------------------------------------
# Die Überschriften sind das Format des Reports. Bewusste Änderungen: Liste hier anpassen
# und in CHANGELOG.md vermerken.

if ($ReportPath) {
    $lines = Get-Content -LiteralPath $ReportPath -Encoding UTF8
    Assert-Equal 'Report beginnt mit "# Inventur"' $true ($lines[0] -like '# Inventur *')
    Assert-Equal 'Report-Kopf Spalten' '| Kunde | Station | Techniker | Erfasst am | Skriptversion |' $lines[2]
    Assert-Equal 'Report-Kopf Version' $version (($lines[4] -split '\|')[5].Trim())
    $expected = @(
        '## Übersicht'
        '## Hardware', '### Prozessor', '### Arbeitsspeicher', '### Mainboard & Firmware', '### Datenträger'
        '## Peripherie & Grafik', '### Grafik', '### Monitore', '### Drucker', '### Akku'
        '## Netzwerk', '### Adapter', '### IP-Konfiguration'
        '## Sicherheit', '### Plattform', '### BitLocker', '### Virenschutz', '### Firewall', '### Windows Update'
        '## Benutzer & Lizenz', '### Domäne & Anmeldung', '### Lokale Benutzer', '### Lokale Administratoren', '### Windows-Lizenz'
        '## Installierte Software', '### Microsoft 365 / Office', '### Programme', '### Store-Apps'
    )
    $actual = @($lines | Where-Object { $_ -match '^#{2,3} ' })
    Assert-Equal 'Report-Gliederung' ($expected -join ' / ') ($actual -join ' / ')
}

# --- Exe-Launcher -----------------------------------------------------------------------

if (-not $SkipLauncher) {
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    $work = Join-Path ([IO.Path]::GetTempPath()) ('win-inventory-tests-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
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
