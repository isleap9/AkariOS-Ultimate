# AkariOS-Ultimate

## What This Is

AkariOS-Ultimate is a single-host PowerShell 5.1 + WPF desktop tweaking tool for Windows 10/11 power users: one elevated shell (`Akari.ps1`) renders a registry of ~127 tweaks across 8 categories and executes them in a background runspace with Apply/Revert support.

This work adds a **Home page** — the new default landing tab — that reads the user's machine specs (CPU, memory, graphics, disk, motherboard/BIOS) and Windows version (edition + build) and presents them in a card grid, refreshed live every time Home is shown.

The Home page is complete: it copies the spec sheet to the clipboard, colours disk-free and RAM-pressure values at their thresholds, and recovers from a hung spec read after 20 seconds.

## Core Value

The Home page shows accurate, live system specs at a glance — if the specs are wrong or stale, the page fails its purpose.

## Requirements

### Validated

- ✓ WPF single-window host with sidebar nav, search, rows, and log drawer — existing
- ✓ Tweak catalog of ~127 tweaks across 8 categories (Check, Refresh, Setup, Installers, Graphics, Windows, Hardware, Advanced) — existing
- ✓ Apply/Revert/Detect/Check tweak execution in a background runspace with log pump — existing
- ✓ Toggle state persistence via `%LOCALAPPDATA%\Akari\state.json` — existing
- ✓ Remote bootstrap via `IWR.ps1` one-liner and execution-policy helper `AllowScripts.cmd` — existing
- ✓ Built-in Advanced-page tuners (priority separation + SvcHost threshold) — existing
- ✓ Home page shows CPU details (model, cores, speed) — Phase 3
- ✓ Home page shows memory/RAM (total, used/free) — Phase 3
- ✓ Home page shows graphics/GPU (model, VRAM, driver version where available) — Phase 3
- ✓ Home page shows disk/storage, narrowed to the Windows system drive only (C:) at the user's request — Phase 3
- ✓ Home page shows motherboard + BIOS (board model, BIOS version/date) — Phase 3
- ✓ Home page shows Windows edition + build — Phase 3
- ✓ Home page is the default landing tab on launch — Phase 3
- ✓ Home specs refresh live every time Home is shown, off the UI thread — Phase 3
- ✓ Home layout uses a card grid (CPU, GPU, RAM, Disk, Board, Windows) under a hostname + maker/model header — Phase 3
- ✓ Home page copies the full spec text to the clipboard (Copy specs, with "Copied" feedback) — Phase 4
- ✓ Home page shows health-at-a-glance indicators (disk-free % / RAM pressure threshold coloring) — Phase 4
- ✓ README documents the AkariOS-Ultimate project including the Home page feature — Phase 4

### Active

*(none open for v1.0 — all four phases complete)*

### Out of Scope

- Update status / pending-reboot flag — not requested; defer to later
- License / activation state — not requested; defer to later
- Install date / uptime display — not requested; defer to later
- Hub shortcuts to Check/Refresh pages — user chose plain default landing, not a hub
- Spec editing or actions from Home — Home is read-only overview
- Cross-platform or PowerShell 7 support — app is locked to Windows PowerShell 5.1 STA + WPF

## Context

- Brownfield addition to an existing repo; codebase map exists in `.planning/codebase/` (see ARCHITECTURE.md, STACK.md, STRUCTURE.md).
- Host owns everything: `Akari.ps1` (~1070 lines) — `Add-Tweak` DSL, `New-Row`/`Show-Page` rendering, `Invoke-Code` runspace engine, `$script:Cat` nav state (defaults to `'Home'` since Phase 3), plus the Home spec pipeline (`Get-Specs`, `Get-HomeModel`, `Get-SpecText`, `Start-SpecRead` watchdog).
- View is `UI/MainWindow.xaml` (single window: `Nav Search Heading Tuner SvcTuner Rows Page Log`); dynamic rows are generated in code, not XAML.
- Catalog is `Tweaks/*.ps1` (GENERATED from numbered `1 Check/`…`8 Advanced/` folders — mirror changes in both sides).
- Spec queries must use inbox-only sources (CIM/WMI, registry, .NET) — no new dependencies; app runs fully elevated as Administrator.
- Live-on-open refresh must not block the UI thread — follow the existing `Invoke-Code` background-runspace + DispatcherTimer log-pump pattern.

## Constraints

- **Tech stack**: Windows PowerShell 5.1 STA + inbox .NET/WPF only — no new packages, modules, or build tools
- **Compatibility**: Windows 10/11 Home/Pro/LTSC/IoT/Server, x64, Administrator required
- **Performance**: Live spec queries on every Home show must stay fast and off the UI thread
- **UI consistency**: Card grid must fit the existing dark-theme XAML (`Ink` tokens, `Bg S1 S2 Bd Tx Mu` resources)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Home is the default landing tab | User wants specs-first experience on launch | ✓ Good — Phase 3 (UAT pass) |
| Card grid layout | Chosen over matching existing tweak rows; overview reads better as cards | ✓ Good — Phase 3 (3 columns normal, 2 narrow) |
| Live refresh on every Home show | User chose live over button/cached; specs never stale | ✓ Good — Phase 3 (second runspace, dims while refreshing). Open: no timeout on a hung read (review WR-01) |
| Show all five spec groups + edition/build only | All hardware groups selected; Windows detail limited to edition + build | ✓ Good — Phase 3 |
| GPU VRAM read from registry `HardwareInformation.qwMemorySize` when WMI caps at 4 GB | WMI AdapterRAM is uint32; real VRAM >4 GB needs the registry | ✓ Good — Phase 2 (RTX 5070 reads 11.9 GB) |
| BIOS date formatted in UTC with invariant culture | Avoids off-by-one dates across timezones/cultures | ✓ Good — Phase 2 |
| Disk card shows only the system drive | User request during Phase 3 (too many drives listed); spec read still returns every fixed volume | ✓ Good — Phase 3 (ac5bff8) |
| Copy text is built from the same shared card model the cards render from (`Get-HomeModel`) | One source means the clipboard text can never drift from what is on screen | ✓ Good — Phase 4 (UAT pass) |
| Health colour is suppressed when a group's `_Status` is `Failed` | A failed read must never colour a value with a real threshold brush (D-12) | ✓ Good — Phase 4 |
| Spec-read watchdog: 20 s deadline, abandoned with `BeginStop` and disposed later from the tick | A hung WMI provider must not dim Home for the session, and the UI thread must never block on a pipeline | ✓ Good — Phase 4 (closes review WR-01) |
| Only the spec read may write `$script:SpecData` (result-variable path deleted, not guarded) | A dormant second writer could install a stale-shape composite | ✓ Good — Phase 4 (closes review WR-02) |
| CPU cores/threads are summed across every `Win32_Processor` socket; a Sockets row appears only above 1 | Multi-socket machines were under-reported; single-socket cards must look unchanged | ✓ Good — Phase 4 (closes review WR-03) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-09 after Phase 4*
