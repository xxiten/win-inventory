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

& $csc /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 `
    "/win32manifest:$root\src\app.manifest" `
    "/resource:$root\Invoke-Inventur.ps1,Invoke-Inventur.ps1" `
    /reference:System.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll `
    "/out:$exe" `
    "$root\src\InventurLauncher.cs"
if ($LASTEXITCODE -ne 0) { throw "Build fehlgeschlagen (csc Exit-Code $LASTEXITCODE)." }

Write-Host "Gebaut: $exe ($([math]::Round((Get-Item $exe).Length / 1KB)) KB)"
