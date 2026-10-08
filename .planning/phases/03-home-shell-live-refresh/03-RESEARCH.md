# Phase 3: Home Shell & Live Refresh - Research

**Researched:** 2026-10-08
**Domain:** Windows PowerShell 5.1 + WPF home-page shell, background runspace refresh channel
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Card Grid
- **D-01:** Six cards in this order: **CPU, GPU, RAM, Disk, Board (motherboard + BIOS), Windows**.
- **D-02:** Fluid wrap — fixed-width cards flowing into as many columns as fit (≈3 on a wide window, 1 on narrow). Window MinWidth is 820 with a 190px sidebar, so card width must allow at least 2 columns at minimum size where reasonable.
- **D-03:** Values shown as **label / value rows** (muted `Mu` label left, `Tx` value right), spec-sheet style. Card title at top; CPU/GPU model name may sit as the first, prominent line.
- **D-04:** Multi-instance groups (GPU `Adapters`, Disk `Volumes`) stack **inside one card**, each item a small block separated by a thin `Bd` divider; card grows taller.
- **D-05:** Cards use existing theme tokens (`S1` card background, `Bd` border, `Tx`/`Mu` text) matching the Tuner panels' look (`UI/MainWindow.xaml` `Tuner` Border).

#### Loading & Refresh
- **D-06:** First visit (no data yet): each card shows "Loading…". Later visits keep showing the **previous values dimmed** until fresh data arrives, then swap in — no flicker/clearing.
- **D-07:** Spec refreshes are **silent** in the log drawer — no "Reading specs…/Done" lines. Only errors are logged.
- **D-08:** The app stays **fully usable** while specs load — sidebar, search, and other pages are not greyed out. Leaving Home mid-load is fine; the result is kept and shown next time.
- **D-09:** If a tweak is running when Home is shown: show last values immediately and **automatically re-read specs once the tweak finishes**. Spec refresh must not block or be blocked into a lost state by tweak runs.
- **D-10:** A spec refresh must never prevent the user from starting a tweak (today `$script:Busy` + `Set-Busy` disable `$Page` and reject new jobs — the spec read needs a path that does not use that guard, or equivalent behavior).

#### Home Header
- **D-11:** Header = **computer name** (large, replaces the plain `Heading` text on Home) + a muted line **"Maker · Model"** of the system (`Win32_ComputerSystem` Manufacturer/Model — new fields to add to the spec read).
- **D-12:** When system maker/model are SMBIOS filler (`Test-SmbiosValue` fails), fall back to the **motherboard** manufacturer/product (e.g. "MSI · MAG B650 TOMAHAWK"). If both are filler, show only the computer name.

#### Sidebar & Search
- **D-13:** **Home** is the first sidebar item, followed by a small gap/thin divider, then Check … Advanced. Same `Nav` style.
- **D-14:** Home is selected on launch (`$script:Cat` default changes from `'Windows'` to `'Home'`).
- **D-15:** Search works as today on Home — typing shows tweak results; clearing search returns to Home.
- **D-16:** Specs re-read **any time Home appears**: launch, clicking Home, and clearing search back to Home. (Avoid re-triggering from the job-completion `Show-Page` call into an endless refresh loop.)

### Claude's Discretion
- Exact card width, padding, spacing, and font sizes (within the existing theme).
- Number formatting (GB decimals, GHz vs MHz) and which secondary fields appear per card, as long as Phase 1–2 fields are all shown.
- How "Not available" fields and `_Status = 'Failed'` groups look (still a card, values read "Not available").
- Mechanism for off-UI-thread spec read that satisfies D-08–D-10 (separate runspace/job slot vs extended `Invoke-Code`).
- Whether dimming uses opacity or `Mu` foreground.

### Deferred Ideas (OUT OF SCOPE)
- **Tweak progress bar under the log drawer** — user wants a progress indicator shown under the log while a tweak applies (some take long). New capability for the tweak pages → own phase (e.g. 3.1 via `/gsd-phase`).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SHELL-01 | User lands on the Home page by default on app launch | `$script:Cat` default flip at `Akari.ps1:34` + the `Add_Loaded` `IsChecked` selection at `Akari.ps1:651` — the only two lines needed; the launch path is verified end-to-end (probe 2). |
| SHELL-02 | User sees specs arranged in a fluid card grid matching the existing dark theme | 240px `WrapPanel` cadence measured live: **2 columns at outer width 820, 3 at 1000** (probe 1). `WrapPanel` confirms row-height stretch. Theme token reuse table from `UI/MainWindow.xaml:9-18`. |
| SHELL-03 | User sees a friendly hostname/manufacturer header on Home | `$env:COMPUTERNAME` available synchronously (probe 3: `DESKTOP-LLLM7SU`), plus the verified `Win32_ComputerSystem` read and the **live mixed-filler case on this host** (`Manufacturer='ASUS'`, `Model='System Product Name'`). |
| REFR-01 | User sees freshly queried specs every time Home is shown (background query with loading/placeholder state, UI never blocks) | The recommended second background channel (`$script:SpecJob` + one-flight guard + tick completion block) — verified by probe 3, including concurrent execution alongside a 2s tweak job. |

</phase_requirements>

## Summary

Phase 3 turns `Get-Specs`'s output into a visible Home page. The data layer is done and verified (`Get-Specs` returns exactly six groups `CPU, Disk, GPU, Motherboard, RAM, Windows`; `$script:SpecData` is now written correctly by the 150 ms `DispatcherTimer`). What is missing is everything UI: a Home sidebar item, a default-landing change, a static Home panel in XAML, a card renderer, a host header, and a refresh trigger.

**The central technical decision is resolved: do NOT route the spec read through `Invoke-Code`.** Three independent lines in the existing engine make it unusable for specs. `Invoke-Code` returns immediately when a tweak is running (`if ($script:Busy) { return }`), calls `Set-Busy $true` which disables the whole `$Page` panel, and logs a start line plus a `"Done: …"` line — violating D-08, D-09/D-10 and D-07 respectively. The correct shape is a **second, independent background channel**: a sibling `$script:SpecJob` slot, its own runspace created by a new `Start-SpecRead` function, and a new completion block inside the *existing* 150 ms tick. No `$script:Busy`, no `Set-Busy`, no `Show-Page` from the completion path. This was verified empirically: a spec read completed in 1.19 s **while a 2 s tweak job ran in parallel** in another runspace, with both results intact.

The D-16 recursion hazard has a single, crisp resolution. Today the tick calls `Show-Page` after every tweak job (`Akari.ps1:527`). If `Show-Page`'s Home branch unconditionally starts a spec read, and the spec read's completion calls `Show-Page`, the two feed each other. Because Home shows **no tweak rows**, the only way a tweak can finish while Home is visible is the D-09 scenario (user navigated to Home mid-tweak) — which is exactly the deferred read D-09 demands. So the rule is simple: **`Show-Page`'s Home branch may call `Start-SpecRead`; the read's completion handler must call a narrow `Update-Home`, never `Show-Page`.** A one-flight guard in `Start-SpecRead` is still required, because a single Home click can produce *two* `Show-Page` calls (verified: the nav handler clears `$Search`, and clearing a non-empty search box raises `TextChanged` → `Show-Page`, then the nav handler calls `Show-Page` again).

Two verified landmines the planner must build in. First, **current-culture formatting**: this host runs `it-IT` (decimal separator `,`), and `'{0:0.00} GHz' -f (3801/1000)` produced `3,80 GHz`, not `3.80 GHz`. The UI-SPEC mandates invariant culture — use `[double].ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)`, never `-f`. Second, **the `Not available` sentinel is a string**, and `'Not available'.ToString('0.00', $ci)` throws `MethodException: Cannot find an overload for "ToString" and the argument count: "2"`. A type guard must precede every numeric format.

**Primary recommendation:** Add a static Home panel to `UI/MainWindow.xaml` (mirroring the `Tuner`/`SvcTuner` pattern), extend the `Set-Variable` shortcut list with `Home`/`HostName`/`HostSub`/`Cards`, add `Start-SpecRead`/`Update-Home` plus a `$script:SpecJob` tick block to `Akari.ps1`, and read host identity through a small `Get-HostIdentity` helper composed with `Get-Specs` into one `@{ Specs = …; Host = … }` result — leaving `Get-Specs` itself byte-identical so the Phase 2 verify command keeps passing.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Spec acquisition (CIM/registry) | Background runspace | — | Already the codebase pattern; measured 1.2–1.9 s. Must never touch the UI thread (D-08). |
| Host identity (`COMPUTERNAME`, `Win32_ComputerSystem`) | Background runspace (for Maker/Model) | UI thread (for `$env:COMPUTERNAME`) | `$env:COMPUTERNAME` is a process env var — free and instant. Maker/Model needs one `Win32_ComputerSystem` query, so it rides in the same background read. |
| Home layout, cards, header | UI thread (WPF visuals) | — | WPF objects can only be constructed on the thread that owns them. `New-Row` already does all visual construction on the UI thread. |
| Refresh trigger ("Home appeared") | UI thread (`Show-Page` choke point) | — | All three triggers (launch, nav click, search clear) funnel through `Show-Page`; a second trigger site would be a second thing to keep in sync. |
| Cross-thread result handoff | UI thread (`DispatcherTimer` 150 ms tick) | Background runspace | The existing and only bridge: `ConcurrentQueue` drain + `PSDataCollection` completion check. No `Dispatcher.Invoke` anywhere. |
| Refresh state (`SpecData`, `SpecJob`, `SpecPending`) | Script scope in `Akari.ps1` | — | Matches the established convention that all shared state is `$script:` in the single-file host. |
| Error line in log drawer | UI thread (`Add-Log`) | — | D-07: errors are the only permitted log output from a spec read. |
| Tweak execution | Background runspace (`Invoke-Code`) | — | Unchanged. The new channel must not share its `$script:Job` slot or `$script:Busy` guard. |

## Project Constraints (from AGENTS.md)

Extracted from `AGENTS.md` (repo root) and `.planning/PROJECT.md`; these carry the same authority as CONTEXT.md locked decisions.

| Directive | Source | Phase 3 implication |
|-----------|--------|---------------------|
| Windows PowerShell 5.1 STA + **inbox .NET/WPF only** — no new packages, modules, or build tools | AGENTS.md §Constraints; PROJECT.md:58 | Zero third-party libraries. `WrapPanel`, `DockPanel`, `Border`, `Grid`, `TextBlock` are all in `PresentationFramework`. Package Legitimacy Audit is trivially "none". |
| Compatibility: Windows 10/11 Home/Pro/LTSC/IoT/Server, x64, Administrator required | AGENTS.md §Constraints; PROJECT.md:59 | Spec reads run in the same elevated process; no new privilege surface. |
| Live spec queries on every Home show "must stay fast and **off the UI thread**" | AGENTS.md §Constraints; PROJECT.md:60 | This is the hard constraint that shapes the whole refresh mechanism. |
| UI consistency: card grid must fit the existing dark-theme XAML (`Bg S1 S2 Bd Tx Mu` resources) | AGENTS.md §Constraints; PROJECT.md:61 | No new styles or brushes. `Inv`/`InvT`/`Warn`/`Bad` are off-limits in Phase 3 per UI-SPEC. |
| `#requires -Version 5.1` at file top; new entry-point scripts start the same line | AGENTS.md conventions | No new entry-point script is created; Phase 3 edits `Akari.ps1` and `UI/MainWindow.xaml` only. |
| Never `Write-Output` objects from tweak bodies; never pop `MessageBox` from tweak code | AGENTS.md conventions §Logging | The spec read is not a tweak body, but it must still not raise modals. Its only user-visible output is one `Add-Log` line on failure. |
| Don't set `$ErrorActionPreference = 'Stop'` or `Set-StrictMode` | AGENTS.md conventions §Error Handling | The new code must use tolerant reads (missing keys, failing CIM) exactly like `Get-Specs` does. |
| Registry/cmd blocks get a one-line lowercase comment naming intent; command payload lives in `Tweaks/*.ps1` | AGENTS.md conventions §Comments | Phase 3 adds no registry work; no `Tweaks/*.ps1` change. |
| Workflow enforcement: start work through a GSD command before editing | AGENTS.md §GSD Workflow Enforcement | The planner must emit tasks that write `Akari.ps1` and `UI/MainWindow.xaml` inside the phase plan (no ad-hoc edits). |
| `$Helpers` preamble + legacy shims are prepended in `Invoke-Code`; tweak files assume host globals | AGENTS.md architecture | `Get-Specs` does **not** depend on `$Helpers` (no `Write-Log` calls inside it — verified by reading `Akari.ps1:132-356`), so the spec read can skip the preamble entirely. |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Windows PowerShell 5.1 (Desktop) | 5.1.26100.9444 (verified live) | Host runtime | Locked by AGENTS.md. Already enforced by `#requires -Version 5.1` (`Akari.ps1:1`) and the STA relaunch at `Akari.ps1:8-13`. |
| `PresentationFramework` | .NET Framework 4.0.30319.42000 (verified live CLR) | `WrapPanel`, `DockPanel`, `Border`, `Grid`, `TextBlock`, `RadioButton`, `DispatcherTimer`, `XamlReader` | Already loaded at `Akari.ps1:15` via `Add-Type`. No new assembly reference is needed. |
| `PresentationCore` / `WindowsBase` / `System.Xaml` | inbox | `System.Windows.Window`, media, XAML parse | Already loaded at `Akari.ps1:15`. |
| `[runspacefactory]` / `[powershell]` | .NET 4.x | The background spec read | Already used by `Invoke-Code` at `Akari.ps1:484-487`. The new channel reuses the exact same construction, minus the busy guard and the log lines. |
| `System.Management.Automation.PSDataCollection[object]` | .NET 4.x | Result buffer read on the UI thread | Already used at `Akari.ps1:490,494` after the Phase 2 PS 5.1 fix. |
| `System.Windows.Threading.DispatcherTimer` | WPF | 150 ms pump — log queue + job completion | Already created and started at `Akari.ps1:504-505,530`. The new completion check rides in the same tick; no second timer. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `System.Windows.Controls.WrapPanel` | inbox (`PresentationFramework`) | Fluid card grid host, `Orientation=Horizontal` | The card grid. Type accelerator verified to resolve. |
| `System.Windows.Controls.DockPanel` | inbox (`PresentationFramework`) | Home header container (right side reserved for Phase 4) | Header row; matches `Tuner`'s existing `DockPanel Margin="0,14,0,0"` use at `UI/MainWindow.xaml:244`. |
| `System.Windows.Controls.Grid` + `Grid.SetColumn` | inbox | Label/value rows inside a card (72px / `*`) | Every field row; matches `New-Row`'s row `Grid` at `Akari.ps1:414-424`. |
| `[Windows.Markup.XamlReader]::Parse` | inbox | Building Home chrome from a XAML string | Optional. The **recommended** approach puts static chrome in `MainWindow.xaml` and builds only the six cards in code, mirroring `New-Row` (`Akari.ps1:410-429`). |
| `Get-CimInstance` + `Get-ItemProperty` | inbox cmdlets | All spec queries | Already the only data-access pattern in the repo. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Separate `$script:SpecJob` slot + own tick block | Extending `Invoke-Code` with a `-Silent` switch | Rejected: would touch the three verified lines that make it unusable (busy reject, `Set-Busy`, `Add-Log $label`/`"Done:"`), and would still need a second job slot because `$script:Job` is a single associative slot. |
| One 150 ms `DispatcherTimer` handling both jobs | A second dedicated `DispatcherTimer` for specs | Rejected: two timers means two points of re-entrancy and two stop paths (`Add_Closing` stops one at `Akari.ps1:663`). One tick, two independent `IsCompleted` checks, is strictly less state. |
| Static Home panel in XAML | Building the whole panel with `XamlReader.Parse` in `Add_Loaded` | Rejected: `Tuner`, `SvcTuner`, `Rows`, `Heading` are all static XAML with named elements grabbed via `FindName`; a code-built panel breaks that convention and needs its own parse/verify step. |
| Composite `@{ Specs; Host }` result | Adding a 7th `Get-Specs` group (`System`) | **Forbidden** — the Phase 2 verify command asserts the exact sorted key set `"CPU,Disk,GPU,Motherboard,RAM,Windows"` and would fail on `"CPU,Disk,GPU,Motherboard,RAM,System,Windows"`. See Open Questions for the second alternative. |
| `Dispatcher.Invoke` marshalling | Nothing (tick only) | `Dispatcher.Invoke` must **not** be introduced. All spec state transitions already happen on the UI thread inside the 150 ms tick; `Dispatcher.Invoke` would only be needed if a runspace tried to touch WPF objects, which it must never do. |

**Version verification:** Not applicable — this phase installs **no** external packages. `AGENTS.md` and `.planning/STACK.md` record "None. No `package.json`, `requirements.txt`, `Cargo.toml`, `go.mod`, `*.csproj`, `*.sln`, or module manifest (`.psd1`) anywhere in repo". Every dependency is an inbox .NET Framework assembly already loaded at `Akari.ps1:15`. The runtime version was confirmed live: `PSVersion 5.1.26100.9444`, `CLR 4.0.30319.42000`, `STA`, elevated, `Microsoft Windows 11 Pro build 26300`.

## Package Legitimacy Audit

**Not applicable — this phase installs zero external packages.** The stack is Windows PowerShell 5.1 + the inbox WPF/.NET Framework assemblies that `Akari.ps1:15` already loads. No `npm`/PyPI/crates registry lookup is meaningful here, so no `package-legitimacy check` was run and no packages appear in any recommendation.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| *(none)* | n/a | n/a | n/a | n/a | n/a | n/a — inbox .NET only |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
   USER ACTION                        UI THREAD (Akari.ps1)                    BACKGROUND RUNSPACE
   ───────────                        ─────────────────────                    ──────────────────

 launch / click Home / clear search
        │
        ▼
  Nav RadioButton Checked ────►  Nav handler (573-578)
        │                              $script:Cat = 'Home'
        │                              $Search.Text = ''  ──► TextChanged (579)
        ▼                                          │
  $window.Add_Loaded (650-654)                      ▼
        │                                     ┌──────────────────────────────┐
        └─ IsChecked on Home item ──►  Show-Page  (451-475)  ◄──────────────┘  (tick, 527)
                                            │
              ┌─────────────────────────────┼──────────────────────────────┐
              ▼                             ▼                              ▼
      $Heading.Visibility          $Home.Visibility               $Rows stays EMPTY
      = Collapsed                   = Visible                     (469-474 suppressed)
              │                             │
              │                             ▼
              │                      Update-Home(data?)
              │                       ├─ $script:SpecData = $null
              │                       │     └─► 6 cards with "Loading…"   [HostSub Collapsed]
              │                       └─ else
              │                             └─► 6 cards from data
              │                        $Cards.Opacity = 0.6 if a read is pending else 1
              │                             │
              │                             ▼
              │                       Start-SpecRead  ◄── one-flight guard
              │                             │
              │              ┌──────────────┴───────────────┐
              │              ▼                              ▼
              │      $script:Busy = false           $script:Busy = true (tweak running)
              │              │                              │
              │              ▼                              ▼
              │      runspace:                          $script:SpecPending = $true
              │      $GetSpecsFunc                      (D-09 deferred; NOTHING is lost)
              │      + Get-HostIdentity
              │      + composite wrapper
              │              │                              │
              │              │  (tweak finishes)            │
              │              │        ◄─────────────────────┘
              │              │        tick: Show-Page → Home branch → Start-SpecRead
              │              ▼
              │      DispatcherTimer tick (504-530), 150 ms
              │        ├─ drain ConcurrentQueue → Add-Log
              │        ├─ $script:SpecJob.IsCompleted ?  ──► $script:SpecData = result
              │        │                                    → Update-Home  (NOT Show-Page → no loop)
              │        └─ $script:Job.IsCompleted ?      ──► tweak completion (unchanged)
              │                                             → Set-Busy $false, Read-Svc, Show-Page
              ▼
        (only failure writes a log line: "Specs: Read failed (…).")
```

Arrows to note: the only path that reaches `Show-Page` from a background event is the **tweak** completion (line 527, unchanged). The **spec** completion deliberately terminates in `Update-Home`, which breaks the D-16 loop.

### Recommended Project Structure

```
UI/MainWindow.xaml        ← insert the static Home panel after <TextBlock x:Name="Heading"> (line 206)
                            ├─ StackPanel x:Name="Home"  Visibility=Collapsed
                            │   ├─ DockPanel x:Name="HomeHeader"  Margin="0,0,0,16"
                            │   │   └─ StackPanel: HostName (22/SemiBold/Tx) + HostSub (13/Mu)
                            │   └─ WrapPanel x:Name="Cards"  Orientation=Horizontal
                            ├─ Tuner / SvcTuner (unchanged, lines 209-279)
                            └─ StackPanel x:Name="Rows" (unchanged, line 281)

Akari.ps1                 ← edit in place, no new files
  ├─ line 34                $script:Cat = 'Home'            (D-14)
  ├─ after line 38           $script:SpecJob = $null; $script:SpecPending = $false
  ├─ after line 357          $HostIdentityFunc here-string + $SpecReadCode builder
  ├─ line 361                add 'Home','HostName','HostSub','Cards' to the Set-Variable list
  ├─ inside Show-Page (451)  Home branch: Heading/Home visibility + suppress empty message
  ├─ after Show-Page         Start-SpecRead, Update-Home, New-FailedSpecs
  ├─ inside tick (504-530)   new $script:SpecJob completion block
  ├─ line 567                add 'Home' to the sidebar foreach + insert the Bd divider
  └─ line 650-654            Add_Loaded unchanged (works as-is)
```

### Pattern 1: Read `Get-Specs`'s result shape as the renderer's contract

**What:** Every card is a pure function of one group hashtable. The renderer never re-queries and never inspects `_Status` to decide *whether* to render.
**When to use:** Always — the six-group contract is asserted by the Phase 2 verify command.

[VERIFIED: Akari.ps1:133-140] The initialized result, verbatim:

```
    $result = @{
        CPU = @{ _Status = 'OK' }
        RAM = @{ _Status = 'OK' }
        Windows = @{ _Status = 'OK' }
        GPU = @{ _Status = 'OK'; Adapters = @() }
        Disk = @{ _Status = 'OK'; Volumes = @() }
        Motherboard = @{ _Status = 'OK' }
    }
```

[VERIFIED: Akari.ps1:132-356] Live `Get-Specs` output keys on this host (probe, 2026-10-08), which is the exact inventory the renderer must map 1:1 per the UI-SPEC content map:

```
  CPU          _Status=OK       keys: _Status, Cores, Model, SpeedMHz, Threads
  Disk         _Status=OK       keys: _Status, Volumes
  GPU          _Status=OK       keys: _Status, Adapters
  Motherboard _Status=OK       keys: _Status, BIOSVersion, Manufacturer, Product, ReleaseDate
  RAM          _Status=OK       keys: _Status, FreeGB, TotalGB, UsedGB
  Windows      _Status=OK       keys: _Status, Build, Edition, Version
  GPU.Adapters[0] keys: DriverVersion, Model, Status, VRAM_GB
  Disk.Volumes[0] keys: Drive, FileSystem, FreeGB, Label, TotalGB
  Volumes on this host: 4 ; Adapters: 1
  Volume0: Drive='C:' Label='' FS='NTFS' Total=464.7 Free=298.6
  GPU0: Model='NVIDIA GeForce RTX 5070' VRAM_GB=11.9 Driver='32.0.16.1742' Status='OK'
  Windows Edition: Microsoft Windows 11 Pro  Build: 26300.9457
```

`_Status` is only `'OK'`, `'Partial'` or `'Failed'`, and is set by comparing a success counter against a field count. The renderer must **not** use it to skip a card: the UI-SPEC requires a card for every group in all states. `Failed` and `Partial` are already encoded per-field, because every failed field is the literal string `"Not available"` (Phase 1 D-10/D-11). Note the stale warning in `02-SUMMARY.md` "Disk `_Status` is `Partial` whenever a volume has no label": the live value is `OK` with 4 volumes including an unlabelled `C:`, because [VERIFIED: Akari.ps1:294] reads `# drive, filesystem, totalgb, freegb (label is descriptive and not counted)` and [VERIFIED: Akari.ps1:296] `$diskFields = 4`. That note is already resolved by plan 02-02 (WR-02).

[VERIFIED: Akari.ps1:38,516] — `$script:SpecData` appears exactly twice in the whole file (grep, 2026-10-08): the initialisation and the tick's single write. Nothing reads it yet, so this phase is its first consumer and may choose its shape freely (see Open Questions).

### Pattern 2: A second background channel that never touches `$script:Busy`

**What:** A sibling job slot, its own runspace, and a completion block inside the existing 150 ms tick.
**When to use:** The whole of REFR-01, D-06 through D-10.

[VERIFIED: Akari.ps1:480-483] — the three reasons `Invoke-Code` cannot be reused, verbatim:

```
function Invoke-Code([string]$code, [string]$label, $meta = $null, [string]$ResultVar = $null) {
    if ($script:Busy) { return }
    Set-Busy $true
    Add-Log $label
```

[VERIFIED: Akari.ps1:478] — `Set-Busy` disables the panel that contains Home, verbatim:

```
function Set-Busy([bool]$b) { $script:Busy = $b; $Page.IsEnabled = -not $b }
```

[VERIFIED: Akari.ps1:523] — the "Done" line that breaks D-07's silence, verbatim:

```
        Add-Log "Done: $($j.Label)"
```

[VERIFIED: Akari.ps1:506-508] — the queue drain at the top of every tick, the only cross-thread log bridge:

```
    $m = $null
    while ($script:Queue.TryDequeue([ref]$m)) { Add-Log $m }
```

[VERIFIED: Akari.ps1:510-512] — the completion predicate the new block must copy, verbatim:

```
    $j = $script:Job
    if ($j -and $j.Handle.IsCompleted) {
        try {
            if ($j.ResultVar) {
```

[VERIFIED: Akari.ps1:515-517] — the only writer of `$script:SpecData`, verbatim (note `ResultVar` is a *flag*, not a variable name — the destination is hard-coded):

```
                # output lands in the caller-supplied collection, endinvoke returns nothing
                $result = $j.ResultCollection
                if ($result -and $result.Count -gt 0) { $script:SpecData = $result[$result.Count - 1] } else { $script:SpecData = $null }
```

[VERIFIED: Akari.ps1:493-496] — the PS 5.1 runspace construction the new function must copy exactly (empty completed input collection):

```
        # ps 5.1 cannot bind the generic BeginInvoke overload with $null input, pass an empty completed collection
        $inputCollection = [System.Management.Automation.PSDataCollection[object]]::new()
        $inputCollection.Complete()
        $script:Job = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke($inputCollection, $resultCollection); Label = $label; Meta = $meta; ResultVar = $ResultVar; ResultCollection = $resultCollection }
```

**Empirically verified (probe 3, 2026-10-08), run against the real `$GetSpecsFunc` extracted from `Akari.ps1`:**

- A composite `@{ Specs = Get-Specs; Host = Get-HostIdentity }` survives the `PSDataCollection` boundary as a `Hashtable` with keys `Host`, `Specs`; `ResultCollection.Count = 1`.
- `$obj.Specs` groups are exactly `CPU,Disk,GPU,Motherboard,RAM,Windows` — **the six-group contract is intact**.
- `Get-HostIdentity` can call `Test-SmbiosValue` in the same runspace after the `$GetSpecsFunc` here-string is prepended.
- A **1.19 s** spec read completed while a **2 s** tweak job ran in a second runspace, with the spec result fully populated — this is the direct proof for D-08/D-10.
- A throwing read emits a `String` (`'boom: CIM unavailable'`), so the tick can distinguish success (hashtable with a `Specs` key) from failure; an empty read yields `Count = 0`.

### Pattern 3: `Show-Page` as the single "Home appeared" choke point

**What:** All three D-16 triggers already converge on `Show-Page`, so the refresh trigger goes there and nowhere else.
**When to use:** Always.

[VERIFIED: Akari.ps1:451-463] — the head of `Show-Page`, verbatim:

```
function Show-Page {
    $q = $Search.Text.Trim()
    $Rows.Children.Clear()
    if ($q) {
        $Heading.Text = "Results for `"$q`""
        $list = @($script:Tweaks | Where-Object { "$($_.Name) $($_.Description)" -like "*$q*" })
    } else {
        $Heading.Text = $script:Cat
        $list = @($script:Tweaks | Where-Object { $_.Category -eq $script:Cat })
    }
    $adv = (-not $q -and $script:Cat -eq 'Advanced')
    $Tuner.Visibility = if ($adv) { 'Visible' } else { 'Collapsed' }
    $SvcTuner.Visibility = $Tuner.Visibility
```

[VERIFIED: Akari.ps1:469-474] — the empty-state message that must be suppressed on Home, verbatim:

```
    if (-not $list.Count -and -not $adv) {
        $msg = [Windows.Controls.TextBlock]::new()
        $msg.Text = if ($q) { 'No scripts match.' } else { 'Nothing here yet.' }
        $msg.Foreground = $window.FindResource('Mu')
        [void]$Rows.Children.Add($msg)
    }
```

With `$script:Cat = 'Home'` and an empty search, `$list` is empty (no tweak uses `'Home'` as a category — grep over `Tweaks/` returns zero matches) and `$adv` is false, so **today Home would render "Nothing here yet."**. That line must gain a `-and -not $home` condition.

[VERIFIED: Akari.ps1:567-572] — the sidebar builder that must gain `'Home'` first, verbatim:

```
foreach ($c in 'Check', 'Refresh', 'Setup', 'Installers', 'Graphics', 'Windows', 'Hardware', 'Advanced') {
    $rb = [Windows.Controls.RadioButton]::new()
    $rb.Content = $c; $rb.Tag = $c; $rb.GroupName = 'nav'
    $rb.Style = $window.FindResource('Nav')
    [void]$Nav.Children.Add($rb)
}
```

[VERIFIED: Akari.ps1:573-578] — the nav handler, verbatim:

```
$Nav.AddHandler([Windows.Controls.Primitives.ToggleButton]::CheckedEvent, [Windows.RoutedEventHandler] {
    param($s, $ev)
    $script:Cat = [string]$ev.OriginalSource.Tag
    if ($Search.Text) { $Search.Text = '' }
    Show-Page
})
```

[VERIFIED: Akari.ps1:650-654] — the launch selection, verbatim; this is the entire SHELL-01 path:

```
$window.Add_Loaded({
    ($Nav.Children | Where-Object { $_.Tag -eq $script:Cat } | Select-Object -First 1).IsChecked = $true
    Add-Log 'Ready.'
    $script:Busy = $false
})
```

[VERIFIED: Akari.ps1:34] — the default category, verbatim:

```
$script:Cat    = 'Windows'
```

[VERIFIED: Akari.ps1:38] — the spec slot, verbatim:

```
$script:SpecData = $null
```

[VERIFIED: Akari.ps1:361] — the element shortcut list, verbatim; `Home`/`HostName`/`HostSub`/`Cards` must be appended here:

```
foreach ($n in 'Nav', 'Search', 'Heading', 'Tuner', 'SvcTuner', 'SvcCur', 'Rows', 'Page', 'Log', 'Hex', 'Dec', 'Logo') { Set-Variable $n $window.FindName($n) }
```

### Pattern 4: Host header with SMBIOS-filler fallback

[VERIFIED: Akari.ps1:104-130] — `Test-SmbiosValue` is defined inside `$GetSpecsFunc`, immediately before `Get-Specs`, with a 17-entry filler list that includes (verbatim, lines 108-126):

```
    $fillers = @(
        'To Be Filled By O.E.M.',
        'Default string',
        'None',
        'N/A',
        'Not Specified',
        'Not Available',
        'System Product Name',
        'System Manufacturer',
        'System Version',
        'System Serial Number',
        'Base Board Version',
        'Base Board Product',
        'Base Board Manufacturer',
        'BIOS Version',
        'BIOS Date',
        'x.x',
        '0'
    )
```

[VERIFIED: Akari.ps1:333-339] — the Motherboard query that supplies the fallback values, verbatim (note the filler filter is already applied to both board strings):

```
    $mbManufacturer = 'Not available'
    $mbProduct = 'Not available'
    $biosVersion = 'Not available'
    $biosDate = 'Not available'
    $mbFields = 4
    $mbSuccess = 0
    try {
        $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
        if ($board) {
            if (Test-SmbiosValue $board.Manufacturer) { $mbManufacturer = $board.Manufacturer.Trim(); $mbSuccess++ }
            if (Test-SmbiosValue $board.Product) { $mbProduct = $board.Product.Trim(); $mbSuccess++ }
        }
    } catch { }
```

**This host hits the ambiguous case for real.** Verified live: `Win32_ComputerSystem.Manufacturer = 'ASUS'` (passes the filler test) and `Win32_ComputerSystem.Model = 'System Product Name'` (**is** in the filler list, so it fails). Board fallback values are `ASUSTeK COMPUTER INC.` / `TUF GAMING B550-PLUS`. See Open Questions for how to read D-12 vs the UI-SPEC on this exact input.

### Anti-Patterns to Avoid

- **Calling `Invoke-Code` for the spec read.** It silently returns while a tweak runs (losing the read — D-09), disables `$Page` (D-08), and writes two log lines (D-07).
- **Building WPF objects in the runspace.** `Border`, `TextBlock`, `WrapPanel` and the parsed card `Border` must all be constructed on the UI thread inside `Update-Home`. The runspace returns *data only* (hashtables, strings, doubles).
- **Calling `Show-Page` from the spec-read completion handler.** This is the D-16 loop. Terminate the read's completion in `Update-Home`.
- **Using the `-f` format operator for spec numbers.** Verified to produce `3,80 GHz` on an `it-IT` host. Use `[double].ToString(format, [Globalization.CultureInfo]::InvariantCulture)`.
- **Adding a top-level group to `Get-Specs`.** Breaks the Phase 2 verify command. See Open Questions.
- **Setting an explicit `Height` on a card.** `WrapPanel` gives every card in a row the tallest card's height; an explicit height would defeat the shared-row layout that the UI-SPEC mandates.
- **Navigating to Home by assigning `$script:Cat` directly.** The existing `Nav` handler and `Add_Loaded` both drive `$script:Cat` through the `Checked` event; bypassing it leaves the sidebar selection and the page out of sync.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Background execution of the spec read | A new threading primitive (`Start-Job`, `RunspacePool`, `Task.Run`, `Dispatcher.Invoke`) | `[runspacefactory]::CreateRunspace()` + `[powershell]::Create()` + `BeginInvoke($emptyCompleted, $resultCollection)`, completed in the 150 ms `DispatcherTimer` | Exactly the pattern already proven in this codebase (Phase 1/2, including the PS 5.1 `BeginInvoke` overload fix). Anything else needs a new cross-thread bridge and a new stop path. |
| Cross-thread result delivery | A thread-safe callback, `Dispatcher.Invoke`, or `ConcurrentQueue` of results | The existing 150 ms tick's `Handle.IsCompleted` + `ResultCollection` check | Already works for `$script:SpecData`; the tick is on the UI thread so no marshalling is needed at all. |
| Card layout / flow | A manual column calculator, a `UniformGrid`, or per-breakpoint column counts | `System.Windows.Controls.WrapPanel` with fixed 240px cards | Measured to give 2 columns at 820 and 3 at 1000 with no code. `UniformGrid` cannot do "as many columns as fit". |
| Label/value row alignment | Canvas offsets or padding hacks | `Grid` with `ColumnDefinitions` `72` and `*` + `Grid.SetColumn` | Matches `New-Row`'s row `Grid` at `Akari.ps1:414-424` and the UI-SPEC's 72px label column. |
| Theme brushes | New `SolidColorBrush` objects or hard-coded hex colors | `{DynamicResource Key}` in XAML, `$window.FindResource('Key')` in code | The UI-SPEC's Theme Resources table is closed for Phase 3. `Inv`/`InvT`/`Warn`/`Bad` are off-limits. |
| SMBIOS filler detection | A second filler list or a regex | `Test-SmbiosValue`, already inside `$GetSpecsFunc` (`Akari.ps1:104-130`) | CONTEXT.md explicitly says "reuse for D-12 filler check". A second list would drift. |
| Empty-state / failed-state copy | New strings | The UI-SPEC Copywriting Contract: `Loading…`, `Not available`, and the two `Specs: Read failed (…)` variants | The contract is approved; inventing variants breaks the UI-consistency constraint. |

**Key insight:** This phase adds no algorithmic complexity — every hard problem (off-thread execution, SMBIOS filtering, VRAM capping, "Not available" per-field fallback) was solved and verified in Phases 1–2. The risk is entirely in *integration*: touching `Show-Page`, the tick, the nav builder and `$script:Cat`, each of which is load-bearing for the ~127 existing tweaks.

## Common Pitfalls

### Pitfall 1: Current-culture decimal separator (VERIFIED, will fire on this host)

**What goes wrong:** A CPU shows `3,80 GHz` and RAM shows `31,9 GB` instead of `3.80`/`31.9`.
**Why it happens:** PS 5.1's `-f` operator formats with the *current* culture. This host is `it-IT` (LCID 1040, decimal separator `,`); the app runs on the user's machine under whatever culture that is, and any user with a comma-decimal locale hits this.
**How to avoid:** Format every numeric spec with `$value.ToString($format, [Globalization.CultureInfo]::InvariantCulture)`. The UI-SPEC mandates this explicitly.
**Warning signs:** Verified reproduction — `'{0:0.00} GHz' -f (3801/1000)` returns `3,80 GHz`; `(3801/1000).ToString('0.00', InvariantCulture)` returns `3.80`.

### Pitfall 2: The `Not available` sentinel is a string and numeric `.ToString()` throws on it (VERIFIED)

**What goes wrong:** The renderer throws inside `Update-Home`, the exception is swallowed by `$window.Dispatcher.Add_UnhandledException` (`Akari.ps1:656-662`), and the cards never update — leaving `Loading…` on screen forever.
**Why it happens:** Every failed `Get-Specs` field is the literal string `"Not available"`. `[string]` has no `ToString(string, IFormatProvider)` overload.
**How to avoid:** Type-guard first. `if ($v -is [string] -or $null -eq $v) { … 'Not available', no unit … }` before any numeric format, per the UI-SPEC rule "with no unit. Never show `Not available GB`."
**Warning signs:** Verified reproduction — `'Not available'.ToString('0.00', $ci)` throws `MethodException: Cannot find an overload for "ToString" and the argument count: "2"`. By contrast `'{0:0.00}' -f 'Not available'` does *not* throw, which is exactly why `-f` hides the bug until the culture bug appears.

### Pitfall 3: D-16 refresh loop

**What goes wrong:** Specs re-read forever at ~1.5 s intervals; CPU spins and the log/UI churns.
**Why it happens:** `Show-Page` is called from the tick after every tweak job (`Akari.ps1:527`). If `Show-Page`'s Home branch triggers a read, and the read's completion calls `Show-Page`, the two call sites feed each other.
**How to avoid:** The spec-read completion block must call `Update-Home` only. `Show-Page` remains exclusively the *tweak*-completion destination. Additionally keep the one-flight guard in `Start-SpecRead`, which bounds any accidental loop to one read per ~1.5 s instead of a spin.
**Warning signs:** Watch for a repeating dim→bright cycle on Home with no user input; check whether `Update-Home` was ever allowed to reach `Show-Page`.

### Pitfall 4: Two `Show-Page` calls per Home click (VERIFIED)

**What goes wrong:** Two spec reads start per navigation (the second is a wasted CIM pass).
**Why it happens:** The nav handler sets `$Search.Text = ''` when the search box is non-empty, and clearing a non-empty box raises `TextChanged` → `Show-Page`; the handler then calls `Show-Page` itself. Two calls, both landing in the Home branch.
**How to avoid:** One-flight guard at the top of `Start-SpecRead`: `if ($script:SpecJob) { return }`.
**Warning signs:** Verified reproduction — `$search.Text = 'bios'` then `$search.Text = ''` produced one `TextChanged` event, and the nav handler's own `Show-Page` is a second entry.

### Pitfall 5: `Add_Loaded` runs the nav handler synchronously (VERIFIED)

**What goes wrong:** Anything the spec read depends on must already exist by line 651 — including any code added *after* `$window.Add_Loaded`.
**Why it happens:** Setting `IsChecked = $true` on a `RadioButton` raises `Checked` synchronously; the handler registered on `$Nav` receives it immediately, so `Show-Page` (and any new `Start-SpecRead`) runs *inside* `Add_Loaded`, before `Add-Log 'Ready.'` at line 652.
**How to avoid:** Define `Start-SpecRead`, `Update-Home` and the new `$script:SpecJob` state **above** line 650. The tick and its variables are already defined at lines 504-530, so this is ordering-safe as written.
**Warning signs:** Verified reproduction — one `Checked` event fired at the property set with `OriginalSource` = the `RadioButton` and `Tag=Home`.

### Pitfall 6: Home shows "Nothing here yet." (VERIFIED)

**What goes wrong:** The Home page renders a grey "Nothing here yet." message under the cards.
**Why it happens:** `Show-Page`'s empty-state branch (`Akari.ps1:469-474`) fires whenever `$list.Count -eq 0` and the category is not Advanced. Home is a new empty category.
**How to avoid:** Add `-and -not $home` to that condition, where `$home = (-not $q -and $script:Cat -eq 'Home')`.
**Warning signs:** The UI-SPEC E6 row states this explicitly: "`Nothing here yet.` does not appear".

### Pitfall 7: Single-job slot clobbering

**What goes wrong:** A tweak job and a spec job overwrite each other; one is lost without disposal, leaking a runspace per occurrence.
**Why it happens:** `$script:Job` is one associative slot written unconditionally at `Akari.ps1:496` and `:500`, and the tick disposes only "the last one".
**How to avoid:** Use a separate `$script:SpecJob` slot with its own dispose path in its own tick block. Never let the two blocks touch each other's slot.

### Pitfall 8: Search-active rows on Home

**What goes wrong:** A user on Home types a query, clicks a tweak's Optimize button, and the post-tweak `Show-Page` behaves unexpectedly.
**Why it happens:** With a non-empty search, `$Rows` is populated with real tweak rows *regardless of `$script:Cat`* (`Akari.ps1:456`). So a tweak can start while `$script:Cat -eq 'Home'`.
**How to avoid:** The Home branch condition must be `$script:Cat -eq 'Home' -and -not $q` — not `$script:Cat -eq 'Home'` alone. When the search is non-empty the Home panel stays hidden and no read starts, which is already the correct behavior.

### Pitfall 9: Re-entrancy from a `RadioButton` `Checked` handler during `Add_Loaded` (VERIFIED)

**What goes wrong:** If a future change makes the Home branch do work that assumes `Loaded` has finished, it will misbehave.
**Why it happens:** Confirmed — the launch `Checked` fires synchronously inside `Add_Loaded`, so `Show-Page` runs before the `Loaded` handler completes.
**How to avoid:** Keep the Home branch free of anything that requires layout to be finished (no `ActualWidth` reads, no scroll manipulation). Note that `ComputedVerticalScrollBarVisibility` / `ActualWidth` are only meaningful after a real layout pass — measure them in a probe or at UAT, never at launch.
**Warning signs:** Verified — the launch path runs the nav handler once, synchronously, with no read of any `Actual*` property anywhere in the existing code.

### Pitfall 10: Dimming the wrong elements

**What goes wrong:** `HostName` dims (UI-SPEC: it stays at full opacity), or nothing dims at all.
**Why it happens:** The dimming rule is scoped to exactly two elements: the `Cards` WrapPanel and `HostSub`.
**How to avoid:** Set `$Cards.Opacity` and `$HostSub.Opacity` only. Never touch `$HostName.Opacity`, and never dim `$Rows`/`$Page`.

### Pitfall 11: Ticker tail order

**What goes wrong:** A spec result rendered "before" a tweak completion produces a one-frame stale header.
**Why it happens:** If both jobs complete in the same tick, the two blocks run back to back.
**How to avoid:** Place the spec block *before* the tweak-job block so the tweak block's `Show-Page` (line 527) runs last and re-renders Home from the already-updated `$script:SpecData`.

### Pitfall 12: PS 5.1 `BeginInvoke` overload trap (already fixed once — do not regress)

**What goes wrong:** `BeginInvoke` throws "Cannot find an overload for BeginInvoke", which also leaves `Set-Busy` stuck on.
**Why it happens:** `$ps.BeginInvoke($null, $resultCollection)` is unbindable in PS 5.1. Phase 2 fixed this with an empty completed `PSDataCollection` input.
**How to avoid:** Copy `Akari.ps1:493-496` verbatim. Never pass `$null` as the input collection.

## Code Examples

### Home panel markup for `UI/MainWindow.xaml`

Insert after `<TextBlock x:Name="Heading" …/>` (line 206) and before the Tuner `Border` (line 208). Values are the UI-SPEC Layout Contract verbatim:

```xml
<!-- Home page (Phase 3). Visible only when Cat = Home AND the search box is empty. -->
<StackPanel x:Name="Home" Visibility="Collapsed">
  <DockPanel x:Name="HomeHeader" Margin="0,0,0,16">
    <!-- right side reserved for the Phase 4 copy button -->
    <StackPanel>
      <TextBlock x:Name="HostName" FontSize="22" FontWeight="SemiBold" Foreground="{DynamicResource Tx}"
                 TextTrimming="CharacterEllipsis"/>
      <TextBlock x:Name="HostSub" FontSize="13" Foreground="{DynamicResource Mu}" Margin="0,4,0,0"
                 Visibility="Collapsed" TextTrimming="CharacterEllipsis"/>
    </StackPanel>
  </DockPanel>
  <WrapPanel x:Name="Cards" Orientation="Horizontal"/>
</StackPanel>
```

Verified layout facts backing this markup (probe 1, 2026-10-08, measuring the real window with a UI-SPEC-shaped panel injected into the real `Page` element):

| Outer window width | Main grid column | Card X positions | Columns |
|---|---|---|---|
| 820 (`MinWidth`) | 565 DIPs | `0, 248` | **2** |
| 1000 (default) | 745 DIPs | `0, 248, 496` | **3** |

Card `ActualWidth` = 240 in both cases; row 2 begins at `Y = 238` (230 tall card + 8 margin); cards in a row all share the tallest card's `ActualHeight` (row 1 at 820: `230, 230, 104, 104, 104, 104`). The 3-column fit at 1000 has only ~1 DIP of slack (`745 − 744 = 1`), so treat "3 columns at the default width" as confirmed-but-tight and re-measure during UAT.

### The second background channel

```powershell
# ---- script state, next to $script:SpecData = $null (Akari.ps1:38)
$script:SpecJob    = $null      # { Ps; Rs; Handle; ResultCollection } for the in-flight spec read
$script:SpecPending = $false    # D-09: a read was requested while a tweak was running

# ---- the read code: $GetSpecsFunc (unchanged) + host identity + one composite result
$HostIdentityFunc = @'
function Get-HostIdentity {
    $m = 'Not available'; $mdl = 'Not available'
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1
        if ($cs.Manufacturer) { $m = $cs.Manufacturer.Trim() }
        if ($cs.Model) { $mdl = $cs.Model.Trim() }
    } catch { }
    if (-not (Test-SmbiosValue $m)) { $m = 'Not available' }
    if (-not (Test-SmbiosValue $mdl)) { $mdl = 'Not available' }
    return @{ Manufacturer = $m; Model = $mdl }
}
'@
$SpecReadCode = $GetSpecsFunc + "`n" + $HostIdentityFunc + @'

try { @{ Specs = Get-Specs; Host = Get-HostIdentity } } catch { $_.Exception.Message }
'@

# ---- the read: no Busy guard, no Set-Busy, no start/Done log line
function Start-SpecRead {
    if ($script:SpecJob) { return }                                  # one read in flight (also collapses the double Show-Page)
    if ($script:Busy) { $script:SpecPending = $true; return }        # D-09: deferred, never lost, never blocking
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $resultCollection = [System.Management.Automation.PSDataCollection[object]]::new()
    [void]$ps.AddScript($SpecReadCode)
    # ps 5.1 cannot bind the generic BeginInvoke overload with $null input, pass an empty completed collection
    $inputCollection = [System.Management.Automation.PSDataCollection[object]]::new()
    $inputCollection.Complete()
    $script:SpecJob = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke($inputCollection, $resultCollection); ResultCollection = $resultCollection }
}

# ---- completion, as a NEW block inside the existing 150 ms tick (Akari.ps1:504-530)
$sj = $script:SpecJob
if ($sj -and $sj.Handle.IsCompleted) {
    $had = ($null -ne $script:SpecData)          # capture BEFORE overwriting: decides the error wording
    $result = $sj.ResultCollection
    $ok = $false; $msg = $null
    if ($result -and $result.Count -gt 0) {
        $obj = $result[$result.Count - 1]
        if ($obj -is [hashtable] -and $obj.ContainsKey('Specs')) { $script:SpecData = $obj; $ok = $true }
        else { $msg = [string]$obj }             # the catch branch emitted the exception message
    } else { $msg = 'no result returned' }       # E7: "throws or returns nothing"
    try { [void]$sj.Ps.EndInvoke($sj.Handle) } catch { $msg = "$($_.Exception.Message)" }
    foreach ($err in $sj.Ps.Streams.Error) { Add-Log "Error: $($err.ToString())" }
    $sj.Ps.Dispose(); $sj.Rs.Dispose()
    $script:SpecJob = $null
    $script:SpecPending = $false
    if (-not $ok) {
        if (-not $had) { $script:SpecData = New-FailedSpecs }        # E7: never stay on "Loading…"
        $tail = if ($had) { ' Showing last known values.' } else { ' Switch to another page and back to Home to try again.' }
        Add-Log "Specs: Read failed ($msg).$tail"
    }
    Update-Home          # NEVER Show-Page here (D-16)
}
```

The `$script:SpecPending` drain belongs at the very end of the existing tweak-completion block, after `Show-Page` (`Akari.ps1:527`):

```powershell
        Show-Page
        if ($script:SpecPending) { Start-SpecRead }     # D-09: auto re-read once the tweak finishes
```

### Card renderer skeleton (values from `Get-Specs`, formatting per the UI-SPEC)

```powershell
# 'Not available' is the sentinel that every failed Get-Specs field carries; it must never be
# fed a numeric format (verified: 'Not available'.ToString('0.00', $ci) throws).
function Fmt-Val($v, [string]$fmt, [string]$unit) {
    if ($null -eq $v -or $v -is [string]) {
        if ("$v" -eq 'Not available' -or [string]::IsNullOrEmpty("$v")) { return "$v" }
        return "$v$unit"
    }
    return $v.ToString($fmt, [Globalization.CultureInfo]::InvariantCulture) + " $unit"
}

function Add-Row([Windows.Controls.Grid]$g, [string]$label, [string]$value) {
    $l = [Windows.Controls.TextBlock]::new()
    $l.Text = $label; $l.Width = 72; $l.FontSize = 12
    $l.Foreground = $window.FindResource('Mu'); $l.VerticalAlignment = 'Top'
    [void]$g.Children.Add($l)
    $v = [Windows.Controls.TextBlock]::new()
    $v.Text = $value; $v.FontSize = 13; $v.TextWrapping = 'Wrap'
    $v.Foreground = $window.FindResource('Tx')
    [Windows.Controls.Grid]::SetColumn($v, 1)
    [void]$g.Children.Add($v)
}
```

Verified real values for the six cards (probe 3, 2026-10-08) — use these to sanity-check the renderer:

| Card | Headline / rows from live data |
|------|-------------------------------|
| CPU | `AMD Ryzen 7 7800X3D 8-Core Processor`; `Cores` → `8 / 16 threads`; `Speed` → `3.80 GHz` |
| GPU | `NVIDIA GeForce RTX 5070`; `VRAM` → `11.9 GB`; `Driver` → `32.0.16.1742`; no `Status` row (`Status = 'OK'`) |
| RAM | `31.9 GB`; `Used` / `Free` |
| Disk | `C:` (no `Label`, so no two-space suffix); `Free`, `Total`, `File system` → `NTFS`; plus 3 more volumes |
| Board | `ASUSTeK COMPUTER INC. TUF GAMING B550-PLUS`; `BIOS`, `Released` |
| Windows | `Windows 11 Pro` (raw caption is `Microsoft Windows 11 Pro`); `Version` → `24H2`; `Build` → `26300.9457` |

`Windows.Edition` display strip: verified `'Microsoft Windows 11 Pro'.TrimStart('Microsoft ')` → `Windows 11 Pro` (the `-replace '^Microsoft\s+',''` form gives the same result). The middle dot is `[char]0x00B7` and the ellipsis is `[char]0x2026` — both single characters, both invisible in a PS 5.1 *console* but rendered correctly by WPF.

### Header source resolution (D-11 / D-12)

```powershell
# order: Win32_ComputerSystem pair -> Motherboard pair -> Collapsed
$sysM = $d.Host.Manufacturer; $sysD = $d.Host.Model
if ($sysM -eq 'Not available' -and $sysD -eq 'Not available') {
    $sysM = $d.Specs.Motherboard.Manufacturer
    $sysD = $d.Specs.Motherboard.Product       # already SMBIOS-filtered at Akari.ps1:336-337
}
$parts = @($sysM, $sysD) | Where-Object { $_ -and $_ -ne 'Not available' }
# UI-SPEC: "If exactly one of the pair is valid, show just that one, with no dot"
$HostSub.Text = ($parts -join ' · ')
$HostSub.Visibility = if ($parts.Count) { 'Visible' } else { 'Collapsed' }
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `Invoke-Code -Result` with `BeginInvoke($null, $collection)` | Empty completed `PSDataCollection` input + read `ResultCollection` in the tick | Phase 2 commit `210bc5f`, 2026-10-08 | `$script:SpecData` actually populates on PS 5.1; before this it threw and left `Set-Busy` stuck. Do not regress. |
| GPU VRAM from `Win32_VideoController.AdapterRAM` | Registry `HardwareInformation.qwMemorySize` with `qwSize` legacy fallback | Phase 2 commit `ce4de3b`, 2026-10-08 | RTX 5070 reads 11.9 GB instead of a capped 4 GB. |
| `$script:Cat = 'Windows'` default landing | `$script:Cat = 'Home'` default landing | **This phase** | SHELL-01. |
| Every runspace job goes through `$script:Busy` | A second, independent job slot that never sets `$script:Busy` | **This phase** | REFR-01, D-08/D-09/D-10. |

**Deprecated / not applicable here:**
- No web framework, no React/shadcn component library — the UI-SPEC records `shadcn_initialized: false`, `preset: none`, `Tool: none`. Any suggestion to use a component library or a UI framework is out of scope by AGENTS.md.
- No icon library, no glyph fonts, no images on Home (UI-SPEC Design System: "Text-only UI"). Do not add `FontIcon`, Segoe MDL2, or `FontAwesome`.
- `02-SUMMARY.md`'s "Notes for Phase 3" claim that `Disk._Status` is `Partial` when a volume has no label is stale — the live value is `OK` (verified above). Do not build a Phase 3 workaround for it.

## Assumptions Log

> Claims below are **not** tool-verified in this session: they rest on a document-vs-document conflict, on a design choice not yet ratified, or on training knowledge about platform behaviour. They are recorded here (rather than tagged inline) because none is a claim about the repo's source of truth — every in-repo value in this document carries a `[VERIFIED: <path>:<line>]` tag with the value quoted verbatim beside it. The planner and discuss-phase use this table to identify what needs user confirmation before it becomes a locked decision.
|---|-------|---------|---------------|
| A1 | The recommended reading of the header fallback is "system pair first; fall back to the board pair only when **both** system values are filler". D-12 says "When system maker/model are SMBIOS filler", while the UI-SPEC says "If **either** is SMBIOS filler … use Motherboard". The two documents disagree on the trigger. | Pattern 4, Open Questions | Cosmetic: the header line reads differently. On this host the literal UI-SPEC reading gives `ASUSTeK COMPUTER INC. · TUF GAMING B550-PLUS`, the D-12 reading gives `ASUS`. Both are valid Phase 3 outcomes, but the planner must pick one and a `checkpoint:human-verify` should confirm it. |
| A2 | Inserting host identity into the read as a composite `@{ Specs; Host }` (leaving `Get-Specs` byte-identical) is acceptable to the project. It changes `$script:SpecData`'s shape from "the six-group hashtable" to "a wrapper around it". | Pattern 2, Open Questions | Low. `$script:SpecData` has no consumer today, so nothing existing breaks. Phase 4 must know the shape. |
| A3 | Two runspaces running concurrently (one tweak, one spec read) is safe on all supported Windows 10/11 versions. Verified on this host (Win 11 build 26300) with a 2 s tweak job and a 1.19 s spec read. | Pattern 2 | Low. Runspaces are the codebase's established primitive; `Invoke-Code` already creates one per tweak. |
| A4 | The 3-column fit at the default 1000px width survives on the user's machine. Verified on this host with ~1 DIP of slack. | Code Examples | Cosmetic: at 1000 the grid could show 2 columns instead of 3. The UI-SPEC's 340 DIPs of headroom at 820 is comfortable; only the 3-column claim is tight. |
| A5 | `Test-SmbiosValue`'s `-contains` operator is case-insensitive (as `02-SUMMARY.md` reports), so a filler spelled `system product name` would still be rejected. | Pattern 4 | Low; the codebase intentionally kept `-contains`. |
| A6 | `$env:COMPUTERNAME` is always populated and needs no "Loading…" state (UI-SPEC: "available immediately at launch and never shows Loading…"). Verified `String` type, non-empty on this host. | Pattern 3, UI-SPEC | Very low. |
| A7 | WPF renders `U+00B7` and `U+2026` correctly even though a PS 5.1 console shows them mangled. | Code Examples | Very low; the UI-SPEC already specifies both characters by code point. |

**If this table is empty:** not empty — items A1 and A2 need a human decision (see Open Questions); the rest are low-risk confirmations.

## Open Questions

1. **Header fallback trigger — "either" (UI-SPEC) vs "both" (CONTEXT D-12)?**
   - What we know: D-11/D-12 say the header line is `Win32_ComputerSystem` Manufacturer/Model, falling back to the motherboard pair when "system maker/model are SMBIOS filler". The UI-SPEC restates it as "If **either** is SMBIOS filler … use Motherboard Manufacturer/Product instead", and separately "If exactly one of the pair is valid, show just that one, with no dot". The two rules only both make sense if the fallback is pair-level.
   - What's unclear: does one filler value trigger the whole-pair fallback, or does each slot substitute independently?
   - **Verified live input on this host:** `Win32_ComputerSystem.Manufacturer = 'ASUS'` (valid), `Win32_ComputerSystem.Model = 'System Product Name'` (filler), board = `ASUSTeK COMPUTER INC.` / `TUF GAMING B550-PLUS`. The three candidate outputs are `ASUS`, `ASUS · TUF GAMING B550-PLUS`, and `ASUSTeK COMPUTER INC. · TUF GAMING B550-PLUS`.
   - Recommendation: implement the **literal UI-SPEC rule** ("either filler → use the board pair"), because the UI-SPEC is the approved contract and the board pair is the more specific identity. Flag it for a `checkpoint:human-verify` in the plan, since it changes visible output on this machine.

2. **Where should host identity live in the result?**
   - What we know: the Phase 2 verify command asserts `$r.Keys` sorted equals `"CPU,Disk,GPU,Motherboard,RAM,Windows"`, so a new top-level `System` group fails the run. Adding keys to an existing group (e.g. `Motherboard.SystemManufacturer`/`SystemModel`) keeps both the contract and `$script:SpecData`'s existing shape.
   - What's unclear: is a wrapper hashtable (`@{ Specs; Host }`) acceptable as "the spec read" shape going into Phase 4?
   - Recommendation: the wrapper. It leaves `Get-Specs` byte-identical (zero regression risk on the most heavily verified asset in the phase) and reuses `Test-SmbiosValue` in the same runspace, which the in-group alternative also does. [VERIFIED: Akari.ps1:38,516] — `$script:SpecData` has no reader anywhere in the file today, so no existing consumer breaks either way. The in-group alternative (`Motherboard.SystemManufacturer`/`SystemModel`) is a valid fallback if a reviewer objects to the shape change — it changes only `Akari.ps1:326-353` and leaves no other consumer to update.

3. **Should the spec read also run once at app start even if Home is never shown?**
   - What we know: Home *is* the default landing tab, so the launch read happens anyway. The question only matters if a future change makes Home non-default.
   - Recommendation: no. The trigger stays exactly where D-16 says: launch, Home click, search clear. Adding an eager read would create a CIM pass on every launch regardless of user intent.

4. **What happens to an in-flight spec read at window close?**
   - What we know: `$window.Add_Closing({ $timer.Stop })` (`Akari.ps1:663`) stops the only completion path. PowerShell runspace threads are background threads, so the process exits and the read is abandoned.
   - Recommendation: no action. At most, note in the plan that a closing mid-read loses that read's result, which is invisible to the user because the values are re-read on the next Home show.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Windows PowerShell 5.1 | Whole phase | ✓ | 5.1.26100.9444 (Desktop) | none — required |
| STA apartment state | WPF host | ✓ | ✓ (verified STA) | none — relaunched by `Akari.ps1:8-13` |
| Administrator elevation | Tweak engine + spec reads | ✓ | ✓ | none — self-elevates via `Start-Process -Verb RunAs` |
| `PresentationFramework` / `PresentationCore` / `WindowsBase` / `System.Xaml` | All WPF + WrapPanel | ✓ | .NET Framework 4.0.30319.42000 | none — inbox |
| `Get-CimInstance` (WMI) | `Get-Specs`, `Get-HostIdentity` | ✓ | Win 11 build 26300 | none — per-field "Not available" fallback already built in |
| Git | Phase commits | ✓ | — | none |

**Missing dependencies with no fallback:** none. This phase needs nothing that is not already present on the target machine and already required by the app.
**Missing dependencies with fallback:** none.

Note: the phase introduces no external tool, service, database, or CLI beyond what the app already requires, so the audit is a formality — it exists to prove the point rather than to discover a gap.

## Validation Architecture

**Skipped — `workflow.nyquist_validation` is `false` in `.planning/config.json`.** No test framework, test directory, or `*.test.*`/`*.spec.*`/`Pester` file exists in the repo (`AGENTS.md` / `STACK.md`: "None. No test runner, assertion library … detected"). The established verification pattern for this project is parse-check commands plus end-of-phase human UAT (`human_verify_mode: "end-of-phase"`).

The prior-phase verify command that **must keep passing** is reproduced here for the planner to re-run verbatim (confirmed passing on commit `8c45682`, 2026-10-08: `PASS live: groups=CPU,Disk,GPU,Motherboard,RAM,Windows`):

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '$e=$null;$t=[System.Management.Automation.Language.Parser]::ParseFile("$PWD\Akari.ps1",[ref]$null,[ref]$e);if($e.Count){"FAIL: Akari.ps1 parse errors";exit 1};$s=$t.Find({param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -match "function Get-Specs"},$true);if(-not $s){"FAIL: Get-Specs here-string not found";exit 1};. ([scriptblock]::Create($s.Value));$r=Get-Specs;$g=($r.Keys|Sort-Object) -join ",";if($g -cne "CPU,Disk,GPU,Motherboard,RAM,Windows"){"FAIL: groups=$g";exit 1};"PASS live: groups=$g"'
```

**Recommended new verify command** for the XAML edit (verified working headlessly — `[Windows.Markup.XamlReader]::Parse` succeeds without an `Application` or a running message loop, and `FindName` resolves every named element afterwards):

```powershell
$e=$null
[void][System.Management.Automation.Language.Parser]::ParseFile("$PWD\Akari.ps1",[ref]$null,[ref]$e)
if ($e.Count) { "FAIL: Akari.ps1 parse errors"; exit 1 }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
$w = [Windows.Markup.XamlReader]::Parse((Get-Content "$PWD\UI\MainWindow.xaml" -Raw))
foreach ($n in 'Home','HostName','HostSub','Cards') {
  if (-not $w.FindName($n)) { "FAIL: missing x:Name=$n"; exit 1 }
}
"PASS: Akari.ps1 parses and MainWindow.xaml exposes Home/HostName/HostSub/Cards"
```

## Security Domain

`security_enforcement` is `true` (absent = enabled), ASVS level 1. This phase is a local, read-only UI surface with **no new input, no network, no authentication, no persistence change, and no new privileges** — but the mitigations must still be stated so the plan-checker can confirm them.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V1 Architecture | yes | Zero new dependencies; single-file host; no network I/O; all queries are local CIM/registry reads the app already performs. |
| V2 Authentication | no | Not applicable — the app is a single-user elevated desktop tool with no identity concept. |
| V3 Session Management | no | Not applicable — no sessions or tokens. |
| V4 Access Control | no | No authorization surface. The process is already fully elevated; Home adds no new privileged operation. |
| V5 Input Validation | yes (limited) | Spec values are display-only text. Any value that reaches a XAML string must be XML-escaped — the existing `$e = { param($s) [Security.SecurityElement]::Escape([string]$s) }` helper at `Akari.ps1:383` already encodes this rule for `New-Row`. |
| V6 Cryptography | no | No secrets, keys, or hashing. |
| V7 Error Handling | yes | The read failure path must never leave a card on "Loading…" and must write exactly one log line (UI-SPEC E7). The host-level safety nets are unchanged. |
| V12 Files | no | Phase 3 writes no files. (`Get-Specs` reads registry only; `state.json` is untouched.) |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| XAML/markup injection via a spec string (a hostile or malformed `Win32_VideoController.Name`, volume label, or product name interpolated into a card) | Tampering / Spoofing | XML-escape every interpolated value before it enters card markup. `New-Row` already does this with `[Security.SecurityElement]::Escape`; the card renderer must copy that habit rather than raw string concatenation. Building cards from .NET objects (`TextBlock.Text = $value`) instead of a XAML string sidesteps this entirely and is the recommended approach. |
| Runspace exception losing the refresh (UI silent, values stale) | Denial of service / Information disclosure of stale data | The try/catch + `ResultCollection` read in the tick, plus `New-FailedSpecs` on first-load failure. The existing `$window.Dispatcher.Add_UnhandledException` handler (`Akari.ps1:656-662`) already converts any slipped exception into `akari.log` + a drawer line. |
| Infinite refresh loop consuming CPU/CIM (self-inflicted DoS) | Denial of service | One-flight guard + "never `Show-Page` from `Update-Home`". Bounded to one read per ~1.5 s even if the rule is broken. |
| UI-thread blocking during a spec read (hang perception) | Denial of service | All CIM work in the background runspace; the tick does only `IsCompleted` checks and object assignment. Verified: a 1.19 s read ran concurrently with a 2 s tweak with no UI-thread involvement. |
| Expanded process lifetime / non-elevated relaunch edge cases | Elevation of privilege | Unchanged from the existing host. No new `Start-Process`, no new `RunAs`, no `Run-Trusted` involvement. |

**Registry safety:** none. The UI-SPEC's Registry Safety section records "none. The WPF/PowerShell project has no component registry, and no third-party code is introduced." `Get-Specs` reads `HKLM` only via `Get-ItemProperty` (`Akari.ps1:203`, `:233`) — no writes anywhere in Phase 3.

## Sources

### Primary (HIGH confidence — read this session with `Read` and/or probed live)
- `Akari.ps1` (664 lines) — read in full. Every `[VERIFIED: Akari.ps1:…]` tag quotes the value verbatim at the cited range. Specifically: `1`, `8-13`, `15`, `34`, `38`, `71-101` (`$Helpers`), `103-357` (`$GetSpecsFunc`, `Test-SmbiosValue`), `104-130`, `132-356`, `133-140`, `203`, `233`, `294`, `296`, `326-353`, `326-339`, `333-339`, `361`, `383`, `451-463`, `451-475`, `469-474`, `478`, `480-483`, `480-502`, `489-496`, `493-496`, `504-530`, `506-508`, `510-512`, `515-517`, `523`, `526`, `527`, `567-572`, `573-578`, `622`, `650-654`, `656-662`.
- `UI/MainWindow.xaml` (292 lines) — read in full. `3-6`, `9-18`, `133-155`, `135`, `159-162`, `173`, `204-206`, `209-279`, `281`, `285-289`, `244`.
- Live probe suite (2026-10-08, `powershell.exe -NoProfile -ExecutionPolicy Bypass -STA`): parse + `Get-Specs` execution returning groups `CPU,Disk,GPU,Motherboard,RAM,Windows`; per-group key inventory; 240px `WrapPanel` column counts at 820/1000 and row-height stretch; `RadioButton` `Checked` firing synchronously at `IsChecked = $true` with `OriginalSource.Tag` correct; `TextBox.TextChanged` behaviour on same-value vs clearing assignments; the composite `@{ Specs; Host }` runspace path including a concurrent 2 s job; current-culture vs invariant formatting; `'Not available'.ToString('0.00', $ci)` throwing; `[Windows.Controls.*]` type-accelerator resolution; headless `XamlReader.Parse` of the real XAML.
- `.planning/config.json` — `workflow.nyquist_validation: false`, `workflow.security_enforcement: true`, `human_verify_mode: "end-of-phase"`.
- `.planning/phases/03-home-shell-live-refresh/03-CONTEXT.md` — D-01 … D-16 (copied verbatim into `<user_constraints>`).
- `.planning/phases/03-home-shell-live-refresh/03-UI-SPEC.md` — the approved design contract (Layout Contract, Card table, per-card content map, Interaction & State Contract, Copywriting Contract, UI Considerations E1–E7).
- `.planning/REQUIREMENTS.md` (SHELL-01/02/03, REFR-01), `.planning/ROADMAP.md` §Phase 3, `.planning/PROJECT.md`, `.planning/STATE.md`.
- `.planning/phases/02-hardware-spec-cards/02-SUMMARY.md` (esp. the `-ResultVar` PS 5.1 fix and the `Invoke-Code ($GetSpecsFunc + "`nGet-Specs") '…' $null 'SpecData'` readiness note), `.planning/phases/01-spec-query-engine/01-CONTEXT.md`.
- `.planning/codebase/STACK.md`, `ARCHITECTURE.md`, `CONVENTIONS.md` (via the injected `AGENTS.md` blocks).
- Grep over `Tweaks/` for `Category = 'Home'` — zero matches.

### Secondary (MEDIUM confidence)
- WPF `WrapPanel` cross-direction line-height stretch behaviour — empirically confirmed on this host rather than recalled; behaviour is a WPF (inbox .NET) invariant, so it holds for Windows 10 as well as 11.
- The PSDataCollection result-delivery mechanism is the Phase 2 integration-verified path (`02-SUMMARY.md` D4), re-confirmed here with a composite payload.

### Tertiary (LOW confidence)
- None. No external documentation was consulted: the phase introduces no third-party packages, every dependency is an inbox .NET Framework assembly, and the authoritative source for every claim is the codebase itself. The configured search providers (`brave_search`, `exa_search`, `firecrawl`, `tavily_search`, `ref_search`, `perplexity`, `jina`) are all `false` in `.planning/config.json` and no Context7/ref/jina MCP tool is available in this session, so no `research-plan` fetch was issued — external docs could not have added evidence, and inventing citations would have violated the claim-provenance rules.

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — every component is an inbox assembly already loaded by `Akari.ps1:15`; runtime version measured live (5.1.26100.9444 / CLR 4.0.30319.42000). Zero external packages, so no registry or slopsquat surface exists.
- Architecture: **HIGH** — the recommended channel was executed end to end against the real `$GetSpecsFunc`, including a concurrent tweak job; the event ordering claims (`Checked` synchronous at launch, `TextChanged` on clearing, one `Checked` per nav change) were each reproduced live.
- Pitfalls: **HIGH** — the culture bug and the `Not available` `.ToString()` throw were reproduced with actual failing and passing output on this host; the loop, double-`Show-Page`, and "Nothing here yet." pitfalls are derived from verified code plus verified event counts.
- Open questions A1 (header fallback trigger) and A2 (result shape) are deliberately unresolved: they are product/contract decisions, not technical unknowns.

**Research date:** 2026-10-08
**Valid until:** 2026-10-08 + 30 days (stable: the stack is Windows PowerShell 5.1, which is feature-frozen; re-verify only if `Akari.ps1`, `UI/MainWindow.xaml`, or `.planning/config.json` changes underneath this phase).
