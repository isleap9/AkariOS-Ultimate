<!-- refreshed: 2026-10-08 -->
# Architecture

**Analysis Date:** 2026-10-08

## System Overview

AkariOS Ultimate is a single-host Windows desktop tweaking tool: one PowerShell + WPF
shell (`Akari.ps1`) that loads a registry of ~127 tweak definitions from
dot-sourced data files, renders them as rows in a window, and executes the chosen
tweak in a background runspace. There is no build step, no module system, no
client/server split — everything runs in one elevated PowerShell process.

```text
┌─────────────────────────────────────────────────────────────┐
│                    Bootstrapping / Entry                     │
│  `IWR.ps1` (remote downloader)  `AllowScripts.cmd` (policy)  │
└──────────────────────────────┬──────────────────────────────┘
                               │ produces a local tree, then launches
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                      Shell / Host (`Akari.ps1`)              │
│  elevation+STA relaunch · `Add-Tweak` DSL · row rendering    │
│  `Show-Page` · `Invoke-Code` (background runspace)           │
│  `Tuner`/`SvcTuner` (built-in Advanced-page tuners)          │
├──────────────────┬──────────────────┬───────────────────────┤
│   View           │  Tweak catalog   │  Legacy script sources │
│  `UI/MainWindow` │  `Tweaks/*.ps1`  │  `1 Check/`…`8 Adv…/`  │
│  `.xaml`         │  (8 category     │  (numbered standalone  │
│  single window   │   files)         │   console scripts)     │
└────────┬─────────┴────────┬─────────┴──────────┬────────────┘
         │                  │                     │
         ▼                  ▼                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Execution + State (inside `Akari.ps1`)          │
│  background runspace + `ConcurrentQueue` log pump (150 ms)   │
│  `%LOCALAPPDATA%\Akari\state.json` · `%LOCALAPPDATA%\Akari\` │
│  `akari.log`                                                 │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  Windows OS surface (registry HKLM/HKCU, services, AppX,    │
│  power plans, drivers, downloaded installers in              │
│  `%SystemRoot%\Temp`)                                        │
└─────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| Main shell / host | Elevation + STA relaunch, tweak registry (`Add-Tweak`), XAML row generation, page/search rendering, background-runspace execution, log pump, state persistence, two built-in registry tuners | `Akari.ps1` |
| View definition | Single-window layout: sidebar `Nav`, `Search`, `Heading`, `Tuner` + `SvcTuner` panels, `Rows` container, `Log` drawer; `Ink` dark-theme resource tokens | `UI/MainWindow.xaml` |
| Tweak catalog (data) | Eight category files that call `Add-Tweak` to register every tweak; bodies are the actual payload scripts | `Tweaks/Check.ps1`, `Tweaks/Refresh.ps1`, `Tweaks/Setup.ps1`, `Tweaks/Installers.ps1`, `Tweaks/Graphics.ps1`, `Tweaks/Windows.ps1`, `Tweaks/Hardware.ps1`, `Tweaks/Advanced.ps1` |
| Legacy standalone scripts | Original per-task console scripts (`ADMIN` + `INTERNET` preamble, `Pause`); the `Tweaks/*.ps1` files are GENERATED compilations of these | `1 Check/`, `2 Refresh/`, `3 Setup/`, `4 Installers/`, `5 Graphics/`, `6 Windows/`, `7 Hardware/`, `8 Advanced/` |
| Remote bootstrapper | Self-elevates, downloads the `main.zip` from GitHub, extracts to `C:\AkariOS-Ultimate`, relaxes execution policy, unblocks files, launches `Akari.ps1` hidden | `IWR.ps1` |
| Policy helper | Interactive `cmd` menu that sets `Unrestricted` (On) or `Restricted` (Off) execution policy + file unblock | `AllowScripts.cmd` |
| Branding | Window logo / icon (`AkariLogo.png` loaded at `Akari.ps1:106-112`) | `Assets/AkariLogo.png`, `Assets/AkariLogo.ico` |

## Pattern Overview

**Overall:** Plugin-registry UI (data-driven shell) — a thin host renders and runs a
catalog of declarative tweak records. The "plugins" are not DLLs; they are
`Add-Tweak` records whose behavior lives in embedded scriptblocks.

**Key Characteristics:**
- Single-file host: all UI logic, threading, and state lives in `Akari.ps1` (~390 lines).
- Declarative tweak DSL: `Add-Tweak -Id -Category -Name -Description -Risk -Kind ...` plus `-Apply / -Revert / -Detect / -Check` scriptblocks and `-Actions` sub-option arrays (`Akari.ps1:40-49`).
- Dot-source composition: `foreach ($f in Get-ChildItem "$Root\Tweaks" -Filter *.ps1 ...) { . $f.FullName }` (`Akari.ps1:56`) — every `Tweaks/*.ps1` file appends to the shared `$script:Tweaks` list.
- GENERATED data layer: each `Tweaks/*.ps1` header states it is GENERATED from the corresponding numbered folder (e.g. `# Check category. GENERATED from the AkariOS-Ultimate '1 Check' scripts.` in `Tweaks/Check.ps1:1`).
- UI-thread isolation: tweak bodies never run on the UI thread; `Invoke-Code` marshals them into a fresh runspace and a `DispatcherTimer` pumps log output back (`Akari.ps1:223-256`).

## Layers

**Bootstrap layer:**
- Purpose: Get the tree onto disk and launch the UI with the right privileges.
- Location: `IWR.ps1`, `AllowScripts.cmd` (repo root).
- Contains: Self-elevation, zip download/extract, registry execution-policy writes, `Unblock-File`.
- Depends on: GitHub release hosting (`AkariOS-Files` binaries), `powershell.exe -STA`.
- Used by: End user copy-pastes the one-liner from `README.md:12-14`.

**Host / shell layer:**
- Purpose: Owns the window, the tweak registry, rendering, execution, and persistence.
- Location: `Akari.ps1` (repo root).
- Contains: `Add-Tweak`, `New-Row`, `Get-State`/`Update-Row`, `Show-Page`, `Invoke-Code`, `$Helpers` preamble, `Confirm-Run`, tuner functions (`Get-Chip`/`Update-Tuner`/`Set-Chips`/`Read-Prio`/`Set-Prio`, `Get-RamKB`/`Get-SvcTarget`/`Read-Svc`/`Set-Svc`), state load/save.
- Depends on: `UI/MainWindow.xaml`, `Tweaks/*.ps1`, `%LOCALAPPDATA%\Akari\state.json`.
- Used by: Everything — it is the only executable entry point of the app itself.

**Catalog / data layer:**
- Purpose: Declares every tweak and embeds its payload.
- Location: `Tweaks/*.ps1` (8 files, ~700 KB total; `Tweaks/Windows.ps1` ~271 KB is the largest).
- Contains: `Add-Tweak` calls only; no functions, no control flow of their own. Tweak counts per file: `Check` 6, `Refresh` 7, `Setup` 12, `Installers` 30, `Graphics` 14, `Windows` 31, `Hardware` 8, `Advanced` 19.
- Depends on: The `Add-Tweak` function and `$Helpers` (`Write-Log`, `Set-Reg`, `Run-Trusted`, `Write-Host` shim) provided by the host.
- Used by: `Akari.ps1:56` dot-sources all of them at startup.

**View layer:**
- Purpose: Static window chrome and styling; all dynamic rows are generated in code.
- Location: `UI/MainWindow.xaml`.
- Contains: Resource tokens (`Bg S1 S2 Bd Tx Mu Inv InvT Warn Bad`), `Btn`/`BtnP`/`Nav`/`Chip`/`Flat` styles, named elements the host grabs via `FindName` (`Nav Search Heading Tuner SvcTuner SvcCur Rows Page Log Hex Dec Logo` — `Akari.ps1:104`).
- Depends on: Nothing at rest; the host parses it with `XamlReader::Parse` (`Akari.ps1:103`).
- Used by: `Akari.ps1` exclusively.

**Legacy source layer:**
- Purpose: Standalone console versions of each task (double-clickable scripts with their own admin-elevation preamble).
- Location: `1 Check/` … `8 Advanced/` numbered folders.
- Contains: Self-contained `.ps1` files (e.g. `1 Check\1 Bios Check.ps1`), including large installers (`4 Installers\1 Installers.ps1` ~45 KB, `4 Installers\2 MSI Afterburner.ps1` ~83 KB).
- Depends on: Nothing in the repo — they run standalone.
- Used by: `Console`-kind tweaks that shell out via `-Script '<folder>\<file>.ps1'` in a new `powershell.exe` window (`Akari.ps1:276-280`); and as the source material for regenerating `Tweaks/*.ps1`.

## Data Flow

### Primary Request Path (run a tweak)

1. Startup — `Akari.ps1:6-13` relaunches itself elevated + STA if needed; `Akari.ps1:103` parses `UI/MainWindow.xaml`; `Akari.ps1:56` dot-sources all `Tweaks/*.ps1` into `$script:Tweaks`; state loads from `%LOCALAPPDATA%\Akari\state.json` (`Akari.ps1:59-63`).
2. Render — `Show-Page` (`Akari.ps1:194-218`) filters `$script:Tweaks` by `$script:Cat` (or search text), builds each row once via `New-Row` (`Akari.ps1:125-173`), caches it in `$script:RowCache`, and paints the state dot via `Update-Row`/`Get-State` (`Akari.ps1:175-192`).
3. Click — the single bubbled click handler on `$Rows` (`Akari.ps1:264-290`) splits the button `Tag` (`"<id>|<kind>|<arg>"`), resolves the tweak record, and optionally gates on `Confirm-Run` (`Akari.ps1:258-261`).
4. Execute — `Invoke-Code` (`Akari.ps1:223-235`) prepends the `$Helpers` preamble to the tweak body, runs it in a fresh runspace via `BeginInvoke`, and sets `$script:Busy` (disables `$Page`).
5. Feedback — the 150 ms `DispatcherTimer` (`Akari.ps1:237-256`) drains the `ConcurrentQueue` log into `Add-Log`, then on completion disposes the runspace, persists Toggle state (`$script:State[$id] = ...; Save-State`), logs `Done:`, re-reads the SvcHost display, and re-renders the page.
6. Errors — runspace exceptions and `$ps.Streams.Error` entries are appended to the log drawer; UI-thread exceptions are caught by `Dispatcher.UnhandledException` (`Akari.ps1:382-388`) and logged instead of crashing; startup failures go to `akari.log` + message box (`Akari.ps1:25-28`).

### Console-kind Flow (interactive scripts)

1. Button with `Kind -eq 'Console'` carries `-Script '2 Refresh\4 Autounattend.ps1'` (e.g. `Tweaks/Refresh.ps1:40`).
2. Handler (`Akari.ps1:277-280`) resolves `Join-Path $Root $t.Script` and starts a **separate** `powershell.exe` window — these scripts run outside the runspace with their own prompts/`Pause`.
3. Only a log line (`"opened in its own console window"`) returns to the main UI.

### Toggle-state Flow

1. `Get-State` (`Akari.ps1:175-181`) prefers a `-Detect` scriptblock result (boolean); falls back to the persisted `$script:State[$Id]`; returns `$null` (dimmed dot) when neither knows.
2. Only two `Detect` implementations exist in the whole catalog (`Tweaks/Windows.ps1:809` widgets, `Tweaks/Windows.ps1:1508` edge-webview region) — every other Toggle relies on `state.json` memory.
3. `Update-Row` (`Akari.ps1:183-192`) paints the dot (`Inv` fill when on, transparent when off, 35% opacity when unknown) and highlights the `Optimize` button via the `BtnP` style.

**State Management:**
- In-memory: `$script:Tweaks` (registry), `$script:RowCache` (rendered rows), `$script:Cat` (default `'Windows'`), `$script:Busy` / `$script:Job` (runspace guard), `$script:Queue` (log channel), `$script:State` (toggle memory).
- On disk: `%LOCALAPPDATA%\Akari\state.json` (toggle memory, written by `Save-State`, `Akari.ps1:64-67`); `%LOCALAPPDATA%\Akari\akari.log` (startup/UI errors via `Write-ErrLog`).

## Key Abstractions

**Tweak record (the core DSL):**
- Purpose: Single unit of user-visible functionality; everything in the UI derives from it.
- Examples: `Tweaks/Check.ps1:3` (Action), `Tweaks/Setup.ps1:3` (Toggle with Apply+Revert), `Tweaks/Refresh.ps1:15` (Group with `-Actions`), `Tweaks/Refresh.ps1:40` (Console with `-Script`), `Tweaks/Windows.ps1:809-811` (Toggle with `-Detect`).
- Pattern: `Add-Tweak -Id <slug> -Category <1 of 8> -Kind <Toggle|Action|Group|Console> -Risk <Safe|Caution|Advanced> [-Button <label>] [-Confirm <text>] [-Script <relpath>] [-Apply {}] [-Revert {}] [-Detect {}] [-Check {}] [-Actions @(@{Name; Description; Button; [Confirm]; Block})]` — defaults are `Risk Safe`, `Kind Toggle`, `Button 'Run'` (`Akari.ps1:40-49`).

**Tweak Kinds (four interaction models):**
- Purpose: Determines which buttons `New-Row` renders and what the click handler does.
- Examples: Toggle `memory-compression` (`Tweaks/Setup.ps1:37` — Optimize/Default + optional Check); Action `storage-check` (`Tweaks/Check.ps1:46`); Group `reinstall` (`Tweaks/Refresh.ps1:15` — expandable `Options` sub-rows) and `bloatware` (`Tweaks/Windows.ps1:863` — main `Remove all` + Options); Console `autounattend` (`Tweaks/Refresh.ps1:40`).
- Pattern: `New-Row` branches on `$t.Kind` (`Akari.ps1:129-138`); the click handler `switch ($kind)` handles `Apply/Revert/Check/Run/Sub/Expand` (`Akari.ps1:272-289`).

**`$Helpers` preamble (runspace standard library):**
- Purpose: Gives background-executed tweak bodies logging, registry helpers, and console-script compatibility shims.
- Examples: Defined `Akari.ps1:70-100`, prepended to every body in `Invoke-Code` (`Akari.ps1:232`).
- Pattern: `Write-Log` (queue), `Write-Host` override (routes to log), `Clear-Host`/`show-menu`/`Pause` no-ops (so legacy bodies don't hang or clear), `Set-Reg`/`Remove-Reg`, `Run-Trusted` (TrustedInstaller hijack for Defender/protected keys — also embedded inline in some tweak bodies such as `Tweaks/Advanced.ps1:12-36`).

**Risk badge:**
- Purpose: Visual severity signal; mapped to theme brushes (`Safe→Mu` grey, `Caution→Warn` amber, `Advanced→Bad` red) in `New-Row` (`Akari.ps1:127,165`).

## Entry Points

**Remote bootstrap (`IWR.ps1`):**
- Location: `IWR.ps1` (repo root).
- Triggers: User pastes `iwr '.../IWR.ps1' -useb | iex` into an elevated PowerShell (`README.md:12-14`).
- Responsibilities: Self-elevate (re-fetch via URL when `$PSCommandPath` is empty, `IWR.ps1:17-24`); wipe `C:\AkariOS-Ultimate` + staging; download/extract/rename/move; relax execution policy via `reg add`; `Unblock-File`; launch `Akari.ps1` hidden (`IWR.ps1:66`).

**Application main (`Akari.ps1`):**
- Location: `Akari.ps1` (repo root; run with `powershell -ExecutionPolicy Bypass -File Akari.ps1`, optional `-ShowConsole`).
- Triggers: Double-click (after `AllowScripts.cmd`), `IWR.ps1`, or manual launch.
- Responsibilities: Everything described in the host layer; `$window.ShowDialog()` (`Akari.ps1:390`) is the message loop. Requires Windows PowerShell 5.1 STA + admin (`#requires -Version 5.1`, relaunch logic `Akari.ps1:6-13`).

**Policy helper (`AllowScripts.cmd`):**
- Location: `AllowScripts.cmd` (repo root).
- Triggers: Manual double-click by a user who downloaded the zip.
- Responsibilities: UAC self-elevation, then menu: option 1 writes `Unrestricted` policy keys + unblocks files; option 2 writes `Restricted` (lockdown).

**Built-in tuners (Advanced page only):**
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

### GENERATED files edited as if they were source

**What happens:** `Tweaks/*.ps1` carry `GENERATED from ...` headers, but there is no generator script in the repo — regeneration appears to be manual copy/adaptation from the numbered folders.
**Why it's wrong:** The numbered folders and `Tweaks/` drift apart silently; a fix applied to one side may never reach the other.
**Do this instead:** Treat the numbered-folder script as the source of truth and re-derive the `Add-Tweak` wrapper from it; when changing a tweak body, mirror the change in the matching numbered-folder file (see STRUCTURE.md "Where to Add New Code").

### TrustedInstaller service hijack as a library function

**What happens:** `Run-Trusted` (`Akari.ps1:85-99`) rewrites the `TrustedInstaller` service `binPath` to run arbitrary commands, then restores it — and the same function is copy-pasted inside tweak bodies (e.g. `Tweaks/Advanced.ps1:12-36`).
**Why it's wrong:** A crash between `sc.exe config` and restore leaves the service broken; duplication means fixes must land in N places.
**Do this instead:** Keep the single `$Helpers` definition as canonical; remove inline copies from tweak bodies so they use the preamble version.

## Error Handling

**Strategy:** Log-and-continue everywhere; modal dialogs only for fatal startup problems.

**Patterns:**
- Startup trap: `trap { Write-ErrLog ...; MessageBox; exit }` (`Akari.ps1:28`) — full stop with `akari.log` entry.
- Runspace guard: `Invoke-Code` wraps bodies in `try/catch` that `Write-Log ('Error: ' + ...)`; completion handler also drains `$ps.Streams.Error` (`Akari.ps1:232, 243-245`).
- UI-thread guard: `Dispatcher.UnhandledException` marks handled, logs to drawer + file, resets `$script:Busy` (`Akari.ps1:382-388`).
- Defensive reads: `Get-State` swallows `Detect` exceptions (`Akari.ps1:177`); registry reads use `-ErrorAction SilentlyContinue` throughout tweak bodies; `Confirm-Run` gates destructive actions.

## Cross-Cutting Concerns

**Logging:** Dual-channel — live `ConcurrentQueue` → `Log` drawer textbox (`Add-Log`, `Akari.ps1:119-122`) for run output; `akari.log` file for host/UI errors (`Write-ErrLog`). Tweak bodies log via `Write-Host` (shimmed) or `Write-Log` directly.
**Validation:** `Add-Tweak` uses `[ValidateSet]` on `Risk`/`Kind` (`Akari.ps1:43-44`); destructive tweaks carry `-Confirm` strings shown via `MessageBox YesNo Warning`. No input validation beyond that — registry values are hardcoded.
**Authentication:** None — the app always runs fully elevated as Administrator; `Run-Trusted` escalates further to TrustedInstaller where registry ACLs require it.

---

*Architecture analysis: 2026-10-08*
