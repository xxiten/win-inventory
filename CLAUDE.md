# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A read-only inventory tool for Windows 10/11 PCs. `Invoke-Inventur.ps1` collects hardware, security, user/license and software data and writes a German Markdown report (`Inventur_<RECHNER>_<yyyy-MM-dd>.md`). Producing that clean Markdown file is the whole job. Converting it to HTML/PDF is out of scope. It must run on a stock Windows install: Windows PowerShell 5.1, no modules, no internet, no changes to the system.

Everything user-facing (report text, GUI, README, code comments, commit messages) is in German.

## Commands

```powershell
# Build dist\Inventur.exe (uses csc.exe from .NET Framework 4.x shipped with Windows; no SDK needed)
powershell -ExecutionPolicy Bypass -File .\build.ps1

# Run the script directly (elevated shell for complete results; non-admin also works but sections are missing)
powershell -ExecutionPolicy Bypass -File .\Invoke-Inventur.ps1 -Kunde "Muster GmbH" -Techniker "Max Mustermann" -OutputPath $env:TEMP\Inventur_Test.md
```

Always test with `powershell` (5.1), not `pwsh`: 7.x accepts syntax that 5.1 rejects. There is no test suite. The check is running the script and looking for `_Nicht verfügbar: …_` lines in the report. CI does the same: on every push/PR to `main`, `.github/workflows/build.yml` builds the exe on `windows-latest`, runs the script under 5.1, emits a warning for each "Nicht verf" line, and uploads the exe plus the test report as an artifact.

## Architecture

Three entry points all end up running `Invoke-Inventur.ps1`:

1. **`Inventur.exe`** (`src/InventurLauncher.cs`, WinForms). `build.ps1` embeds the `.ps1` as a manifest resource, so **script changes only reach the exe after a rebuild**. `app.manifest` requests admin rights, so everything below runs elevated:
   - **Staging the script:** it is written into a fresh folder under `%WINDIR%\Temp` whose protected DACL allows only SYSTEM and Administrators (`CreatePrivateTempDir`). Never stage it in the user's `%TEMP%`: an unelevated process could swap it before PowerShell reads it.
   - **Starting PowerShell:** `powershell.exe` comes from `Sysnative`/`System32`, so a 32-bit process still gets 64-bit PowerShell and the real registry. `PSModulePath` is set to the system modules only, so modules in the user's Documents folder can't shadow cmdlets.
   - **Passing parameters:** `-OutputPath/-Kunde/-Techniker/-NoStoreApps/-IncludeProductKey` go through `Quote()`, which follows the Windows argv rules (backslashes before `"` doubled, `"` as `\"`). Names keep their quotes.
   - **Showing output:** stdout/stderr stream into the log box using the system OEM code page (`GetOEMCP()`). Don't take it from `CultureInfo.TextInfo.OEMCodePage`: formats like de-IT/en-DE return `1` there and `Encoding.GetEncoding` throws.
   - **Opening things:** report, folder and website all go through `explorer.exe` (`OpenWithShell`), so the editor or browser doesn't run elevated.
   - **Icon:** it is embedded once, via `/win32icon`. The window loads the large and small icon from the exe with `SHDefExtractIcon`.
   - **Remembered setting:** the technician name is stored under `HKCU\Software\win-inventory`.
2. **`Start-Inventur.cmd`** checks for admin rights with `fltmc` (`net session` breaks when the Server service is off) and elevates itself first. Then it prompts for the customer name, so the input isn't lost during the UAC restart. It strips `"` and trailing `\` from the name and calls PowerShell by full path with the same pinned `PSModulePath`.
3. **Direct call** with parameters.

**How the script builds the report:** lines accumulate in `$script:md`. The file starts with `# Inventur <RECHNER>` and a one-row table (customer, technician, timestamp, script version). There is no YAML front matter, because the Markdown must read well in any viewer. Each section is wrapped in `Invoke-Section`, which catches exceptions and writes `_Nicht verfügbar: <reason>_`, so one failing data source never aborts the run. Warnings collected in `$script:hinweise` (for example "not running as admin") are inserted as blockquotes at `$headerIndex`, right after that header, just before the file is written. The output is UTF-8 **without** a BOM.

Helpers to reuse when adding data:
- `Add-Table $rows ([ordered]@{ 'Header' = 'PropertyName'; 'Other' = { param($x) ... } })` takes a property name or a scriptblock per column.
- `Add-KeyValueTable ([ordered]@{...})` builds a two-column table.
- `ConvertTo-MdCell` escapes Markdown and formats dates as `dd.MM.yyyy HH:mm` and bools as Ja/Nein. It escapes `| * _ \` <`, and doubles a backslash only before punctuation, so `\\server` survives and `DOMAIN\user` stays readable. Every table value must go through it.
- `Get-Cim` sets `-ErrorAction Stop` so `Invoke-Section` can catch failures. `Get-RegValue` returns `$null` instead of throwing.

## Constraints that are easy to break

- **PowerShell 5.1 syntax only.** That rules out `? :`, `??`, `?.`, `&&`/`||` and other 7.x syntax. An `if` without `else` used as a hashtable value is a parse error in 5.1, so wrap it as `$(if (...) { ... })`.
- **`Invoke-Inventur.ps1` must stay UTF-8 with BOM.** 5.1 reads BOM-less files as ANSI and the umlauts break. `build.ps1` and `Start-Inventur.cmd` are pure ASCII (comments write ae/oe/ue). Keep them that way. Line endings are pinned in `.gitattributes`: CRLF for ps1/cmd/cs/manifest, LF for md/yml. A batch file with LF line endings breaks `goto`/labels.
- **C# 5 only** in `InventurLauncher.cs`. The in-box `csc.exe` v4.0.30319 has no string interpolation, `?.`, `nameof`, expression-bodied members, etc.
- **Read-only.** The script must not change system state.
- **The version number** lives only in `$ScriptVersion` in `Invoke-Inventur.ps1`, in the format `x.y.z`, which `build.ps1` enforces. `build.ps1` generates the exe's `AssemblyVersion` from it, and the footer reads it from there. The `assemblyIdentity` in `app.manifest` stays fixed at 1.0.0.0. Don't add version literals anywhere else. Product, company and copyright text are the `Product`/`Company`/`Copyright` consts in `MainForm`, and the assembly attributes use them too.
- **Releases:** *Actions → Build → Run workflow* with the version (e.g. `0.8.0`), or push a `v*` tag. The release runs as a separate job, the only one with `contents: write`. It reads the version from the built exe and fails if the tag doesn't match.
- **The repo is public and MIT-licensed** (`LICENSE`). Only add third-party assets whose license allows redistribution in a public repo. A Flaticon free icon, for example, does not. `src/app.ico` is from Microsoft Fluent UI Emoji (MIT). If you replace it, update `THIRD-PARTY-NOTICES.md` and `IconCredit` in `MainForm`. `build.ps1` embeds `LICENSE` and `THIRD-PARTY-NOTICES.md` into the exe, because MIT requires the notice in every copy.
- **Reports contain customer data** (serial numbers, user names, Entra tenant). `Inventur_*` and `dist/` are gitignored. Never commit generated reports. Product keys stay masked unless `-IncludeProductKey` is passed.
