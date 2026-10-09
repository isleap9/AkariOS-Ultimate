## Project

**AkariOS-Ultimate**

AkariOS-Ultimate is a single-host PowerShell 5.1 + WPF desktop tweaking tool for Windows 10/11 power users: one elevated shell (`Akari.ps1`) renders a registry of ~127 tweaks across 8 categories and executes them in a background runspace with Apply/Revert support.

This work adds a **Home page** — the new default landing tab — that reads the user's machine specs (CPU, memory, graphics, disk, motherboard/BIOS) and Windows version (edition + build) and presents them in a card grid, refreshed live every time Home is shown.

**Core Value:** The Home page shows accurate, live system specs at a glance — if the specs are wrong or stale, the page fails its purpose.

### Constraints

- **Tech stack**: Windows PowerShell 5.1 STA + inbox .NET/WPF only — no new packages, modules, or build tools
- **Compatibility**: Windows 10/11 Home/Pro/LTSC/IoT/Server, x64, Administrator required
- **Performance**: Live spec queries on every Home show must stay fast and off the UI thread
- **UI consistency**: Card grid must fit the existing dark-theme XAML (`Ink` tokens, `Bg S1 S2 Bd Tx Mu` resources)

## Technology Stack

## Languages

- PowerShell 5.1 (Windows PowerShell) - All logic: `Akari.ps1`, `IWR.ps1`, `Tweaks/*.ps1`
- XAML (WPF markup) - Declarative UI in `UI/MainWindow.xaml`
- Batch (`.cmd`) - Execution-policy bootstrap in `AllowScripts.cmd`
- Inline C# (P/Invoke signature only) - Single `DllImport("dwmapi.dll")` declaration in `Akari.ps1:16`

## Runtime

- Windows PowerShell 5.1 (`powershell.exe`, NOT PowerShell 7 / `pwsh`). Enforced by `#requires -Version 5.1` in `Akari.ps1:1` and explicit `powershell.exe -STA` relaunch in `Akari.ps1:11` and `IWR.ps1:66`
- .NET Framework (inbox WPF stack) + STA apartment thread (required by WPF; checked in `Akari.ps1:7`)
- Must run elevated (Administrator); self-elevates via `Start-Process -Verb RunAs` in `Akari.ps1:11` and `IWR.ps1:22`
- None. No `package.json`, `requirements.txt`, `Cargo.toml`, `go.mod`, `*.csproj`, `*.sln`, or module manifest (`.psd1`) anywhere in repo
- Lockfile: missing (not applicable — zero package dependencies)

## Frameworks

- WPF (`PresentationFramework, PresentationCore, WindowsBase, System.Xaml` loaded via `Add-Type` in `Akari.ps1:15`) - Entire UI; windows parsed with `[Windows.Markup.XamlReader]::Parse` (`Akari.ps1:103,172`)
- `System.Windows.Forms` + `System.Drawing` - Folder/file dialogs and wallpaper image manipulation in tweak scripts (e.g. `Tweaks/Windows.ps1:718,721`)
- .NET Runspaces (`[runspacefactory]::CreateRunspace()` in `Akari.ps1:227`) - Background execution of tweak `Apply`/`Revert`/`Check` scriptblocks so the UI stays responsive
- `Windows.Threading.DispatcherTimer` (150 ms tick, `Akari.ps1:237`) - Drains the log queue and completes background jobs on the UI thread
- Pester 3.4 (ships with Windows 10/11; dev tooling only, never loaded by the app) - Tests in `Tests/*.Tests.ps1`, run by `Tests/Run.ps1` (see Testing below)
- None. No build tool, bundler, linter config (`.eslintrc`, `.prettierrc`, `PSScriptAnalyzerSettings.psd1`), or formatter. Files run directly from source: `powershell -ExecutionPolicy Bypass -File Akari.ps1`

## Key Dependencies

- None (third-party). Every `Add-Type` target (`PresentationFramework`, `System.Windows.Forms`, `System.Drawing`, `System.Xaml`) is an inbox .NET Framework assembly. No `Import-Module` of external modules detected
- COM automation (inbox Windows): `WScript.Shell` (shortcut creation) and `Shell.Application` (Desktop path) used across `Tweaks/Installers.ps1` (e.g. lines 24-29, 56-67)
- CIM/WMI (inbox): `Get-CimInstance Win32_ComputerSystem` (RAM size, `Akari.ps1:347`), `Win32_Service` (TrustedInstaller hijack helper, `Akari.ps1:88`), `Get-Service` / `Get-ScheduledTask` (installer cleanup, `Tweaks/Installers.ps1:102-109`)
- Windows Registry (via `reg.exe`, `Set-ItemProperty`/`New-ItemProperty` helpers) - Primary configuration/tweak surface (`HKLM:\SYSTEM\CurrentControlSet\Control`, browser policy keys, PowerShell `ShellIds`)
- `Expand-Archive` / `Invoke-WebRequest` (aliased `IWR`) - Download-and-install pipeline used by every installer and driver script (e.g. `Tweaks/Installers.ps1:10`, `Tweaks/Graphics.ps1:207-213`)
- `dwmapi.dll!DwmSetWindowAttribute(attr 20)` via P/Invoke (`Akari.ps1:16,116`) - Forces dark title bar

## Configuration

- No `.env` files, no secrets, no env-var-based config. Presence check only: no `.env*`, `credentials*`, `*.pem`/`*.key` files exist in repo
- Runtime state is local-only:
- Execution policy is mutated on the machine (not per-project config): `AllowScripts.cmd:29-32` and `IWR.ps1:52-54` write `HKCR\Applications\powershell.exe\shell\open\command` and `HKCU/HKLM\...\ShellIds\Microsoft.PowerShell\ExecutionPolicy = Unrestricted`
- No build config files (`tsconfig.json`, `*.config.*`, `.nvmrc`, `Makefile`, CI YAML all absent)

## Platform Requirements

- Windows 10/11 machine with Windows PowerShell 5.1 and .NET Framework WPF stack; Administrator shell; edit `.ps1`/`.xaml` with any text editor — no toolchain install needed
- Windows 10/11 Home/Pro/LTSC/IoT/Server, x64, online access (`README.md:6-8`); Administrator + reboot required for tweaks to apply (`README.md:4`); single static asset pair `Assets/AkariLogo.png` / `Assets/AkariLogo.ico` loaded at `Akari.ps1:106-112`

## Conventions

## Naming Patterns

- Category registration files: PascalCase singular — `Tweaks/Check.ps1`, `Tweaks/Windows.ps1`, `Tweaks/Setup.ps1`, `Tweaks/Refresh.ps1`, `Tweaks/Installers.ps1`, `Tweaks/Graphics.ps1`, `Tweaks/Hardware.ps1`, `Tweaks/Advanced.ps1`.
- Host/launcher: `Akari.ps1` (WPF app), `IWR.ps1` (bootstrapper), `AllowScripts.cmd` (batch helper), `UI/MainWindow.xaml` (view).
- Tweak IDs (the `-Id` argument): kebab-case, lowercase — e.g. `'bios-check'`, `'start-taskbar'`, `'memory-compression'`, `'adv-defender'` in `Tweaks/Check.ps1`, `Tweaks/Windows.ps1`, `Tweaks/Setup.ps1`, `Tweaks/Advanced.ps1`.
- Use approved PowerShell verbs in PascalCase with a dash: `Add-Tweak`, `Write-Log`, `Write-ErrLog`, `Set-Reg`, `Remove-Reg`, `Run-Trusted`, `Get-State`, `Update-Row`, `Show-Page`, `Set-Busy`, `Invoke-Code`, `Confirm-Run`, `Save-State`, `Read-Prio`, `Set-Prio`, `Read-Svc`, `Set-Svc`, `Get-Chip`, `Update-Tuner`, `Set-Chips`, `Get-RamKB`, `Get-SvcTarget`, `Add-Log`, `New-Row` — all defined in `Akari.ps1`.
- The `Run-Trusted` helper is duplicated verbatim inside tweak bodies that need TrustedInstaller (e.g. `Tweaks/Advanced.ps1` Defender Apply/Revert blocks). When adding a TrustedInstaller tweak, copy that exact function rather than inventing a new privilege-escalation path.
- XAML-code-behind style helpers in `Akari.ps1` use `Verb-Noun` even for UI plumbing (`New-Row`, `Update-Row`, `Show-Page`).
- Script scope for shared mutable state in `Akari.ps1`: `$script:Tweaks`, `$script:RowCache`, `$script:Cat`, `$script:Busy`, `$script:Job`, `$script:Queue`, `$script:State`.
- UI element shortcuts are single PascalCase words via `Set-Variable`: `$Nav`, `$Search`, `$Heading`, `$Tuner`, `$SvcTuner`, `$SvcCur`, `$Rows`, `$Page`, `$Log`, `$Hex`, `$Dec`, `$Logo` (`Akari.ps1` line ~104).
- Tweak bodies use lowercase `$camelCase`/descriptive locals (`$TaskbarClean`, `$DefenderDisable`, `$windowssecuritysettings`, `$notifyiconsettings`, `$regAliases`, `$basePath`, `$keyPath`) and environment paths `$env:SystemRoot`, `$env:SystemDrive`, `$env:USERPROFILE`, `$env:LOCALAPPDATA`, `$env:ProgramData`.
- Registry roots written as `HKLM:` / `HKCU:` PSDrives in PowerShell cmdlets but as `HKLM\…` / `HKCU\…` string literals inside `cmd /c "reg add …"` strings. Keep whichever form the surrounding block already uses; do not mix within one command.
- `Add-Tweak` parameters constrain vocab with `ValidateSet` — copy exactly (`Akari.ps1` lines 40–45):
- Group sub-actions are hashtables with keys `Name`, `Description`, `Button`, `Block`, optional `Confirm` — e.g. the `bloatware` Group in `Tweaks/Windows.ps1` and the `rebar` Group in `Tweaks/Advanced.ps1`.

## Code Style

- No formatter config in repo (no `.editorconfig`, no `PSScriptAnalyzerSettings.psd1`, no Prettier/ESLint — PowerShell-only repo, those tools do not apply).
- De-facto style: 4-space indent in `Akari.ps1` core; tweak `Apply`/`Revert`/`Check` scriptblock bodies are emitted at column 0 (no indent) — match the surrounding file, do not "fix" indentation inside tweak bodies.
- Line continuation with backtick + aligned `-Parameter` pairs for `Add-Tweak` registrations:
- Quoting: single quotes for static strings, double quotes only when interpolating (`"$Root\$sub"`, `"Win32PrioritySeparation = $hex"`). Escaped quotes inside `cmd /c "reg add `"`"…" strings use the backtick-doublequote form — preserve it exactly.
- Only version gate in the repo: `#requires -Version 5.1` at the top of `Akari.ps1`. New entry-point scripts must start with the same line.
- None configured. No CI, no `.github/` workflows, no PSScriptAnalyzer settings file. If you run the linter locally, use `Invoke-ScriptAnalyzer -Path` with default rules and treat `PSAvoidUsingCmdletAliases`, `PSAvoidUsingWriteHost` (see Logging exception below), and `PSUseDeclaredVarsMoreThanAssignments` as informational for this codebase.

## Import Organization

- None (no module system, no `New-Alias`, no bundler aliases). Resolve repo-relative paths from `$Root`/`$PSScriptRoot` with `Join-Path` or `"$Root\UI\MainWindow.xaml"` interpolation. Never hardcode `C:\AkariOS-Ultimate` except in `IWR.ps1` (its `$root = "C:\AkariOS-Ultimate"` install target is intentional).

## Error Handling

- Default posture is *suppress-and-continue*: append `-ErrorAction SilentlyContinue | Out-Null` to destructive/optional operations (`Remove-Item`, `Stop-Process`, `Get-ItemProperty`, `Disable-MMAgent`, `Remove-AppxPackage`, `Unblock-File`). Example from `Tweaks/Setup.ps1`:
- Swallow blocks for best-effort probes: `try { … } catch { }` with an empty catch (state-file load in `Akari.ps1` line 62, `Disable-BitLocker` loop in `Tweaks/Setup.ps1`).
- Registry-via-`cmd` silencing: every `cmd /c "reg add/delete …"` ends with `>nul 2>&1` (hundreds of instances in `Tweaks/Windows.ps1`, `Tweaks/Advanced.ps1`). Always include the redirect on new `cmd /c reg …` lines.
- Host-level safety nets (do not remove): the file-top `trap { Write-ErrLog …; Show message box; exit }` (`Akari.ps1` line 28) and the `$window.Dispatcher.Add_UnhandledException({ … $ev.Handled = $true; Add-Log …; Set-Busy $false })` handler (`Akari.ps1` lines 382–388).
- Runspace execution wraps every tweak body: `try { & { <code> } *>&1 | Out-String -Stream | … } catch { Write-Log ('Error: ' + $_.Exception.Message) }` (`Invoke-Code` in `Akari.ps1` line 232), plus `EndInvoke` in try/catch and draining `$j.Ps.Streams.Error` into the log (lines 244–245). Tweak code itself must not try to surface errors modally — `Write-Log '…'` / `Write-Host '…'` is the channel.
- Do NOT set `$ErrorActionPreference = 'Stop'` or `Set-StrictMode` — the codebase depends on tolerant reads (missing keys, absent services, already-removed packages).

## Logging

- Inside any `Add-Tweak` `Apply`/`Revert`/`Check`/`Block` scriptblock, use `Write-Host "Narrative…"` for user-visible progress and `Write-Log '…'` for guard messages. Both land in the log drawer with an `HH:mm:ss` prefix via `Add-Log` (`Akari.ps1` lines 119–122).
- Fatal/host errors go to `%LOCALAPPDATA%\Akari\akari.log` via `Write-ErrLog` (`Akari.ps1` lines 24–27) — reserved for host crashes and UI-thread exceptions, not per-tweak output.
- Rules: never `Write-Output` objects from tweak bodies (output is stringified into the log stream); never pop `MessageBox` from tweak code (only `Akari.ps1` host chrome and `-Confirm` prompts may do that); keep messages in `Title Case: Verb…` form (`"Defender: Disable..."`, `"Memory Compression: Off"`).

## Comments

- Every registry/cmd block gets a one-line lowercase comment naming the intent: `# disable widgets regedit`, `# import reg file`, `# restart explorer`, `# stop store running`, `# create reg file` (pervasive in `Tweaks/Windows.ps1`, `Tweaks/Advanced.ps1`). Add one above each new `reg add/delete`, `schtasks`, `bcdedit`, or service change.
- Precondition/caveat comments stay with the command: `# breaks file explorer`, `# windows 11 breaks msi installers if removed`, `# needs safe boot as trusted installer`, `# can't turn back on` (see AppX/Capability whitelists in `Tweaks/Windows.ps1` and Defender blocks in `Tweaks/Advanced.ps1`).
- `Tweaks/*.ps1` are the single source of truth for every Tweak (see `docs/adr/0001-tweak-catalogue-is-single-source.md`); edit them directly. Their old "GENERATED from the '<N> <Name>' scripts" headers are stale and should be dropped when touched.
- Inline step banners inside bodies are `# <verb> <thing>` lowercase (`# download cpuz`, `# extract files`, `# set start menu apps view to list` in `Tweaks/Check.ps1`, `Tweaks/Windows.ps1`).
- Not applicable (no TypeScript). PowerShell comment-based help (`<# .SYNOPSIS … #>`) is not used anywhere — do not introduce it; follow the banner style above.

## Function Design

## Module Design

## Architecture

## System Overview

```text

```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| Main shell / host | Elevation + STA relaunch, tweak registry (`Add-Tweak`), XAML row generation, page/search rendering, background-runspace execution, log pump, state persistence, two built-in registry tuners | `Akari.ps1` |
| State checker | Detect rules: declared targets + machine readings -> Detect result. Pure logic, no UI, no side effects; dot-sourced by the host and by tests | `StateChecker.ps1` |
| View definition | Single-window layout: sidebar `Nav`, `Search`, `Heading`, `Tuner` + `SvcTuner` panels, `Rows` container, `Log` drawer; `Ink` dark-theme resource tokens | `UI/MainWindow.xaml` |
| Tweak catalog (data) | Eight category files that call `Add-Tweak` to register every tweak; bodies are the actual payload scripts | `Tweaks/Check.ps1`, `Tweaks/Refresh.ps1`, `Tweaks/Setup.ps1`, `Tweaks/Installers.ps1`, `Tweaks/Graphics.ps1`, `Tweaks/Windows.ps1`, `Tweaks/Hardware.ps1`, `Tweaks/Advanced.ps1` |
| Remote bootstrapper | Self-elevates, downloads the `main.zip` from GitHub, extracts to `C:\AkariOS-Ultimate`, relaxes execution policy, unblocks files, launches `Akari.ps1` hidden | `IWR.ps1` |
| Policy helper | Interactive `cmd` menu that sets `Unrestricted` (On) or `Restricted` (Off) execution policy + file unblock | `AllowScripts.cmd` |
| Branding | Window logo / icon (`AkariLogo.png` loaded at `Akari.ps1:106-112`) | `Assets/AkariLogo.png`, `Assets/AkariLogo.ico` |

## Pattern Overview

- Single-file host: all UI logic, threading, and state lives in `Akari.ps1` (~390 lines).
- Declarative tweak DSL: `Add-Tweak -Id -Category -Name -Description -Risk -Kind ...` plus `-Apply / -Revert / -Check` scriptblocks, `-ApplyTarget / -RevertTarget` declared targets that Detect compares: either `.reg` text in a single-quoted here-string (the body imports that same text with `Import-Reg $ApplyTarget '<file>'`, see `start-layout`), or lists of `@{ Path; Name; Value }`, `@{ Path; Name; Absent = $true }`, `@{ Path; KeyAbsent = $true }` registry entries, `@{ Service; StartType | Absent }`, `@{ Task = '\Folder\Name'; Enabled | Absent }`, `@{ Feature; State }` (see `timer-resolution`), power plans and values `@{ ActivePowerScheme }`, `@{ PowerScheme; Subgroup; Setting; AC; DC }`, `@{ PowerScheme; Absent }` (see `power-plan`), boot settings `@{ Boot; Value | Absent }` ( the comment at the top of `StateChecker.ps1` lists every form); plus `-Actions` sub-option arrays (`Add-Tweak` in `Akari.ps1`).
- Dot-source composition: `foreach ($f in Get-ChildItem "$Root\Tweaks" -Filter *.ps1 ...) { . $f.FullName }` (`Akari.ps1:56`) — every `Tweaks/*.ps1` file appends to the shared `$script:Tweaks` list.
- UI-thread isolation: tweak bodies never run on the UI thread; `Invoke-Code` marshals them into a fresh runspace and a `DispatcherTimer` pumps log output back (`Akari.ps1:223-256`).

## Layers

- Purpose: Get the tree onto disk and launch the UI with the right privileges.
- Location: `IWR.ps1`, `AllowScripts.cmd` (repo root).
- Contains: Self-elevation, zip download/extract, registry execution-policy writes, `Unblock-File`.
- Depends on: GitHub release hosting (`AkariOS-Files` binaries), `powershell.exe -STA`.
- Used by: End user copy-pastes the one-liner from `README.md:12-14`.
- Purpose: Owns the window, the tweak registry, rendering, execution, and persistence.
- Location: `Akari.ps1` (repo root).
- Contains: `Add-Tweak`, `New-Row`, `Get-State`/`Update-Row`, `Show-Page`, `Invoke-Code`, `$Helpers` preamble, `Confirm-Run`, tuner functions (`Get-Chip`/`Update-Tuner`/`Set-Chips`/`Read-Prio`/`Set-Prio`, `Get-RamKB`/`Get-SvcTarget`/`Read-Svc`/`Set-Svc`), state load/save.
- Depends on: `UI/MainWindow.xaml`, `Tweaks/*.ps1`, `%LOCALAPPDATA%\Akari\state.json`.
- Used by: Everything — it is the only executable entry point of the app itself.
- Purpose: Declares every tweak and embeds its payload.
- Location: `Tweaks/*.ps1` (8 files, ~700 KB total; `Tweaks/Windows.ps1` ~271 KB is the largest).
- Contains: `Add-Tweak` calls only; no functions, no control flow of their own. Tweak counts per file: `Check` 6, `Refresh` 7, `Setup` 12, `Installers` 30, `Graphics` 14, `Windows` 31, `Hardware` 8, `Advanced` 19.
- Depends on: The `Add-Tweak` function and `$Helpers` (`Write-Log`, `Set-Reg`, `Run-Trusted`, `Write-Host` shim) provided by the host.
- Used by: `Akari.ps1:56` dot-sources all of them at startup.
- Purpose: Static window chrome and styling; all dynamic rows are generated in code.
- Location: `UI/MainWindow.xaml`.
- Contains: Resource tokens (`Bg S1 S2 Bd Tx Mu Inv InvT Warn Bad`), `Btn`/`BtnP`/`Nav`/`Chip`/`Flat` styles, named elements the host grabs via `FindName` (`Nav Search Heading Tuner SvcTuner SvcCur Rows Page Log Hex Dec Logo` — `Akari.ps1:104`).
- Depends on: Nothing at rest; the host parses it with `XamlReader::Parse` (`Akari.ps1:103`).
- Used by: `Akari.ps1` exclusively.

## Data Flow

### Primary Request Path (run a tweak)

### Console-kind Flow (interactive scripts)

### Toggle-state Flow

- In-memory: `$script:Tweaks` (registry), `$script:RowCache` (rendered rows), `$script:Cat` (default `'Windows'`), `$script:Busy` / `$script:Job` (runspace guard), `$script:Queue` (log channel), `$script:State` (toggle memory).
- On disk: `%LOCALAPPDATA%\Akari\state.json` (toggle memory, written by `Save-State`, `Akari.ps1:64-67`); `%LOCALAPPDATA%\Akari\akari.log` (startup/UI errors via `Write-ErrLog`).

## Key Abstractions

- Purpose: Single unit of user-visible functionality; everything in the UI derives from it.
- Examples: `Tweaks/Check.ps1:3` (Action), `Tweaks/Setup.ps1:3` (Toggle with Apply+Revert), `Tweaks/Refresh.ps1:15` (Group with `-Actions`), `Tweaks/Refresh.ps1:40` (Console with `-Script`), `widgets` / `gamebar` in `Tweaks/Windows.ps1` (Toggle with `-ApplyTarget`/`-RevertTarget`).
- Pattern: `Add-Tweak -Id <slug> -Category <1 of 8> -Kind <Toggle|Action|Group|Console> -Risk <Safe|Caution|Advanced> [-Button <label>] [-Confirm <text>] [-Script <relpath>] [-Apply {}] [-Revert {}] [-Check {}] [-ApplyTarget <.reg text | @(...)>] [-RevertTarget <.reg text | @(...)>] [-Actions @(@{Name; Description; Button; [Confirm]; Block})]` — defaults are `Risk Safe`, `Kind Toggle`, `Button 'Run'` (`Add-Tweak` in `Akari.ps1`).
- Purpose: Determines which buttons `New-Row` renders and what the click handler does.
- Examples: Toggle `memory-compression` (`Tweaks/Setup.ps1:37` — Optimize/Default + optional Check); Action `storage-check` (`Tweaks/Check.ps1:46`); Group `reinstall` (`Tweaks/Refresh.ps1:15` — expandable `Options` sub-rows) and `bloatware` (`Tweaks/Windows.ps1:863` — main `Remove all` + Options); Console `autounattend` (`Tweaks/Refresh.ps1:40`).
- Pattern: `New-Row` branches on `$t.Kind` (`Akari.ps1:129-138`); the click handler `switch ($kind)` handles `Apply/Revert/Check/Run/Sub/Expand` (`Akari.ps1:272-289`).
- Purpose: Gives background-executed tweak bodies logging, registry helpers, and console-script compatibility shims.
- Examples: Defined `Akari.ps1:70-100`, prepended to every body in `Invoke-Code` (`Akari.ps1:232`).
- Pattern: `Write-Log` (queue), `Write-Host` override (routes to log), `Clear-Host`/`show-menu`/`Pause` no-ops (so legacy bodies don't hang or clear), `Set-Reg`/`Remove-Reg`, `Run-Trusted` (TrustedInstaller hijack for Defender/protected keys — also embedded inline in some tweak bodies such as `Tweaks/Advanced.ps1:12-36`).
- Purpose: Visual severity signal; mapped to theme brushes (`Safe→Mu` grey, `Caution→Warn` amber, `Advanced→Bad` red) in `New-Row` (`Akari.ps1:127,165`).

## Entry Points

- Location: `IWR.ps1` (repo root).
- Triggers: User pastes `iwr '.../IWR.ps1' -useb | iex` into an elevated PowerShell (`README.md:12-14`).
- Responsibilities: Self-elevate (re-fetch via URL when `$PSCommandPath` is empty, `IWR.ps1:17-24`); wipe `C:\AkariOS-Ultimate` + staging; download/extract/rename/move; relax execution policy via `reg add`; `Unblock-File`; launch `Akari.ps1` hidden (`IWR.ps1:66`).
- Location: `Akari.ps1` (repo root; run with `powershell -ExecutionPolicy Bypass -File Akari.ps1`, optional `-ShowConsole`).
- Triggers: Double-click (after `AllowScripts.cmd`), `IWR.ps1`, or manual launch.
- Responsibilities: Everything described in the host layer; `$window.ShowDialog()` (`Akari.ps1:390`) is the message loop. Requires Windows PowerShell 5.1 STA + admin (`#requires -Version 5.1`, relaunch logic `Akari.ps1:6-13`).
- Location: `AllowScripts.cmd` (repo root).
- Triggers: Manual double-click by a user who downloaded the zip.
- Responsibilities: UAC self-elevation, then menu: option 1 writes `Unrestricted` policy keys + unblocks files; option 2 writes `Restricted` (lockdown).
- Location: `Akari.ps1:307-373`; panels `Tuner`/`SvcTuner` in `UI/MainWindow.xaml:209-279`, shown only when `$script:Cat -eq 'Advanced'` (`Akari.ps1:204-206`).
- Triggers: Chip radio buttons + Read/Default/Apply buttons.
- Responsibilities: Compose/read/write `Win32PrioritySeparation` bitfields (`QL/QT/FB` chips → hex+decimal, `Akari.ps1:312-332`) and `SvcHostSplitThresholdInKB` presets (Windows default 3670016 / Match RAM / Never split, `Akari.ps1:346-370`). These bypass the tweak registry — they call `Invoke-Code` directly with generated `Set-Reg` snippets.

## Architectural Constraints

- **Threading:** Single UI thread + exactly one background runspace at a time (`$script:Busy` guard, `Akari.ps1:224`). The `DispatcherTimer` tick is the only cross-thread bridge, via the `ConcurrentQueue`. Concurrent tweak runs are impossible by design.
- **Global state:** All shared state is script-scope in `Akari.ps1`: `$script:Tweaks`, `$script:RowCache`, `$script:Cat`, `$script:Busy`, `$script:Job`, `$script:Queue`, `$script:State`, plus the `$window`-bound named controls. Tweak files assume these globals exist.
- **Circular imports:** None possible — composition is one-directional dot-sourcing (`Akari.ps1` → `Tweaks/*.ps1`); tweak files must not dot-source each other.
- **Host coupling:** Every `Tweaks/*.ps1` body implicitly depends on `$Helpers` functions and on legacy-console shims; bodies copied from standalone scripts only work because `Write-Host`/`Pause`/`Clear-Host` are redefined in the runspace.
- **Platform lock-in:** Windows-only (WPF `PresentationFramework`, HKLM/HKCU registry, `TrustedInstaller`, AppX, `ms-settings:` URIs). PowerShell 5.1 STA required; not PowerShell 7 compatible (uses `powershell.exe` explicitly throughout).
- **Elevation:** The whole process runs as admin; there is no least-privilege separation between Safe tweaks and Advanced ones.

## Anti-Patterns

### TrustedInstaller service hijack as a library function

## Error Handling

- Startup trap: `trap { Write-ErrLog ...; MessageBox; exit }` (`Akari.ps1:28`) — full stop with `akari.log` entry.
- Runspace guard: `Invoke-Code` wraps bodies in `try/catch` that `Write-Log ('Error: ' + ...)`; completion handler also drains `$ps.Streams.Error` (`Akari.ps1:232, 243-245`).
- UI-thread guard: `Dispatcher.UnhandledException` marks handled, logs to drawer + file, resets `$script:Busy` (`Akari.ps1:382-388`).
- Defensive reads: the background Detect read reports an unreadable value as Unknown with its reason in the log drawer, and rows still unanswered at the deadline become Unknown; registry reads use `-ErrorAction SilentlyContinue` throughout tweak bodies; `Confirm-Run` gates destructive actions.

## Testing

Run every test with one command from the repo root (Windows PowerShell 5.1, built-in Pester 3.4, nothing to install):

```
powershell -NoProfile -ExecutionPolicy Bypass -File Tests\Run.ps1
```

It prints pass/fail per test and exits with the number of failed tests (0 = all passed).

- Tests cover `StateChecker.ps1` only, through its public functions: fake targets/readings in, Detect result out. They never read or write the real registry, services or UI. One exception reads source: `Tests\RegTargets.Tests.ps1` parses `Tweaks\*.ps1` (without running it) so every embedded `.reg` payload must parse.
- Use Pester 3 syntax (`Describe`/`It`/`Should Be`); `Tests\Run.ps1` loads the newest Pester 3.x/4.x and fails if only Pester 5 is installed.
- New test files go in `Tests\` named `<Thing>.Tests.ps1` and dot-source what they test from `$PSScriptRoot\..`.

## Cross-Cutting Concerns

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues on `isleap9/AkariOS-Ultimate` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one root `CONTEXT.md` plus `docs/adr/`, both created when first needed. See `docs/agents/domain.md`.
