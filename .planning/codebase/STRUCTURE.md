# Codebase Structure

**Analysis Date:** 2026-10-08

## Directory Layout

```
AkariOS-Ultimate/
├── Akari.ps1           # Main app: WPF host, tweak registry, execution engine (~390 lines)
├── IWR.ps1             # Remote bootstrapper: download → extract → launch
├── AllowScripts.cmd    # Execution-policy on/off helper (interactive menu)
├── README.md           # One-liner install, requirements, credits
├── LICENSE             # MIT (via upstream FR33THY/Ultimate rebrand)
├── .gitignore
├── UI/
│   └── MainWindow.xaml # Single-window view: sidebar, search, tuners, rows, log
├── Tweaks/             # GENERATED tweak catalog: 8 category files (~700 KB)
│   ├── Check.ps1       # 6 tweaks
│   ├── Refresh.ps1     # 7 tweaks
│   ├── Setup.ps1       # 12 tweaks
│   ├── Installers.ps1  # 30 tweaks
│   ├── Graphics.ps1    # 14 tweaks
│   ├── Windows.ps1     # 31 tweaks (~271 KB, largest)
│   ├── Hardware.ps1    # 8 tweaks
│   └── Advanced.ps1    # 19 tweaks
├── 1 Check/            # 6 standalone console scripts (source for Tweaks/Check.ps1)
├── 2 Refresh/          # 7 standalone scripts (source for Tweaks/Refresh.ps1)
├── 3 Setup/            # 12 standalone scripts (source for Tweaks/Setup.ps1)
├── 4 Installers/       # 2 standalone scripts (source for Tweaks/Installers.ps1)
├── 5 Graphics/         # 14 standalone scripts (source for Tweaks/Graphics.ps1)
├── 6 Windows/          # 36 standalone scripts (source for Tweaks/Windows.ps1)
├── 7 Hardware/         # 8 standalone scripts (source for Tweaks/Hardware.ps1)
├── 8 Advanced/         # 19 standalone scripts (source for Tweaks/Advanced.ps1)
└── Assets/
    ├── AkariLogo.png   # Window logo + icon (loaded by Akari.ps1:106-112)
    └── AkariLogo.ico   # Icon file (not referenced in code; PNG is used)
```

## Directory Purposes

**Repo root:**
- Purpose: Entry points and project metadata — the only files a user touches directly.
- Contains: 3 launch scripts (`Akari.ps1`, `IWR.ps1`, `AllowScripts.cmd`), `README.md`, `LICENSE`, `.gitignore`.
- Key files: `Akari.ps1` (the application), `IWR.ps1` (the installer one-liner target).

**`UI/`:**
- Purpose: View layer — exactly one file.
- Contains: `MainWindow.xaml` (~15 KB, 292 lines): resource tokens, control styles, static layout. Dynamic tweak rows are NOT here; `Akari.ps1:125-173` generates them at runtime.
- Key files: `UI/MainWindow.xaml`.

**`Tweaks/`:**
- Purpose: The tweak catalog the app actually runs — 8 GENERATED category files, one per nav tab.
- Contains: Only `Add-Tweak` calls with embedded `-Apply`/`-Revert`/`-Detect`/`-Check` scriptblocks and `-Actions` arrays. File header comments name the source folder (e.g. `Tweaks/Windows.ps1:1`).
- Key files: `Tweaks/Windows.ps1` (31 tweaks, control-panel mega-tweak at line 1717 spans ~3000 lines), `Tweaks/Installers.ps1` (30 download-and-install tweaks), `Tweaks/Advanced.ps1` (19 high-risk tweaks incl. `services` at line 1098, ~1900 lines).

**`1 Check/` … `8 Advanced/` (numbered source folders):**
- Purpose: Original standalone console scripts — each is double-clickable, self-elevating, pausable.
- Contains: Numbered `.ps1` files (`"<n> <Name>.ps1"`); each starts with the ADMIN + INTERNET preamble (see `1 Check\1 Bios Check.ps1:1-16`) and ends with `Pause`. Sizes range from 23 bytes (check stubs like `6 Windows\18 Bloatware TaskMgr Check.ps1`) to ~115 KB (`6 Windows\22 Control Panel Settings.ps1`).
- Key files: `8 Advanced\10 Priority.ps1`, `2 Refresh\4 Autounattend.ps1`, `2 Refresh\5 Updates Drivers Block.ps1` (referenced by `Console`-kind tweaks via `-Script`).

**`Assets/`:**
- Purpose: Branding images.
- Contains: `AkariLogo.png` (used), `AkariLogo.ico` (present but unreferenced — the window icon is set from the PNG in `Akari.ps1:111`).
- Key files: `Assets/AkariLogo.png`.

## Key File Locations

**Entry Points:**
- `Akari.ps1`: Main application (run: `powershell -ExecutionPolicy Bypass -File Akari.ps1`, add `-ShowConsole` to keep the console visible).
- `IWR.ps1`: Remote installer (run: `iwr 'https://github.com/isleap9/AkariOS-Ultimate/raw/refs/heads/main/IWR.ps1' -useb | iex` from elevated PowerShell; installs to `C:\AkariOS-Ultimate`).
- `AllowScripts.cmd`: Local policy helper for zip-download users (double-click → menu 1 On / 2 Off).

**Configuration:**
- No config files. Runtime state (not committed): `%LOCALAPPDATA%\Akari\state.json` (toggle memory), `%LOCALAPPDATA%\Akari\akari.log` (error log). There is no settings UI and no `.env`/JSON/YAML config anywhere in the repo.

**Core Logic:**
- `Akari.ps1:40-49` — `Add-Tweak` DSL definition (the schema every catalog file must follow).
- `Akari.ps1:56` — catalog loader (dot-sources `Tweaks/*.ps1`).
- `Akari.ps1:125-218` — row generation (`New-Row`), state dots (`Get-State`/`Update-Row`), page rendering (`Show-Page`).
- `Akari.ps1:223-256` — execution engine (`Invoke-Code` + 150 ms log-pump timer).
- `Akari.ps1:264-304` — input routing (row-button handler + sidebar nav builder).
- `Akari.ps1:307-373` — built-in Advanced-page tuners (priority separation + SvcHost threshold).

**Testing:**
- No tests, no test runner, no test directories. Verification is manual (run the tweak, check the log drawer).

## Naming Conventions

**Files:**
- Standalone scripts: `"<order> <Pascal-Case Name>.ps1"` — e.g. `6 Windows\22 Control Panel Settings.ps1`, `1 Check\5 Storage Ram Cpu Test & Bench.ps1`. Note `&` appears in file names; quoting is required when referencing them.
- Catalog files: `Tweaks/<Category>.ps1` — Pascal-case singular matching the nav tab (`Check Refresh Setup Installers Graphics Windows Hardware Advanced`).
- Tweak IDs: kebab-case slugs — e.g. `bios-check`, `memory-compression`, `driver-debloat`, `start-search-shell`. IDs are used as `RowCache` keys and `state.json` keys, so they must stay unique and stable.
- UI element names: Pascal-case (`Nav Search Heading Tuner SvcTuner SvcCur Rows Page Log Hex Dec Logo`); tuner chips use `PREFIX_index` (`QL_0 QL_1 QL_2 QT_* FB_* SV_*`).

**Directories:**
- Source folders: `"<order> <Category>"` with a leading digit that defines nav order — `1 Check`, `2 Refresh`, `3 Setup`, `4 Installers`, `5 Graphics`, `6 Windows`, `7 Hardware`, `8 Advanced`. The digit is cosmetic for folders but load-bearing for `-Script` relative paths (e.g. `-Script '8 Advanced\10 Priority.ps1'` in `Tweaks/Advanced.ps1:940`), so never rename these folders without updating `Tweaks/*.ps1`.
- System folders: `UI/`, `Tweaks/`, `Assets/` (Pascal-case, no prefix).

## Where to Add New Code

**New tweak in an existing category (the common case):**
- Primary code: append an `Add-Tweak` call to the matching `Tweaks/<Category>.ps1`, following the file's existing pattern (copy the nearest neighbor: Toggle with Apply/Revert for on/off settings — see `Tweaks/Setup.ps1:37-64`; Action for open/download/run-once — see `Tweaks/Check.ps1:46-69`; Group with `-Actions @(...)` for multi-option — see `Tweaks/Refresh.ps1:15-38`; Console with `-Script '<folder>\<file>.ps1'` for interactive flows — see `Tweaks/Refresh.ps1:40-41`).
- Source mirror: add/update the corresponding standalone script in the numbered folder (`N <Category>\`) with the ADMIN + INTERNET preamble and trailing `Pause`, since `Tweaks/` files are GENERATED from those.
- Tests: none exist; verify manually by launching with `-ShowConsole` and watching the log drawer.
- Risk/metadata rules: set `-Risk` honestly (`Safe` grey / `Caution` amber / `Advanced` red); add `-Confirm '...'` for anything destructive (pattern: `Tweaks/Windows.ps1:863`); add `-Revert` whenever a safe undo exists (its absence disables the Default button with a tooltip, `Akari.ps1:135-136`); add `-Detect { ... }` returning `[bool]` only when a cheap registry check exists.

**New category (new nav tab — rare):**
- Implementation: create `Tweaks/<NewCat>.ps1` with `Add-Tweak -Category '<NewCat>'` entries; add `'<NewCat>'` to the sidebar list in `Akari.ps1:293`; optionally create a numbered source folder and reference it from `Console`-kind `-Script` paths. Default landing tab is `$script:Cat = 'Windows'` (`Akari.ps1:34`) — change only deliberately.

**New built-in tuner (registry bitfield UI on the Advanced page):**
- Implementation: add a `Border` panel next to `Tuner`/`SvcTuner` in `UI/MainWindow.xaml:208-279`, name it, grab it in `Akari.ps1:104`, wire Read/Default/Apply handlers like `Akari.ps1:333-343`, and gate visibility in `Show-Page` (`Akari.ps1:204-206`).

**Utilities / shared helpers:**
- Shared helpers: the `$Helpers` heredoc in `Akari.ps1:70-100` (available inside every background runspace: `Write-Log`, `Write-Host` shim, `Clear-Host`/`show-menu`/`Pause` no-ops, `Set-Reg`, `Remove-Reg`, `Run-Trusted`). Do NOT duplicate `Run-Trusted` into tweak bodies — use the preamble version.

## Special Directories

**`Tweaks/` (generated, committed):**
- Purpose: Runtime catalog; the only code the app loads.
- Generated: Yes (headers claim GENERATED status, but no generator script exists in the repo — regeneration is manual).
- Committed: Yes.

**Numbered folders (`1 Check/` … `8 Advanced/`):**
- Purpose: Human-readable sources + standalone console UX.
- Generated: No — these are the sources of truth.
- Committed: Yes.

**`%LOCALAPPDATA%\Akari\` (runtime, NOT in repo):**
- Purpose: Holds `state.json` and `akari.log` created at runtime.
- Generated: Yes, at runtime.
- Committed: No.

---

*Structure analysis: 2026-10-08*
