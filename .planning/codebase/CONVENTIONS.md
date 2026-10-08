# Coding Conventions

**Analysis Date:** 2026-10-08

> PowerShell 5.1 / Windows-only tuning-script repo. Two code shapes exist:
> (1) the WPF host + registration layer in `Akari.ps1` and `Tweaks/*.ps1` (an `Add-Tweak` DSL),
> (2) the standalone runnable scripts in the numbered folders (`1 Check/`, `2 Refresh/`, … `8 Advanced/`).
> `Tweaks/*.ps1` files are GENERATED aggregations of the numbered-folder originals (see header comment in `Tweaks/Check.ps1`, `Tweaks/Windows.ps1`, `Tweaks/Setup.ps1`, `Tweaks/Advanced.ps1`).

## Naming Patterns

**Files:**
- Standalone scripts: `"<N> <Name>.ps1"` with numeric prefix + Title Case, spaces allowed — e.g. `1 Check\1 Bios Check.ps1`, `8 Advanced\1 Defender.ps1`, `6 Windows\29 Power Plan.ps1`.
- Category registration files: PascalCase singular — `Tweaks/Check.ps1`, `Tweaks/Windows.ps1`, `Tweaks/Setup.ps1`, `Tweaks/Refresh.ps1`, `Tweaks/Installers.ps1`, `Tweaks/Graphics.ps1`, `Tweaks/Hardware.ps1`, `Tweaks/Advanced.ps1`.
- Host/launcher: `Akari.ps1` (WPF app), `IWR.ps1` (bootstrapper), `AllowScripts.cmd` (batch helper), `UI/MainWindow.xaml` (view).
- Tweak IDs (the `-Id` argument): kebab-case, lowercase — e.g. `'bios-check'`, `'start-taskbar'`, `'memory-compression'`, `'adv-defender'` in `Tweaks/Check.ps1`, `Tweaks/Windows.ps1`, `Tweaks/Setup.ps1`, `Tweaks/Advanced.ps1`.

**Functions:**
- Use approved PowerShell verbs in PascalCase with a dash: `Add-Tweak`, `Write-Log`, `Write-ErrLog`, `Set-Reg`, `Remove-Reg`, `Run-Trusted`, `Get-State`, `Update-Row`, `Show-Page`, `Set-Busy`, `Invoke-Code`, `Confirm-Run`, `Save-State`, `Read-Prio`, `Set-Prio`, `Read-Svc`, `Set-Svc`, `Get-Chip`, `Update-Tuner`, `Set-Chips`, `Get-RamKB`, `Get-SvcTarget`, `Add-Log`, `New-Row` — all defined in `Akari.ps1`.
- The `Run-Trusted` helper is duplicated verbatim inside tweak bodies that need TrustedInstaller (e.g. `Tweaks/Advanced.ps1` Defender Apply/Revert blocks). When adding a TrustedInstaller tweak, copy that exact function rather than inventing a new privilege-escalation path.
- XAML-code-behind style helpers in `Akari.ps1` use `Verb-Noun` even for UI plumbing (`New-Row`, `Update-Row`, `Show-Page`).

**Variables:**
- Script scope for shared mutable state in `Akari.ps1`: `$script:Tweaks`, `$script:RowCache`, `$script:Cat`, `$script:Busy`, `$script:Job`, `$script:Queue`, `$script:State`.
- UI element shortcuts are single PascalCase words via `Set-Variable`: `$Nav`, `$Search`, `$Heading`, `$Tuner`, `$SvcTuner`, `$SvcCur`, `$Rows`, `$Page`, `$Log`, `$Hex`, `$Dec`, `$Logo` (`Akari.ps1` line ~104).
- Tweak bodies use lowercase `$camelCase`/descriptive locals (`$TaskbarClean`, `$DefenderDisable`, `$windowssecuritysettings`, `$notifyiconsettings`, `$regAliases`, `$basePath`, `$keyPath`) and environment paths `$env:SystemRoot`, `$env:SystemDrive`, `$env:USERPROFILE`, `$env:LOCALAPPDATA`, `$env:ProgramData`.
- Registry roots written as `HKLM:` / `HKCU:` PSDrives in PowerShell cmdlets but as `HKLM\…` / `HKCU\…` string literals inside `cmd /c "reg add …"` strings. Keep whichever form the surrounding block already uses; do not mix within one command.

**Types / DSL enums:**
- `Add-Tweak` parameters constrain vocab with `ValidateSet` — copy exactly (`Akari.ps1` lines 40–45):
  - `-Risk`: `'Safe' | 'Caution' | 'Advanced'`
  - `-Kind`: `'Toggle' | 'Action' | 'Group' | 'Console'`
- Group sub-actions are hashtables with keys `Name`, `Description`, `Button`, `Block`, optional `Confirm` — e.g. the `bloatware` Group in `Tweaks/Windows.ps1` and the `rebar` Group in `Tweaks/Advanced.ps1`.

## Code Style

**Formatting:**
- No formatter config in repo (no `.editorconfig`, no `PSScriptAnalyzerSettings.psd1`, no Prettier/ESLint — PowerShell-only repo, those tools do not apply).
- De-facto style: 4-space indent in `Akari.ps1` core; tweak `Apply`/`Revert`/`Detect`/`Check` scriptblock bodies are emitted at column 0 (no indent) — match the surrounding file, do not "fix" indentation inside GENERATED bodies.
- Line continuation with backtick + aligned `-Parameter` pairs for `Add-Tweak` registrations:
  ```powershell
  Add-Tweak -Id 'widgets' -Category 'Windows' -Name 'Widgets' -Risk Safe `
      -Description 'Remove the Widgets board from the taskbar and stop its processes' `
      -Apply {
  # disable widgets regedit
  cmd /c "reg add `"HKLM\SOFTWARE\Policies\Microsoft\Dsh`" /v `"AllowNewsAndInterests`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
      } `
      -Revert {
  # widgets regedit
  cmd /c "reg delete `"HKLM\SOFTWARE\Policies\Microsoft\Dsh`" /f >nul 2>&1"
      } `
      -Detect {
          (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -ErrorAction SilentlyContinue).AllowNewsAndInterests -eq 0
      }
  ```
  (from `Tweaks/Windows.ps1`).
- Quoting: single quotes for static strings, double quotes only when interpolating (`"$Root\$sub"`, `"Win32PrioritySeparation = $hex"`). Escaped quotes inside `cmd /c "reg add `"`"…" strings use the backtick-doublequote form — preserve it exactly.
- Only version gate in the repo: `#requires -Version 5.1` at the top of `Akari.ps1`. New entry-point scripts must start with the same line.

**Linting:**
- None configured. No CI, no `.github/` workflows, no PSScriptAnalyzer settings file. If you run the linter locally, use `Invoke-ScriptAnalyzer -Path` with default rules and treat `PSAvoidUsingCmdletAliases`, `PSAvoidUsingWriteHost` (see Logging exception below), and `PSUseDeclaredVarsMoreThanAssignments` as informational for this codebase.

## Import Organization

**Order:**
1. `#requires` / `param()` header (`Akari.ps1` lines 1–2).
2. Elevation + STA relaunch guard (every entry point: `Akari.ps1`, `IWR.ps1`, `1 Check\1 Bios Check.ps1`, `8 Advanced\1 Defender.ps1`).
3. `Add-Type -AssemblyName …` for WPF/Drawing/Forms (`Akari.ps1` line 15; `System.Windows.Forms`/`System.Drawing` inline in image-generating tweaks such as `signout-wallpaper` in `Tweaks/Windows.ps1`).
4. Dot-sourcing of the whole category layer: `foreach ($f in Get-ChildItem "$Root\Tweaks" -Filter *.ps1 | Sort-Object Name) { . $f.FullName }` (`Akari.ps1` line 56). Registration order is filename-sorted; keep `Tweaks/*.ps1` filenames stable.
5. State/log init (`$StateDir`/`$StatePath`/`$LogFile`), then `$Helpers` here-string, then window/XAML wiring.

**Path Aliases:**
- None (no module system, no `New-Alias`, no bundler aliases). Resolve repo-relative paths from `$Root`/`$PSScriptRoot` with `Join-Path` or `"$Root\UI\MainWindow.xaml"` interpolation. Never hardcode `C:\AkariOS-Ultimate` except in `IWR.ps1` (its `$root = "C:\AkariOS-Ultimate"` install target is intentional).

## Error Handling

**Patterns:**
- Default posture is *suppress-and-continue*: append `-ErrorAction SilentlyContinue | Out-Null` to destructive/optional operations (`Remove-Item`, `Stop-Process`, `Get-ItemProperty`, `Disable-MMAgent`, `Remove-AppxPackage`, `Unblock-File`). Example from `Tweaks/Setup.ps1`:
  ```powershell
  Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue | Out-Null
  ```
- Swallow blocks for best-effort probes: `try { … } catch { }` with an empty catch (state-file load in `Akari.ps1` line 62, `Get-State`/`Detect` invocation line 177, `Disable-BitLocker` loop in `Tweaks/Setup.ps1`).
- Registry-via-`cmd` silencing: every `cmd /c "reg add/delete …"` ends with `>nul 2>&1` (hundreds of instances in `Tweaks/Windows.ps1`, `Tweaks/Advanced.ps1`). Always include the redirect on new `cmd /c reg …` lines.
- Host-level safety nets (do not remove): the file-top `trap { Write-ErrLog …; Show message box; exit }` (`Akari.ps1` line 28) and the `$window.Dispatcher.Add_UnhandledException({ … $ev.Handled = $true; Add-Log …; Set-Busy $false })` handler (`Akari.ps1` lines 382–388).
- Runspace execution wraps every tweak body: `try { & { <code> } *>&1 | Out-String -Stream | … } catch { Write-Log ('Error: ' + $_.Exception.Message) }` (`Invoke-Code` in `Akari.ps1` line 232), plus `EndInvoke` in try/catch and draining `$j.Ps.Streams.Error` into the log (lines 244–245). Tweak code itself must not try to surface errors modally — `Write-Log '…'` / `Write-Host '…'` is the channel.
- Standalone scripts (numbered folders) use the interactive variant: print with `Write-Host "…`n" -ForegroundColor Red`, then `Pause`, then `exit` on preconditions — e.g. the internet gate in `1 Check\1 Bios Check.ps1`:
  ```powershell
  if (!(Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
  Write-Host "Internet Connection Required`n" -ForegroundColor Red
  Pause
  exit
  }
  ```
- Do NOT set `$ErrorActionPreference = 'Stop'` or `Set-StrictMode` — the codebase depends on tolerant reads (missing keys, absent services, already-removed packages).

## Logging

**Framework:** Custom, no dependency. `Write-Host` is *overridden* inside the background runspace to route into the UI log (see `$Helpers` here-string, `Akari.ps1` lines 70–100).

**Patterns:**
- Inside any `Add-Tweak` `Apply`/`Revert`/`Check`/`Block` scriptblock, use `Write-Host "Narrative…"` for user-visible progress and `Write-Log '…'` for guard messages. Both land in the log drawer with an `HH:mm:ss` prefix via `Add-Log` (`Akari.ps1` lines 119–122).
  ```powershell
  if (-not (Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet -ErrorAction SilentlyContinue)) { Write-Log 'Internet connection required'; return }
  Write-Host "Start Menu Taskbar: Clean..."
  ```
- Fatal/host errors go to `%LOCALAPPDATA%\Akari\akari.log` via `Write-ErrLog` (`Akari.ps1` lines 24–27) — reserved for host crashes and UI-thread exceptions, not per-tweak output.
- Standalone scripts log to the console only (`Write-Host` + `Pause` + `Clear-Host`); they must remain readable when double-clicked in their own console window.
- Rules: never `Write-Output` objects from tweak bodies (output is stringified into the log stream); never pop `MessageBox` from tweak code (only `Akari.ps1` host chrome and `-Confirm` prompts may do that); keep messages in `Title Case: Verb…` form (`"Defender: Disable..."`, `"Memory Compression: Off"`).

## Comments

**When to Comment:**
- Every registry/cmd block gets a one-line lowercase comment naming the intent: `# disable widgets regedit`, `# import reg file`, `# restart explorer`, `# stop store running`, `# create reg file` (pervasive in `Tweaks/Windows.ps1`, `Tweaks/Advanced.ps1`). Add one above each new `reg add/delete`, `schtasks`, `bcdedit`, or service change.
- Precondition/caveat comments stay with the command: `# breaks file explorer`, `# windows 11 breaks msi installers if removed`, `# needs safe boot as trusted installer`, `# can't turn back on` (see AppX/Capability whitelists in `Tweaks/Windows.ps1` and Defender blocks in `Tweaks/Advanced.ps1`).
- File headers state provenance: `# <Category> category. GENERATED from the AkariOS-Ultimate '<N> <Name>' scripts…` (`Tweaks/*.ps1` line 1–2). Do not hand-edit GENERATED bodies without also updating the numbered-folder original.

**Section banners (standalone scripts):**
- `8 Advanced\1 Defender.ps1`, `1 Check\1 Bios Check.ps1` open with the same three banners — reproduce verbatim in new standalone scripts:
  ```powershell
  # SCRIPT RUN AS ADMIN
  If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
  {Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
  Exit}
  $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
  $Host.UI.RawUI.BackgroundColor = "Black"
  $Host.PrivateData.ProgressBackgroundColor = "Black"
  $Host.PrivateData.ProgressForegroundColor = "White"
  Clear-Host

  # SCRIPT CHECK INTERNET   # (only in scripts that download)
  ```
- Inline step banners inside bodies are `# <verb> <thing>` lowercase (`# download cpuz`, `# extract files`, `# set start menu apps view to list` in `Tweaks/Check.ps1`, `Tweaks/Windows.ps1`).

**JSDoc/TSDoc:**
- Not applicable (no TypeScript). PowerShell comment-based help (`<# .SYNOPSIS … #>`) is not used anywhere — do not introduce it; follow the banner style above.

## Function Design

**Size:** Host helpers in `Akari.ps1` are 1–15 lines each. Tweak `Apply`/`Revert` blocks are intentionally long procedural batches (dozens to hundreds of lines; `Tweaks/Windows.ps1` is ~6000 lines total) — keep each block to one concern (one feature + its revert) and split multi-step flows into `Group` sub-actions (`-Actions @( @{ … Block = { … } } )`) instead of one mega-menu script.

**Parameters:** `Add-Tweak` call shape (from `Akari.ps1` lines 40–49): `-Id` (kebab-case, unique repo-wide), `-Category` (must match a sidebar entry built in `Akari.ps1` line 293: `Check/Refresh/Setup/Installers/Graphics/Windows/Hardware/Advanced`), `-Name`, `-Description`, `-Risk`, `-Kind`, `-Button` (label for `Action`/`Group`), `-Actions` (Group only), `-Confirm` (destructive prompts — copy the existing explicit-loss wording, e.g. the `bloatware` confirm in `Tweaks/Windows.ps1`), `-Apply` (required), `-Revert` (omit only when there is genuinely no safe revert — the UI then disables the Default button), `-Detect` (return strict `[bool]`; `$null`/throw means "unknown" and renders the dot dimmed via `Get-State`/`Update-Row`), `-Check` (read-only reporter ending with `Pause`).

**Return Values:** `Detect` scriptblocks return `[bool]` or `$null`/nothing; `Check` blocks return nothing (they print + `Pause`); `Apply`/`Revert` return nothing (they print progress; completion is signaled by the runspace finishing, and Toggle state is persisted to `state.json` by the host, not by the tweak).

## Module Design

**Exports:** No modules, no manifests, no `Export-ModuleMember`. The "public API" is the `Add-Tweak` function plus the `$Helpers` runspace prelude (`Write-Log`, shadowed `Write-Host`, `Clear-Host`, `show-menu`, `Pause`, `Set-Reg`, `Remove-Reg`, `Run-Trusted`) defined in `Akari.ps1`. Tweak code may rely only on those helpers plus built-in cmdlets — do not define competing helpers with the same names in `Tweaks/*.ps1`.

**Barrel Files:** `Tweaks/*.ps1` act as category barrels: each file contains only `Add-Tweak …` calls for its category and is dot-sourced alphabetically by the host. To add a tweak: (1) author/fix the standalone script in the matching numbered folder, (2) regenerate or hand-mirror it as an `Add-Tweak` entry in the matching `Tweaks/<Category>.ps1`, keeping `-Id` unique and `-Category` equal to the sidebar name.

**.cmd companion:** `AllowScripts.cmd` is plain batch (`@echo off`, `:labels`, `goto`, `set /p`, `reg add/delete … >nul 2>&1`). Keep batch idioms there; do not port it to PowerShell — its purpose is bootstrapping execution policy when PowerShell itself is locked down.

---

*Convention analysis: 2026-10-08*
