# Architecture Research: Home Page Integration

**Domain:** Brownfield addition — read-only info page in a PowerShell 5.1 + WPF single-host tweaking tool
**Researched:** 2026-10-08
**Confidence:** HIGH (grounded in direct reads of `Akari.ps1` — all 390 lines — and `UI/MainWindow.xaml` — all 292 lines; no external docs needed)

## Standard Architecture

### System Overview

Home does **not** extend the tweak-registry architecture — it branches off it. The existing system is a data-driven plugin-registry UI (`$script:Tweaks` → `New-Row` → `Show-Page` → `Invoke-Code` runspace). Home is a second, parallel render path inside the same host: a **query layer** (inbox CIM/registry reads) feeding a **card renderer** (XAML-string → `XamlReader::Parse`, same technique as `New-Row`), selected by a **nav/default-tab branch** in `Show-Page`. All three live in `Akari.ps1`; no new files, no new processes, no catalog entries.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Shell / Host (`Akari.ps1`)                    │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐  │
│  │ Spec-query   │  │ Card         │  │ Nav / default-tab      │  │
│  │ layer        │→ │ renderer     │→ │ wiring                 │  │
│  │ (NEW)        │  │ (NEW)        │  │ (2-line change +       │  │
│  │ Get-Spec*    │  │ New-HomeCard │  │  Show-Page branch)     │  │
│  │ functions    │  │ Show-Home    │  │                        │  │
│  └──────┬───────┘  └──────▲───────┘  └────────────────────────┘  │
│         │                 │                                      │
│  ┌──────▼─────────────────┴──────────────────────────────────┐  │
│  │  Execution: existing `Invoke-Code` background runspace +   │  │
│  │  150 ms `DispatcherTimer` log-pump (REUSED, not forked)    │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  Untouched: tweak registry (`Add-Tweak`, `Tweaks/*.ps1`),       │
│  `New-Row`/`Update-Row`/`Get-State`, tuners, `state.json`,      │
│  log drawer, elevation/STA bootstrap                            │
├─────────────────────────────────────────────────────────────────┤
│  View (`UI/MainWindow.xaml`): NO structural change needed.      │
│  Cards render into the existing `Rows` container; `Heading`     │
│  shows "Home" for free. Optional: card-grid styles only.       │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| Spec-query layer | Returns a single spec object (CPU, RAM, GPU, disk, board/BIOS, edition+build) using inbox-only sources; pure functions, no UI references, safe to run in a background runspace | New `Get-*` functions in `Akari.ps1` (beside the tuner helpers, ~lines 307-373); CIM `Get-CimInstance` + `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` registry reads |
| Card renderer | Converts one spec object into card visuals inside the existing `Rows` panel; follows the `New-Row` XAML-string + `XamlReader::Parse` technique so theme tokens (`S1 Bd Tx Mu`) and code style stay consistent | New `New-HomeCard` / `Show-Home` functions in `Akari.ps1`; card grid = `UniformGrid`/`WrapPanel` XAML string added to `$Rows.Children` |
| Nav / default-tab wiring | Makes Home the first sidebar entry and the launch landing tab; routes `Show-Page` to the card path when `$script:Cat -eq 'Home'` | `$script:Cat = 'Home'` (`Akari.ps1:34`); prepend `'Home'` to the nav list (`Akari.ps1:293`); branch at the top of `Show-Page` (`Akari.ps1:194`) |
| Async refresh bridge | Runs the query off the UI thread and marshals the result back for rendering; reuses the existing runspace + timer, extended with a structured-result channel | `Invoke-Code` (`Akari.ps1:223`) + timer tick (`Akari.ps1:239`) with a synchronized-hashtable result slot and a Home-job guard flag |

## Recommended Project Structure

No new files. All Home code lives in `Akari.ps1`, grouped in one clearly-delimited section (mirroring how the two tuners occupy `Akari.ps1:307-373`):

```
Akari.ps1
├── ... existing: elevation, registry, state, $Helpers, window, rows ...
├── Show-Page (+ Home branch at top)          # MODIFIED, ~5 lines
├── $script:Cat default 'Windows' → 'Home'    # MODIFIED, 1 line
├── nav builder list + 'Home' first           # MODIFIED, 1 line
└── Home section (NEW, after tuners ~line 373)
    ├── Get-HomeSpec / Get-CpuSpec / Get-MemSpec / Get-GpuSpec /
    │   Get-DiskSpec / Get-BoardSpec / Get-OsSpec   # query layer
    ├── New-HomeCard / Show-Home                    # card renderer
    └── Start-HomeRefresh (timer-completion hook)    # async bridge
```

`UI/MainWindow.xaml`: unchanged unless the roadmap wants named card-grid styles — dynamic cards are code-generated like `New-Row` output, so XAML edits are optional, not required.

### Structure Rationale

- **Single-host cohesion:** the codebase's core invariant is "all UI logic lives in `Akari.ps1` (~390 lines)". A separate module/file would break the dot-source-free, no-import composition model and complicate the `IWR.ps1` zip layout. Keep the invariant.
- **One delimited section:** the tuner precedent (`Get-Chip`/`Update-Tuner`/`Set-Prio`, `Get-RamKB`/`Read-Svc`/`Set-Svc`) proves the codebase already organizes non-registry UI features as function clusters inside the host. Home follows the same convention.
- **No `Tweaks/Home.ps1`:** Home cards must never enter `$script:Tweaks`. The registry drives search (`Show-Page` search path, `Akari.ps1:197-199`), `RowCache`, and the state dot — injecting pseudo-tweaks would pollute search results and risk `Update-Row` null-reference paths. The nav list and `Show-Page` branch are the only integration seams.

## Architectural Patterns

### Pattern 1: Registry-bypass page branch

**What:** `Show-Page` gains an early branch: if `$script:Cat -eq 'Home'`, set `Heading`, collapse tuners, clear `Rows`, and delegate to `Show-Home` — skipping the `$script:Tweaks` filter, `RowCache`, and `Update-Row` entirely. Search text still takes precedence (searching from Home shows tweak results, matching how search overrides every other tab today).
**When to use:** Any future non-tweak page (dashboard, settings, about). This establishes the "special page" pattern.
**Trade-offs:** Pro — zero risk to the 127-tweak render path; the existing loop is untouched. Con — two render paths to maintain; keep the branch thin (route + chrome) and put all card logic in `Show-Home`.

**Example:**
```powershell
function Show-Page {
    $q = $Search.Text.Trim()
    if ($q) { <# ... existing search path, unchanged ... # return }
    if ($script:Cat -eq 'Home') {
        $Heading.Text = 'Home'
        $Tuner.Visibility = 'Collapsed'; $SvcTuner.Visibility = 'Collapsed'
        $Rows.Children.Clear()
        Show-Home   # placeholder cards + kick background refresh
        return
    }
    # ... existing category path, unchanged ...
}
```

### Pattern 2: Placeholder-first async refresh (skeleton → live data)

**What:** Every `Show-Home` renders immediately with placeholder cards ("Reading specs…") on the UI thread, then dispatches the CIM/registry query to the background runspace. When the timer observes job completion, it renders the real cards on the UI thread. The page is never blank and never frozen.
**When to use:** Because live-on-every-show is a hard requirement and CIM calls (notably `Win32_VideoController` VRAM/driver and physical-disk enumeration) can take hundreds of milliseconds — and hang for seconds against a broken WMI provider. Never run them synchronously on the UI thread.
**Trade-offs:** Pro — perceived instant load; follows the project's own `Invoke-Code` + log-pump constraint. Con — one extra render pass per visit; requires the completion guard below.

**Example:**
```powershell
# Show-Home (UI thread): paint placeholders, then dispatch
function Show-Home {
    Add-HomePlaceholders          # 6 skeleton cards into $Rows
    Start-HomeRefresh              # Invoke-Code around Get-HomeSpec; result -> $script:HomeResult
}
# Timer tick completion (UI thread): only re-render if this was a Home job AND Home is still showing
if ($j -and $j.Handle.IsCompleted) {
    # ... existing drain/dispose ...
    if ($j.Meta -and $j.Meta.Kind -eq 'Home' -and $script:Cat -eq 'Home' -and -not $Search.Text) {
        Render-HomeCards $script:HomeResult
    }
    Show-Page  # existing tail — must NOT re-trigger refresh (see Anti-Pattern 1)
}
```

### Pattern 3: Structured result via synchronized slot (not the log queue)

**What:** The existing `ConcurrentQueue` carries log *strings* to the drawer. Spec data is a structured object, so the Home job writes it to a synchronized hashtable (`$script:HomeResult = [hashtable]::Synchronized(@{})`) that the timer tick reads on completion. Log lines from the query still flow through the queue normally.
**When to use:** Any background job whose output is data, not log text.
**Trade-offs:** Pro — no serialization format to invent; keeps the log channel clean. Con — slight departure from the pure queue pattern; document the slot next to `$script:Queue` declaration (`Akari.ps1:37`) so the two channels are visibly paired.

## Data Flow

### Request Flow (open / return to Home)

```
[User clicks Home] or [app launch, $script:Cat='Home']
    ↓
Nav Checked handler → $script:Cat='Home' → Show-Page          (Akari.ps1:299-304)
    ↓ (Home branch)
Heading='Home' · tuners collapsed · Rows cleared
    ↓
Show-Home: skeleton cards painted (UI thread, instant)
    ↓
Start-HomeRefresh: Invoke-Code(Get-HomeSpec) → fresh runspace  (Akari.ps1:223-235)
    ↓ (background thread: CIM + registry reads, ~6 queries)
$script:HomeResult = @{ Cpu=…; Ram=…; Gpu=…; Disk=…; Board=…; Os=… }
    ↓
DispatcherTimer 150 ms tick sees Handle.IsCompleted            (Akari.ps1:239-255)
    ↓ (back on UI thread)
Guard: Meta.Kind -eq 'Home' AND Cat still 'Home' AND no search text
    ↓
Render-HomeCards: rebuild $Rows.Children from result
```

### State Management

```
$script:Cat ('Home' default) ──→ Show-Page branch selector
$script:HomeResult (synchronized hashtable) ──→ latest spec object; written by runspace, read by timer tick
$script:HomeRefreshing (bool guard) ──→ prevents overlapping refresh jobs while $script:Busy is tweak-scoped
$script:RowCache ──→ UNTOUCHED by Home (tweak rows only; Home cards rebuild live every show per requirement)
$script:State / state.json ──→ UNTOUCHED by Home (read-only page: no toggles, no Detect, no persistence)
```

### Key Data Flows

1. **Launch flow:** `$window.Add_Loaded` (`Akari.ps1:376-380`) checks the nav radio matching `$script:Cat` — with default `'Home'` and `'Home'` first in the nav list, launch lands on Home with zero extra startup code.
2. **Live-refresh flow:** described above; every `Show-Page` with `Cat='Home'` re-queries (no caching — "refresh live every time shown" is the requirement; CIM cost is small and off-thread).
3. **Interruption flow:** user clicks away mid-query → completion guard sees `Cat -ne 'Home'`, discards render, result slot simply overwritten next visit. No cancellation plumbing needed.
4. **Tweak-completion flow (existing):** timer tail calls `Show-Page` after every tweak job (`Akari.ps1:253`) — if the user is sitting on Home, this re-renders Home and re-queries. Acceptable and consistent with "live every time shown", provided the recursion guard (Anti-Pattern 1) is in place.

## Scaling Considerations

Not applicable in the user-count sense (single-user desktop tool). The relevant scale axis is **spec-query cost across machine diversity**:

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Typical desktops (1 GPU, 1-2 disks) | 6 CIM queries + 1 registry read in one runspace invocation; well under a second |
| Exotic hardware (multi-GPU, many disks, VMs with thin WMI providers) | Per-query `try/catch` with "Unknown" fallback per card — one slow/failed class must never blank the whole grid |
| Broken WMI repository (provider hangs) | Runspace-level timeout: timer tick checks elapsed time and abandons the job with an error card rather than hanging `Busy` forever; Home refresh must never set the tweak-scoped `$script:Busy` latch |

### Scaling Priorities

1. **First bottleneck:** `Win32_VideoController` and disk enumeration latency on some drivers — mitigated by placeholder-first rendering (user sees skeleton, not freeze).
2. **Second bottleneck:** `Akari.ps1` file growth (~390 → ~550 lines). Acceptable — matches the tuner precedent; if a second special page ever arrives, extract shared card helpers then, not now.

## Anti-Patterns

### Anti-Pattern 1: Timer-tail recursion (refresh loop)

**What people do:** The existing timer completion tail calls `Show-Page` (`Akari.ps1:253`). If Home-job completion calls `Show-Page` and `Show-Page` on Home always starts a new refresh, each completion spawns another job — an infinite background-query loop.
**Why it's wrong:** Permanent runspace churn, log spam (`Done:` lines), CPU waste.
**Do this instead:** Separate *render-from-result* (`Render-HomeCards`) from *refresh* (`Start-HomeRefresh`). Timer completion calls `Render-HomeCards` directly; only user navigation (nav click, launch, return-to-tab) calls `Start-HomeRefresh`. The `$script:HomeRefreshing` guard is a backstop, not the primary mechanism.

### Anti-Pattern 2: Home entries in the tweak registry

**What people do:** Model each spec card as `Add-Tweak -Category 'Home'` to "reuse" `New-Row`.
**Why it's wrong:** Cards would appear in global search results, enter `RowCache` under fake IDs, hit `Update-Row`/`Get-State` paths that assume `Apply`/`Revert` scriptblocks, and break the "read-only, no actions" requirement. It also forces the card-grid design into the row layout the project explicitly rejected.
**Do this instead:** Keep `$script:Tweaks` tweak-only. Cards are bespoke XAML via `New-HomeCard`, rendered by `Show-Home` — same *technique* as `New-Row` (XAML string → `XamlReader::Parse`), different function, different container content.

### Anti-Pattern 3: Synchronous CIM on the UI thread

**What people do:** Call `Get-CimInstance` directly in `Show-Page` because "it's just a quick query".
**Why it's wrong:** "Quick" is hardware-dependent; a single stalled provider freezes the entire window (WPF has one UI thread), violating the project's explicit non-blocking constraint. It also runs inside `Dispatcher.UnhandledException` territory where a CIM exception would surface as a log-drawer error on every tab visit.
**Do this instead:** Placeholder-first async (Pattern 2). UI thread only ever paints XAML; all CIM/registry reads happen in the `Invoke-Code` runspace with per-query `try/catch` → `"Unknown"` fallback.

### Anti-Pattern 4: Reusing the `$script:Busy` latch for Home refresh

**What people do:** Let `Invoke-Code` set `Busy` (disables `$Page`) during spec queries, as it does for tweaks.
**Why it's wrong:** `Set-Busy $true` disables the whole `Page` container (`Akari.ps1:221`) — the Home grid would go dead on every visit, and a second overlapping concern (tweak running + Home showing) would collide on one latch. Worse, the single-job slot (`$script:Job`, "exactly one background runspace at a time" per ARCHITECTURE.md) means a Home refresh could block a tweak run or vice versa.
**Do this instead:** Home refresh uses its own `$script:HomeRefreshing` flag and either its own lightweight runspace (preferred — leaves `Invoke-Code`/`$script:Job`/`$script:Busy` semantics untouched) or a `Meta.Kind='Home'` path that skips `Set-Busy`. Decision: dedicated runspace + existing timer for completion pickup is the smallest-blast-radius option — reuse the *timer*, not the *job slot*.

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Nav builder ↔ Home | Prepend `'Home'` to category list (`Akari.ps1:293`); existing `Checked` handler routes via `$script:Cat` with no handler change | Default tab: `$script:Cat = 'Home'` (`Akari.ps1:34`); `Add_Loaded` (`Akari.ps1:377`) picks it up automatically |
| `Show-Page` ↔ `Show-Home` | Early return branch; search path takes precedence over Home branch | Mirrors the existing `$adv`/tuner-visibility gating (`Akari.ps1:204-206`) — add an `$isHome` flag in the same style |
| Query layer ↔ runspace | Query functions must be self-contained scriptblocks (no `$window`/UI refs); `$Helpers` preamble is available but Home queries need only `try/catch` discipline | Same constraint as tweak bodies — but simpler, since queries are pure reads with no `Set-Reg`/`Run-Trusted` surface |
| Timer tick ↔ Home render | Completion guard (`Meta.Kind -eq 'Home'`, `Cat -eq 'Home'`, no search text) before `Render-HomeCards` | Prevents render-after-navigate and the recursion loop; see Anti-Pattern 1 |
| Cards ↔ theme | Reuse `S1 Bd Tx Mu` resource tokens and `CornerRadius="5" Padding="12,9"` card chrome from `New-Row` output | Guarantees Ink dark-theme consistency with zero XAML changes |

### Touch-Point Checklist (exact lines)

| # | File:line | Change | Risk |
|---|-----------|--------|------|
| 1 | `Akari.ps1:34` | `$script:Cat = 'Windows'` → `'Home'` | Trivial; `Add_Loaded` follows automatically |
| 2 | `Akari.ps1:293` | Nav list `'Check',…` → `'Home','Check',…` | Trivial; handler is tag-driven |
| 3 | `Akari.ps1:194-218` | `Show-Page` Home branch (heading, tuner collapse, delegate, return) | Low; existing paths untouched below the branch |
| 4 | `Akari.ps1:~374+` | New Home section: 6 query fns + card fns + refresh bridge | Medium; all new code, isolated |
| 5 | `Akari.ps1:239-255` | Timer tick: Home completion guard + `Render-HomeCards` | Medium; the recursion guard is the critical detail |
| 6 | `UI/MainWindow.xaml` | No change required (optional card styles only) | None |

## Suggested Build Order

Dependencies flow one way — each step is independently verifiable before the next begins:

1. **Spec-query layer first** (`Get-HomeSpec` + 6 per-group functions). Pure functions, testable in any console via `powershell -File` without launching the UI. Defines the spec-object schema every later step consumes. Highest risk (hardware diversity) is retired earliest.
2. **Card renderer second** (`New-HomeCard` + `Render-HomeCards` with static sample data). Verifiable by calling `Render-HomeCards $sample` after launch with `-ShowConsole`. Locks the card-grid layout and theme-token usage before any threading is involved.
3. **Nav + default-tab wiring third** (touch-points 1-3). Two-line change plus `Show-Page` branch rendering *synchronous* cards from a hardcoded sample — proves routing, heading, tuner-collapse, and search-precedence with no async surface.
4. **Async refresh bridge last** (placeholder cards + background dispatch + timer guard). Converts the step-3 synchronous call into `Show-Home` → `Start-HomeRefresh` → `Render-HomeCards`. Smallest-blast-radius threading change, built on two already-verified halves.

**Phase-shape implication for roadmap:** steps 1+2 are UI-thread-safe and demoable without threading; step 4 is the only step that touches the runspace/timer engine and deserves its own verification pass (navigate-away-mid-query, tweak-completes-while-on-Home, broken-WMI fallback). Recommend two phases — *(a) queries + cards + wiring with synchronous render*, *(b) async live-refresh hardening* — rather than one big-bang Home phase.

## Sources

- `Akari.ps1` (all 390 lines, direct read — HIGH confidence): `$script:Cat` default (line 34), `Show-Page` (194-218), `Invoke-Code` (223-235), timer tick (237-256), row-button handler (264-290), nav builder (293-304), tuner sections (307-373), `Add_Loaded` (376-380)
- `UI/MainWindow.xaml` (all 292 lines, direct read — HIGH confidence): named elements, `Rows` container (281), tuner panels (209-279), theme tokens (9-18)
- `.planning/codebase/ARCHITECTURE.md` + `STRUCTURE.md` (required reading — HIGH confidence for "new category" and "new tuner" extension precedents)
- PowerShell runspace + WPF `DispatcherTimer` single-threaded-affinity behavior (standard platform knowledge — MEDIUM confidence on WMI-provider hang durations; mitigated by placeholder-first design regardless)

---
*Architecture research for: AkariOS-Ultimate Home page integration*
*Researched: 2026-10-08*
