# Phase 3: Home Shell & Live Refresh - Context

**Gathered:** 2026-10-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Turn the spec data built in Phases 1–2 (`Get-Specs` → `$script:SpecData`) into a visible **Home** page: Home becomes the default landing tab, shows a hostname/maker header and a fluid card grid (CPU, GPU, RAM, Disk, Board, Windows) in the existing dark theme, and re-reads specs in the background every time Home is shown without blocking the UI.

Covers SHELL-01, SHELL-02, SHELL-03, REFR-01. Copy-to-clipboard, health coloring and README are Phase 4.

</domain>

<decisions>
## Implementation Decisions

### Card Grid
- **D-01:** Six cards in this order: **CPU, GPU, RAM, Disk, Board (motherboard + BIOS), Windows**.
- **D-02:** Fluid wrap — fixed-width cards flowing into as many columns as fit (≈3 on a wide window, 1 on narrow). Window MinWidth is 820 with a 190px sidebar, so card width must allow at least 2 columns at minimum size where reasonable.
- **D-03:** Values shown as **label / value rows** (muted `Mu` label left, `Tx` value right), spec-sheet style. Card title at top; CPU/GPU model name may sit as the first, prominent line.
- **D-04:** Multi-instance groups (GPU `Adapters`, Disk `Volumes`) stack **inside one card**, each item a small block separated by a thin `Bd` divider; card grows taller.
- **D-05:** Cards use existing theme tokens (`S1` card background, `Bd` border, `Tx`/`Mu` text) matching the Tuner panels' look (`UI/MainWindow.xaml` `Tuner` Border).

### Loading & Refresh
- **D-06:** First visit (no data yet): each card shows "Loading…". Later visits keep showing the **previous values dimmed** until fresh data arrives, then swap in — no flicker/clearing.
- **D-07:** Spec refreshes are **silent** in the log drawer — no "Reading specs…/Done" lines. Only errors are logged.
- **D-08:** The app stays **fully usable** while specs load — sidebar, search, and other pages are not greyed out. Leaving Home mid-load is fine; the result is kept and shown next time.
- **D-09:** If a tweak is running when Home is shown: show last values immediately and **automatically re-read specs once the tweak finishes**. Spec refresh must not block or be blocked into a lost state by tweak runs.
- **D-10:** A spec refresh must never prevent the user from starting a tweak (today `$script:Busy` + `Set-Busy` disable `$Page` and reject new jobs — the spec read needs a path that does not use that guard, or equivalent behavior).

### Home Header
- **D-11:** Header = **computer name** (large, replaces the plain `Heading` text on Home) + a muted line **"Maker · Model"** of the system (`Win32_ComputerSystem` Manufacturer/Model — new fields to add to the spec read).
- **D-12:** When system maker/model are SMBIOS filler (`Test-SmbiosValue` fails), fall back to the **motherboard** manufacturer/product (e.g. "MSI · MAG B650 TOMAHAWK"). If both are filler, show only the computer name.

### Sidebar & Search
- **D-13:** **Home** is the first sidebar item, followed by a small gap/thin divider, then Check … Advanced. Same `Nav` style.
- **D-14:** Home is selected on launch (`$script:Cat` default changes from `'Windows'` to `'Home'`).
- **D-15:** Search works as today on Home — typing shows tweak results; clearing search returns to Home.
- **D-16:** Specs re-read **any time Home appears**: launch, clicking Home, and clearing search back to Home. (Avoid re-triggering from the job-completion `Show-Page` call into an endless refresh loop.)

### Clarified During Planning (2026-10-08)
- **D-17:** Home header fallback follows the **UI-SPEC literal rule**: if *either* `Win32_ComputerSystem` Manufacturer or Model is SMBIOS filler (`Test-SmbiosValue` fails), the *entire* system pair is discarded in favour of the motherboard Manufacturer/Product pair. Resolves the wording conflict against D-12, which read "when system maker/model are filler" (both). Then, within whichever pair is chosen, if exactly one value is valid show just that one with no dot; if both are filler, `HostSub` is Collapsed so only the computer name shows. Verified live candidate on this host: `ASUSTeK COMPUTER INC. · TUF GAMING B550-PLUS`.
- **D-18:** `Get-Specs` stays byte-for-byte unchanged. Computer-name / maker-model data arrives through a **composite wrapper** — a new here-string returning `@{ Specs = Get-Specs; Host = Get-HostIdentity }` — preserving the exact six-group contract (`CPU,Disk,GPU,Motherboard,RAM,Windows`) that Phase 2's verify command asserts.

### Claude's Discretion
- Exact card width, padding, spacing, and font sizes (within the existing theme).
- Number formatting (GB decimals, GHz vs MHz) and which secondary fields appear per card, as long as Phase 1–2 fields are all shown.
- How "Not available" fields and `_Status = 'Failed'` groups look (still a card, values read "Not available").
- Mechanism for off-UI-thread spec read that satisfies D-08–D-10 (separate runspace/job slot vs extended `Invoke-Code`).
- Whether dimming uses opacity or `Mu` foreground.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project scope
- `.planning/PROJECT.md` — core value, constraints (PS 5.1 STA, inbox only, dark theme tokens)
- `.planning/REQUIREMENTS.md` — SHELL-01/02/03, REFR-01 definitions
- `.planning/ROADMAP.md` §Phase 3 — success criteria

### Prior phase decisions
- `.planning/phases/01-spec-query-engine/01-CONTEXT.md` — result structure (grouped hashtable, `_Status`, "Not available"), `Invoke-Code -ResultVar` design
- `.planning/phases/02-hardware-spec-cards/02-SUMMARY.md` — GPU/Disk array groups, Motherboard group, `Test-SmbiosValue`, PS 5.1 `-ResultVar` fix

### Codebase maps
- `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/CONVENTIONS.md`, `.planning/codebase/STRUCTURE.md`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `$GetSpecsFunc` here-string + `Get-Specs` (`Akari.ps1` ~103–400): returns `CPU/RAM/Windows/GPU/Disk/Motherboard` groups; not yet invoked anywhere.
- `Test-SmbiosValue` (inside `$GetSpecsFunc`): reuse for D-12 filler check.
- `Invoke-Code -ResultVar` (`Akari.ps1:480`) + timer tick (`Akari.ps1:506`) writes `$script:SpecData`.
- XAML tokens `Bg S1 S2 Bd Tx Mu` and the `Tuner` Border styling (`UI/MainWindow.xaml:9-18, 209`).

### Established Patterns
- `Show-Page` (`Akari.ps1:451`) rebuilds `$Rows` from `$script:Cat`; Advanced-only panels toggled via Visibility — Home panel can follow the same pattern.
- Sidebar built in code (`Akari.ps1:566` foreach over category names) with `Nav` style; Checked handler sets `$script:Cat` and calls `Show-Page`.
- Initial selection in `$window.Add_Loaded` checks the nav item matching `$script:Cat`.

### Integration Points
- `Set-Busy` disables `$Page` and `Invoke-Code` rejects calls while busy — conflicts with D-08/D-10; planner must route spec reads around it.
- Timer tick calls `Show-Page` after every job — refresh triggers must not recurse (D-16).
- `Page` StackPanel inside a vertical-only ScrollViewer — a `WrapPanel` card host fits here.

</code_context>

<specifics>
## Specific Ideas

- Card mock (label/value):
  ```
  ┌─ CPU ──────────────────────┐
  │ AMD Ryzen 7 7800X3D        │
  │ Cores     8 / 16 threads   │
  │ Speed     4.20 GHz         │
  └────────────────────────────┘
  ```
- Header mock:
  ```
  DESKTOP-7F2K
  ASUS · ROG Strix G16
  ```

</specifics>

<deferred>
## Deferred Ideas

- **Tweak progress bar under the log drawer** — user wants a progress indicator shown under the log while a tweak applies (some take long). New capability for the tweak pages → own phase (e.g. 3.1 via `/gsd-phase`).

</deferred>

---

*Phase: 03-home-shell-live-refresh*
*Context gathered: 2026-10-08*
