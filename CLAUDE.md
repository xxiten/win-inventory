# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A read-only inventory tool for Windows 10/11 PCs. `Invoke-Inventur.ps1` collects hardware, security, user/license and software data and writes a German Markdown report (`Inventur_<RECHNER>_<yyyy-MM-dd>.md`), which Pandoc turns into HTML/PDF using `report.css`. It must run on a stock Windows install: Windows PowerShell 5.1, no modules, no internet, no changes to the system.

Everything user-facing (report text, GUI, README, code comments, commit messages) is in German.

## Commands

```powershell
# Build dist\Inventur.exe (uses csc.exe from .NET Framework 4.x shipped with Windows; no SDK needed)
powershell -ExecutionPolicy Bypass -File .\build.ps1

# Run the script directly (elevated shell for complete results; non-admin also works but sections are missing)
powershell -ExecutionPolicy Bypass -File .\Invoke-Inventur.ps1 -Kunde "Muster GmbH" -Techniker "Max Mustermann" -OutputPath $env:TEMP\Inventur_Test.md

# Report to HTML / PDF
pandoc Inventur_X.md -s --embed-resources --css report.css -o Inventur_X.html
pandoc Inventur_X.md -s --css report.css --pdf-engine=weasyprint -o Inventur_X.pdf
```

Always test with `powershell` (5.1), not `pwsh`: 7.x accepts syntax that 5.1 rejects. There is no test suite. The check is running the script and looking for `_Nicht verfügbar: …_` lines in the report. CI does the same: on every push/PR to `main`, `.github/workflows/build.yml` builds the exe on `windows-latest`, runs the script under 5.1, emits a warning for each "Nicht verf" line, and uploads the exe plus the test report as an artifact.

## Architecture

Three entry points all end up running `Invoke-Inventur.ps1`:

1. **`Inventur.exe`** (`src/InventurLauncher.cs`, WinForms). `build.ps1` embeds the `.ps1` as a manifest resource, so **script changes only reach the exe after a rebuild**. At runtime the launcher writes the script to `%TEMP%`, starts `powershell.exe` from `Sysnative`/`System32` (so a 32-bit process still gets 64-bit PowerShell and the real registry), passes `-OutputPath/-Kunde/-Techniker/-NoStoreApps/-IncludeProductKey`, and streams stdout/stderr into the log box using the system OEM code page (`GetOEMCP()`). Don't take it from `CultureInfo.TextInfo.OEMCodePage`: formats like de-IT/en-DE return `1` there and `Encoding.GetEncoding` throws. `app.manifest` requests admin rights. The technician name is remembered under `HKCU\Software\win-inventory`.
2. **`Start-Inventur.cmd`** elevates itself first, then prompts for the customer name, so the input isn't lost during the UAC restart.
3. **Direct call** with parameters.

The launcher and the .cmd both strip `"` from the names, because quotes would break the command line.

**How the script builds the report:** lines accumulate in `$script:md`. The file starts with YAML front matter (`title`, `subtitle` = customer, `author` = technician, `date`, `lang`), which Pandoc and `report.css` use for the title block. Each section is wrapped in `Invoke-Section`, which catches exceptions and writes `_Nicht verfügbar: <reason>_`, so one failing data source never aborts the run. Warnings collected in `$script:hinweise` (for example "not running as admin") are inserted as blockquotes at `$headerIndex`, right after the front matter, just before the file is written. The output is UTF-8 **without** a BOM.

Helpers to reuse when adding data:
- `Add-Table $rows ([ordered]@{ 'Header' = 'PropertyName'; 'Other' = { param($x) ... } })` takes a property name or a scriptblock per column.
- `Add-KeyValueTable ([ordered]@{...})` builds a two-column table.
- `ConvertTo-MdCell` handles escaping and formats dates as `dd.MM.yyyy HH:mm` and bools as Ja/Nein.
- `Get-Cim` sets `-ErrorAction Stop` so `Invoke-Section` can catch failures. `Get-RegValue` returns `$null` instead of throwing.

## Constraints that are easy to break

- **PowerShell 5.1 syntax only.** That rules out `? :`, `??`, `?.`, `&&`/`||` and other 7.x syntax. An `if` without `else` used as a hashtable value is a parse error in 5.1, so wrap it as `$(if (...) { ... })`.
- **`Invoke-Inventur.ps1` must stay UTF-8 with BOM.** 5.1 reads BOM-less files as ANSI and the umlauts break. `build.ps1` and `Start-Inventur.cmd` are pure ASCII (comments write ae/oe/ue). Keep them that way. Line endings are pinned in `.gitattributes`: CRLF for ps1/cmd/cs/manifest, LF for md/css/yml.
- **C# 5 only** in `InventurLauncher.cs`. The in-box `csc.exe` v4.0.30319 has no string interpolation, `?.`, `nameof`, expression-bodied members, etc.
- **Read-only.** The script must not change system state.
- **Version number** lives in four places, and all of them must change together: `$ScriptVersion` in `Invoke-Inventur.ps1`, `AssemblyVersion`/`AssemblyFileVersion` in `src/InventurLauncher.cs`, `assemblyIdentity` in `src/app.manifest`, and the "Status" line in `README.md`.
- **Releases:** *Actions → Build → Run workflow* with the version (e.g. `0.8.0`), or push a `v*` tag. The job fails if the tag doesn't equal `v$ScriptVersion`.
- **Reports contain customer data** (serial numbers, user names, Entra tenant). `Inventur_*` and `dist/` are gitignored. Never commit generated reports. Product keys stay masked unless `-IncludeProductKey` is passed.
