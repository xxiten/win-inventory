<#
.SYNOPSIS
    Baut dist\Inventur.exe mit dem in Windows enthaltenen .NET-Framework-Compiler.
    Keine Installation von Visual Studio oder .NET SDK noetig.
#>
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'csc.exe aus dem .NET Framework 4.x nicht gefunden.' }

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$exe = Join-Path $dist 'Inventur.exe'

# Die Version steht nur in $ScriptVersion im Skript; daraus wird die Exe-Version.
$line = Select-String -LiteralPath "$root\Invoke-Inventur.ps1" -Pattern "^\`$ScriptVersion = '([^']+)'" | Select-Object -First 1
if (-not $line) { throw '$ScriptVersion in Invoke-Inventur.ps1 nicht gefunden.' }
$version = $line.Matches[0].Groups[1].Value
# Exe-Versionen sind rein numerisch; drei Stellen, damit Fusszeile, Report und Tag gleich lauten
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "`$ScriptVersion '$version' muss das Format x.y.z haben." }
$versionCs = Join-Path $env:TEMP "win-inventory-version-$PID.cs"
"[assembly: System.Reflection.AssemblyVersion(""$version"")]" | Set-Content -Path $versionCs -Encoding ASCII

try {
    & $csc /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 `
        "/win32manifest:$root\src\app.manifest" `
        "/win32icon:$root\src\app.ico" `
        "/resource:$root\Invoke-Inventur.ps1,Invoke-Inventur.ps1" `
        "/resource:$root\LICENSE,LICENSE.txt" `
        "/resource:$root\THIRD-PARTY-NOTICES.md,THIRD-PARTY-NOTICES.md" `
        /reference:System.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll `
        "/out:$exe" `
        "$root\src\InventurLauncher.cs" $versionCs
    if ($LASTEXITCODE -ne 0) { throw "Build fehlgeschlagen (csc Exit-Code $LASTEXITCODE)." }
}
finally { Remove-Item $versionCs -ErrorAction SilentlyContinue }

Write-Host "Gebaut: $exe, Version $version ($([math]::Round((Get-Item $exe).Length / 1KB)) KB)"
