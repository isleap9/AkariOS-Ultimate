# Project Research Summary

**Project:** AkariOS-Ultimate — Home system-info dashboard
**Domain:** Read-only system-info overview page in a Windows PowerShell 5.1 + WPF tweaking utility
**Researched:** 2026-10-08
**Confidence:** HIGH

## Executive Summary

AkariOS-Ultimate is a single-host PowerShell 5.1 + WPF tweaking tool (~127 tweaks, `Akari.ps1` + `UI/MainWindow.xaml`). The new work adds a **Home page** — the default landing tab — that shows live CPU, RAM, GPU, disk, motherboard/BIOS, and Windows edition+build specs in a card grid, refreshed every time Home is shown. Experts build this class of page (Speccy summary, Settings > About, msinfo32) as a thin read-only view over inbox CIM/registry sources with per-field graceful degradation; no new dependencies, no polling loops, no edit affordances.

The recommended approach: query with `Get-CimInstance` (never `Get-WmiObject`) plus one registry read (`HKLM:\...\CurrentVersion`), all inside the app's existing background-runspace + DispatcherTimer pattern with placeholder-first rendering. All Home code lives in one delimited section of `Akari.ps1` (~150 new lines); `MainWindow.xaml` needs no structural change; Home must never enter the `$script:Tweaks` registry. Build order is queries → cards → nav wiring → async hardening, in 3 phases (spec engine, quirky-hardware cards, shell + refresh bridge).

The key risks are all well-documented WMI/CIM traps, not unknowns: UI-thread freezes from synchronous queries, RAM totals read from a single DIMM instance, the `AdapterRAM` uint32 4 GB cap / wrong-GPU-picked bug, Win10-mislabeled-on-Win11 OS identity, and null/filler SMBIOS strings on VMs/OEMs. Each has a known prevention pattern with a concrete verification check (see "Looks Done But Isn't" checklist in PITFALLS.md). Mitigation strategy: per-group queries with `-Property`, per-query try/catch → "Not available", a shared formatter helper, and a VM + multi-GPU + DPI test matrix in every phase.

## Key Findings

### Recommended Stack

Inbox-only on Windows 10/11 + PS 5.1 — nothing to install. `Get-CimInstance` supersedes deprecated `Get-WmiObject` (faster, lighter, PS7-compatible). Registry `CurrentVersion` key is the ~1 ms source for edition/build display; `Win32_OperatingSystem` cross-checks it and supplies live free RAM. All 8 CIM classes are `root/cimv2` inbox since Vista. Full details: [STACK.md](./STACK.md).

**Core technologies:**
- `Get-CimInstance` (CimCmdlets, PS 3.0+ inbox): all live hardware/OS queries — deprecated-WMI replacement, `-Property`/`-Filter` trims payload server-side
- Registry `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` via `Get-ItemProperty`: Windows edition + DisplayVersion + CurrentBuildNumber.UBR display string (~1 ms, canonical for human label)
- `Win32_OperatingSystem` (singleton): live `FreePhysicalMemory` + totals + Caption/BuildNumber/OSArchitecture cross-check
- `Win32_Processor` / `Win32_ComputerSystem` + `Win32_PhysicalMemory` sum / `Win32_VideoController` / `Win32_LogicalDisk -Filter "DriveType=3"` / `Win32_BaseBoard` / `Win32_BIOS`: per-card sources; prefer `MaxClockSpeed` over throttled `CurrentClockSpeed`, `PhysicalMemory.Capacity` sum over BIOS-reserved `TotalPhysicalMemory`, `SMBIOSBIOSVersion` over `Version`
- Existing `Invoke-Code` background-runspace + 150 ms log-pump: executes all spec queries off the UI thread — reuse, don't reinvent

Critical version notes: `DisplayVersion` exists only 20H2+ (fall back to `ReleaseId`, then build table); `ConfiguredClockSpeed`/`SMBIOSMemoryType` need Win10+ (graceful `$null` older); `AdapterRAM` is uint32 — wraps above 4 GB, needs `qwMemorySize` registry fallback; `CurrentBuild` is a string — cast to `[int]` before the ≥22000 Win11 gate.

### Expected Features

Speccy-summary pattern scoped to the five PROJECT.md spec groups + Windows card; refresh-on-show (middle ground between static About and polling Task Manager); read-only by omission. Full analysis: [FEATURES.md](./FEATURES.md).

**Must have (table stakes):**
- CPU card (model, cores/threads, base speed) — the lead spec; normalize vendor whitespace
- RAM card (total installed + used/free) — used = total − free; GB with 1 decimal
- GPU card (model + VRAM + driver, ALL adapters enumerated) — never take instance `[0]`
- Disk card (per-volume free/total, `DriveType=3` only) — volumes match user mental model
- Motherboard + BIOS card (board Manufacturer+Product, SMBIOSBIOSVersion + converted ReleaseDate)
- Windows card (edition + friendly version + full build incl. UBR) — Caption-derived, build-gated 10/11
- Default landing + card grid shell — Home must be home on launch
- Live refresh on show (background runspace + loading/placeholder state) — accuracy-is-everything Core Value
- Per-field "n/a" fallbacks — real hardware/VM data is messy; never fail a whole card on one bad query

**Should have (competitive, v1.x):**
- Copy-to-clipboard spec export — highest value/effort ratio; reuses queried values, zero new queries
- Health-at-a-glance indicators (disk-free % / RAM pressure threshold coloring) — presentation-only over existing numbers
- Friendly hostname/manufacturer header — free fields from the existing `Win32_ComputerSystem` object

**Defer (v2+):**
- Expandable per-card detail (per-slot RAM etc.) — doubles card complexity; validate demand first
- Temperature readout — no reliable inbox source (MSAcpi temps often absent/stale); needs forbidden driver dependency
- Update status / activation / uptime / network / benchmarks / hub shortcuts / spec editing — each explicitly out of scope with documented rationale (see Anti-Features)

### Architecture Approach

Home branches off the tweak-registry architecture; it does not extend it. Three new pieces inside `Akari.ps1`, zero new files: a pure-function spec-query layer (`Get-*Spec`), a card renderer following the `New-Row` XAML-technique (`New-HomeCard`/`Show-Home` into the existing `Rows` container), and nav/default-tab wiring (`$script:Cat='Home'`, prepend `'Home'` to nav list, early `Show-Page` branch). Async uses placeholder-first rendering with a synchronized-hashtable result slot (not the log queue) plus a completion guard (`Kind -eq 'Home'` AND still on Home AND no search text). Full design with touch-point line numbers: [ARCHITECTURE.md](./ARCHITECTURE.md).

**Major components:**
1. Spec-query layer — pure inbox CIM/registry reads, no UI refs, runspace-safe; defines the spec-object schema everything consumes
2. Card renderer — code-built cards reusing `S1 Bd Tx Mu` theme tokens; fluid layout (`WrapPanel`/star grid, wrap + ellipsis); theme-consistent with zero XAML changes
3. Nav / default-tab wiring — 2-line change + thin `Show-Page` branch; search path takes precedence; tuner `'Advanced'` exact-match gate untouched
4. Async refresh bridge — dedicated lightweight runspace (leaves `Invoke-Code`/`$script:Job`/`$script:Busy` tweak semantics untouched) + existing timer for completion pickup; separate *render-from-result* from *refresh* to avoid the timer-tail recursion loop

### Critical Pitfalls

Top 7 from [PITFALLS.md](./PITFALLS.md) (all HIGH confidence, all with known fixes):

1. **Synchronous CIM on the UI thread freezes the window** — route ALL spec gathering through background runspace + placeholder cards; never `Get-CimInstance` from `Show-Page`/nav/render code.
2. **RAM total from a single DIMM instance** — `@(...Capacity | Measure-Object -Sum).Sum` with `@()` array guard; prefer `PhysicalMemory` sum (installed) over `TotalPhysicalMemory` (usable); test 1-stick/multi-stick/VM.
3. **Wrong GPU / "4 GB" on 8 GB+ cards** — enumerate all `Win32_VideoController`, filter virtual/mirror adapters, pick discrete (or list all); `qwMemorySize` registry (uint64) fallback for VRAM; keep driver version paired to the selected instance.
4. **"Windows 10" label on Windows 11** — name from WMI `Caption`, 10-vs-11 via `[int]CurrentBuild -ge 22000`, version from `DisplayVersion` with build-table fallback; never `ProductName`/`Environment.OSVersion`/`ReleaseId`-only.
5. **Nulls and SMBIOS filler strings on VMs/OEMs** — single `Get-SpecSafe` + formatter convention mapping `$null`/`""`/`0`/filler blocklist → "Not available"; guard all arithmetic; prefer board `Product` over `Model`.
6. **Default-tab / tuner-gating regression** — explicit `if ($Cat -eq 'Home')` branch separate from `RowCache`; one-place default change; keep `-eq 'Advanced'` gate exact; card clicks are no-ops in the bubbled handler.
7. **Theme/layout breakage at real DPI** — code-built cards, theme brushes only (zero hardcoded colors), fluid layout, test at 125%/150% + min width + longest device names.

Plus integration gotchas: cross-thread writes only via Dispatcher/queue; `BeginInvoke` always paired with `EndInvoke`/dispose (flat handles over 20 visits); `-Property` on every query; single in-flight flag; one runspace per refresh (never 7 parallel); `DriveType=3` + nonzero-size disk filter; never persist specs to `state.json`; never `Run-Trusted` for reads; XML-escape any XAML-injected strings; label static speeds honestly (`Base speed`, never fake-live GHz).

## Implications for Roadmap

Based on research, suggested phase structure (mirrors both ARCHITECTURE.md "Suggested Build Order" and PITFALLS.md "Pitfall-to-Phase Mapping" — they agree):

### Phase 1: Spec engine (CPU + RAM + OS queries, threading, safety conventions)
**Rationale:** Queries are the true foundation — the card shell is empty chrome without data; threading + fallback conventions constrain everything after, and the simplest query groups retire the most pitfalls earliest.
**Delivers:** `Get-HomeSpec` + `Get-CpuSpec`/`Get-MemSpec`/`Get-OsSpec`, background-runspace execution with placeholder-then-fill, `Get-SpecSafe` try/catch + formatter/`Format-Size` helpers, per-query `-Property`; console-testable without launching UI.
**Addresses:** CPU card, RAM card (total + usage), Windows card; live-refresh + loading-state pattern established; per-field n/a fallbacks convention.
**Avoids:** Pitfalls 1 (UI freeze), 2 (RAM sum), 4 (Win10/11), 5 (nulls/fillers); perf traps (`Get-ComputerInfo`, unfiltered queries, 7 runspaces).

### Phase 2: Quirky-hardware cards (GPU + disk + board/BIOS)
**Rationale:** These three cards hold all the hardware-diversity traps; isolated in their own phase so the selection/filter/fallback helpers (`qwMemorySize` VRAM, discrete-first GPU pick, `DriveType=3` disk scope, board `Product`-preference + filler blocklist) get a dedicated verification pass.
**Delivers:** `Get-GpuSpec`/`Get-DiskSpec`/`Get-BoardSpec` with registry VRAM fallback, multi-adapter enumeration, per-volume disk rows, filler-string filtering.
**Uses:** `Win32_VideoController` + display-class `qwMemorySize`, `Win32_LogicalDisk -Filter "DriveType=3"`, `Win32_BaseBoard` + `Win32_BIOS` (SMBIOSBIOSVersion + date conversion).
**Implements:** Full query layer; honest-labeling rules (Base speed, point-in-time used/free, ≥4 GB guard where fallback absent).
**Avoids:** Pitfall 3 (wrong GPU/4 GB cap), disk-scope gotcha (USB/network/DVDs), board filler garbage, headless-VM null crashes.

### Phase 3: Home shell + async refresh hardening
**Rationale:** Card-content phases need a safe container to target; the shell branch must exist before content lands, and the runspace/timer engine touch is the highest-blast-radius change — smallest when built on two already-verified halves.
**Delivers:** `$script:Cat='Home'` default + nav-first wiring + `Show-Page` Home branch (search-precedence, tuner collapse), card-grid shell + one reference card establishing the code-gen/theme-token pattern, `Start-HomeRefresh` + timer completion guard + `$script:HomeRefreshing` in-flight flag, skeleton→live→failure-terminal card states.
**Addresses:** Default landing + card grid shell; live refresh on show; theme/layout consistency.
**Avoids:** Pitfalls 6 (default-tab/tuner regression), 7 (theme/DPI), timer-tail recursion loop, `$script:Busy` latch collision, runspace leaks, search-vs-Home fallthrough, card-click exceptions.

### Phase Ordering Rationale

- **Dependencies flow one way:** queries → cards → shell → async. Each step is independently verifiable (console queries; `Render-HomeCards $sample` with `-ShowConsole`; sync-render routing; then background dispatch) — no big-bang integration.
- **Highest risk retired earliest:** hardware-diversity query traps (Phase 1–2) before the threading-engine touch (Phase 3); the timer/recursion guard is the one detail that must not be built first.
- **Two render paths stay separated:** Home never enters `$script:Tweaks`/`RowCache`/`Update-Row`/`state.json`; the branch is thin (route + chrome), all card logic in `Show-Home`.
- **P2 differentiators slot after Phase 3:** copy-export, health thresholds, hostname header are strictly additive over stable queries — schedule as v1.x polish, not in the initial three phases.

### Research Flags

Phases likely needing deeper research during planning (`/gsd-plan-phase --research-phase`):
- **Phase 2 (GPU VRAM fallback):** matching `qwMemorySize` registry subkeys (`{4d36e968-…}\<nnnn>`) to the selected adapter instance is the least-documented step (MEDIUM confidence, community-sourced) — worth a focused code-pattern check during planning.
- **Phase 3 (timer completion guard):** the recursion/in-flight-flag interaction with the existing tweak-job tail (`Akari.ps1:253` unconditional `Show-Page`) needs careful plan-level design — architecture is clear on intent but the exact edit is line-surgery.

Phases with standard patterns (skip research-phase):
- **Phase 1:** CIM query shapes per class are learn.microsoft.com-documented (HIGH); `Invoke-Code` reuse follows the in-repo precedent directly.
- **Phase 3 card-grid visuals:** `New-Row` code-gen + theme-token pattern is fully repo-grounded; DPI/fluid-layout rules are standard WPF.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All 8 CIM classes + registry keys verified against learn.microsoft.com class docs; deprecation/fallback guidance corroborated across MS docs and community |
| Features | HIGH | Competitor patterns (Speccy/msinfo32/Settings About/WinUtil/Winhance) stable for years; scope matches PROJECT.md five-groups decision exactly |
| Architecture | HIGH | Grounded in direct full-file reads of `Akari.ps1` (390 lines) and `MainWindow.xaml` (292 lines) plus in-repo codebase map; touch points cite exact lines |
| Pitfalls | HIGH | WMI/CIM quirks documented across MS Learn + KBs + a decade of recurring community post-mortems + repo-grounded app specifics |

**Overall confidence:** HIGH

### Gaps to Address

- **Oldest-target verification:** `Win32_*` classes are Vista-era stable, but `DisplayVersion`/`ConfiguredClockSpeed` fallbacks and provider presence should be smoke-tested once on the oldest supported image (Win10 1607/LTSC or oldest Server target) — handle during Phase 1 verification, not further research.
- **GPU registry-fallback adapter matching:** exact subkey-to-adapter correlation code is community-pattern, not MS-documented — validate with a mock (`AdapterRAM=4294967295` + registry value) if no >4 GB card is available at build time (Phase 2 verification).
- **WMI-provider hang durations:** exact stall times are environment-dependent (MEDIUM) — design is hang-proof regardless (placeholder-first + runspace timeout/abandon + failure-terminal cards); confirm abandon path with an injected `Start-Sleep` during Phase 3 verification.
- **Multi-GPU / VM / DPI coverage:** no gap in *what* to do, but the test matrix needs real or mocked instances (iGPU+dGPU laptop, Hyper-V/VBox VM, 125%/150% scaling, longest device strings) — bake the PITFALLS.md "Looks Done But Isn't" checklist into each phase's PLAN.md acceptance criteria.

## Sources

### Primary (HIGH confidence)
- learn.microsoft.com class docs: `win32-processor`, `win32-computersystem` (incl. TotalPhysicalMemory caveat), `win32-physicalmemory`, `win32-videocontroller`, `win32-logicaldisk` (DriveType enum), `win32-baseboard`, `win32-bios` (SMBIOS remark), `win32-operatingsystem` — per-class properties and quirks
- `Akari.ps1` full read (390 lines): `$script:Cat`, `Show-Page`, `Invoke-Code`, timer tick, nav builder, tuners, `Add_Loaded` — all architecture touch points
- `UI/MainWindow.xaml` full read (292 lines): theme tokens, `Rows` container, tuner panels
- `.planning/codebase/ARCHITECTURE.md` + `STRUCTURE.md`: extension precedents, runspace/state constraints
- MS Learn PS101 ch.7 "Working with WMI": `Get-WmiObject` deprecated since PS 3.0, CIM preferred
- Microsoft Support KB: null `Win32_VideoController.Current*` on headless/driver-less systems

### Secondary (MEDIUM confidence)
- Maik Koster CIM-vs-WMI benchmarks (implicit-session ~2.5–3x cost, session reuse)
- Stack Overflow / Server Fault / Spiceworks decade-recurring threads: `Measure-Object -Sum` RAM pattern, `.Capacity` array unrolling, `CurrentClockSpeed` static-under-Turbo, `AdapterRAM` 4 GB cap + `qwMemorySize` workaround, filler serials, `ProductName`-says-Win10 + build≥22000 gate
- Hardware.Info issue #40 (`AdapterRAM` uint32 cap + fix); SillyTavern-Launcher issue #72 (iGPU-over-dGPU + virtual-adapter fix)
- PowerShellFAQs / Windows OS Hub / tseknet / ctrlaltnod: `DisplayVersion` vs `ReleaseId`, `CurrentBuild`/`UBR`, `Get-ComputerInfo` cost
- Speccy / msinfo32 / Settings About conventions; WinUtil + Winhance tab structures (dashboard gap among tweakers); CPU-Z/HWiNFO polling-scope rationale

### Tertiary (LOW confidence)
- None outstanding — registry display values (`ProductName`, `DisplayVersion`, `UBR`) are officially undocumented, so STACK.md recommends pinning behavior with a code comment; treat as convention, not contract.

---
*Research completed: 2026-10-08*
*Ready for roadmap: yes*
