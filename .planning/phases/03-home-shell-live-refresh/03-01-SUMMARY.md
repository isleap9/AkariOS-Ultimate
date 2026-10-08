---
phase: 03-home-shell-live-refresh
plan: 01
subsystem: ui
tags: [powershell, wpf, runspace, dispatchertimer, home-page, spec-cards]

requires:
  - phase: 02-hardware-spec-cards
    provides: "Get-Specs six-group contract (CPU, RAM, Windows, GPU, Disk, Motherboard) inside the $GetSpecsFunc here-string"
provides:
  - "Home as the default landing category, first sidebar item above a non-focusable 1px Bd divider"
  - "Static HomePanel in MainWindow.xaml (HomeHeader DockPanel with HostName/HostSub, Cards WrapPanel)"
  - "$HostIdentityFunc (Get-HostIdentity) + $SpecReadCode composite read: @{ Specs = Get-Specs; Host = Get-HostIdentity }"
  - "Start-SpecRead: second background channel ($script:SpecJob), one-flight, deferred via $script:SpecPending while a tweak runs"
  - "Spec-completion block in the 150 ms tick, ahead of the tweak block, ending in Update-Home (never Show-Page)"
  - "Card renderer: Update-Home, New-Card, Add-Headline, Add-Row, Add-Loading, Add-Divider, Fmt-Num, New-FailedSpecs"
  - "Six cards in fixed order CPU, GPU, RAM, Disk, Board, Windows with multi-instance GPU/Disk blocks"
affects: [03-02, phase-04-copy-specs]

actuals:
  tokens: 4012
  tasks: 2
  commits: 2

plan_head_before: 2394fc1f5159b69ab6a4547571afd225fe597fd8
plan_head_after: cb0a303c37edc7479f200b5d037481506aa07957

tech-stack:
  added: []
  patterns:
    - "Second runspace job slot ($script:SpecJob) harvested by the existing DispatcherTimer, independent of $script:Busy / Set-Busy"
    - "Cards built from .NET objects with Text set as a property (no XAML string interpolation of spec values)"
    - "Numeric display via Fmt-Num with InvariantCulture; string sentinel passes through without a unit"

key-files:
  created: []
  modified:
    - Akari.ps1
    - UI/MainWindow.xaml

key-decisions:
  - "The Home panel is named HomePanel (not Home) because $HOME is a read-only AllScope automatic variable; Show-Page uses the flag $onHome"
  - "$script:SpecData is now the composite @{ Specs; Host } (D-18); a failed first read stores @{ Specs = New-FailedSpecs; Host = @{ Manufacturer/Model = 'Not available' } }"
  - "Sentinel headlines and values render in Mu (helpers check for 'Not available'), per UI-SPEC colour split"
  - "Loading state still renders a single CPU placeholder card; the other five loading cards and HostSub are plan 03-02"

patterns-established:
  - "Spec read never goes through Invoke-Code -ResultVar; the dormant Phase 2 harvest in the tweak block is untouched and has no caller"

requirements-completed: [SHELL-01, SHELL-02, SHELL-03, REFR-01]

coverage:
  - id: D1
    description: "App opens on Home, Home is the first sidebar item above a thin non-clickable divider, heading hidden, no empty-state message"
    requirement: "SHELL-01"
    verification: []
    human_judgment: true
    rationale: "The plan's headless verify commands could not be executed in this sandbox (every powershell.exe invocation was refused by the worktree isolation guard); verifier must run Task 1 verify #1 and #3"
  - id: D2
    description: "Six 240px cards in the dark theme wrap into the available columns (CPU, GPU, RAM, Disk, Board, Windows) with multi-instance dividers and invariant-culture numbers"
    requirement: "SHELL-02"
    verification: []
    human_judgment: true
    rationale: "Task 2 verify #1 (mocked six-card render) not executed in this sandbox; column fit at 820/1000 px is an end-of-phase UAT check"
  - id: D3
    description: "Header shows $env:COMPUTERNAME immediately; HostSub stays collapsed before the first read"
    requirement: "SHELL-03"
    verification: []
    human_judgment: true
    rationale: "Task 1 verify #1 not executed in this sandbox"
  - id: D4
    description: "Every Home show starts a background spec read off the UI thread, one-flight guarded and deferred while a tweak runs; the tick harvests it and re-renders only the cards"
    requirement: "REFR-01"
    verification: []
    human_judgment: true
    rationale: "Task 1 verify #1 (real tick harvest) and #3 (static busy-guard/Show-Page checks) not executed in this sandbox"

duration: 6min
completed: 2026-10-08
status: complete
---

# Phase 3 Plan 1: Home Shell, Live Read, Card Renderer Summary

**Home is now the default landing tab: a second runspace channel reads Get-Specs plus host identity on every Home show, the 150 ms tick harvests it ahead of the tweak job, and Update-Home renders six object-built 240px cards (CPU, GPU, RAM, Disk, Board, Windows) with invariant-culture numbers.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-10-08T19:54:18Z
- **Completed:** 2026-10-08T19:59:50Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- `UI/MainWindow.xaml`: `HomePanel` StackPanel (collapsed in markup) after `Heading`, holding `HomeHeader` DockPanel (`HostName` 22/SemiBold/Tx, `HostSub` 13/Mu collapsed) and the `Cards` WrapPanel. Only `Tx`/`Mu` referenced; no new brush or style.
- `Akari.ps1` state: `$script:Cat = 'Home'`, new `$script:SpecJob` and `$script:SpecPending`.
- `$HostIdentityFunc` (Get-HostIdentity: Win32_ComputerSystem maker/model through Test-SmbiosValue, `Not available` sentinel) and `$SpecReadCode` composite; `Get-Specs` is byte-for-byte unchanged.
- `Show-Page`: `$onHome` flag, HomePanel/Heading visibility flip, empty-state guard excludes Home, and `Update-Home; Start-SpecRead` at the end of the Home branch.
- Sidebar: `Home` first, followed by a 1px `Bd` Border with `IsHitTestVisible`/`Focusable` false; nav handler untouched.
- `Start-SpecRead`: one-flight guard, busy deferral via `SpecPending`, runspace + empty completed input collection (PS 5.1 BeginInvoke idiom), never touches the busy guard or the log.
- Tick: spec-completion block placed before `$j = $script:Job`; stores a hashtable with `Specs` key, otherwise logs exactly one `Specs: Read failed (...)` line with the contractual tail, installs the composite failed skeleton when no earlier data existed, disposes the job, then calls `Update-Home`. Tweak block now drains `SpecPending` after `Show-Page`.
- `Update-Home` full content map (Task 2): CPU (model, `Cores` partial rule, `Speed` MHz to GHz), GPU (block per adapter, VRAM/Driver, Status only when not OK, dividers between blocks, `Not available` headline when empty), RAM (total headline, Used/Free), Disk (drive + two-space label headline, Free/Total/File system, dividers), Board (maker + product with missing parts dropped), Windows (leading `Microsoft ` stripped for display, Version/Build).

## Task Commits

1. **Task 1 (tracer): launch lands on Home, background read, live CPU card** - `df495cc` (feat)
2. **Task 2: six-card content map with multi-instance blocks** - `cb0a303` (feat)

## Files Created/Modified

- `Akari.ps1` - Home state, composite read code, Start-SpecRead, tick spec harvest, sidebar Home item + divider, card helpers and Update-Home
- `UI/MainWindow.xaml` - static Home panel (header + card grid host)

## Decisions Made

See `key-decisions` in frontmatter. Notable: helpers colour a value or headline `Mu` when it is exactly `Not available`, implementing the UI-SPEC colour split already in this plan rather than deferring it.

## Deviations from Plan

### Verification not executed (environment)

**1. [unrun-verify] All five `<automated>` verify commands could not be run**
- **Found during:** Task 1 (precondition) and every verify step
- **Issue:** The worktree isolation guard refuses every `powershell.exe` invocation from the Bash tool ("this command runs powershell in a plain command ... Refusing to run it"), including a bare `powershell.exe -NoProfile -Command "Get-Location"`. No PowerShell tool is available to this agent, so neither the AST/XAML headless harness nor the Phase 2 six-group regression could be executed.
- **Mitigation:** The precondition was established by read-only inspection: `02-VERIFICATION.md` is `status: passed` and `Akari.ps1` had no commits after Phase 2's last fix (`c55c7a0`). The implementation was written against each acceptance criterion and the exact markers the static verify looks for (the `$sj = ` assignment ahead of `$j = `, no `Show-Page` in the spec region, no `Set-Busy`/`$script:Busy =` in `Start-SpecRead`, composite hashtable literal around `New-FailedSpecs`, `HomePanel` in the Set-Variable list and no bare `Home`, no `-ResultVar` call site). Grep checks that could be run passed: file is pure ASCII, no assignment to a `home` variable, no `$ErrorActionPreference`/`Set-StrictMode`, no `Invoke-Code ... -ResultVar` call site.
- **Tracer gate:** The tracer feedback gate (re-run verify before expansion) could not be evaluated; Task 2 proceeded on code review only. The verifier/orchestrator must run Task 1 verify #1-#3 and Task 2 verify #1-#2 from the main checkout.

### Auto-fixed Issues

None.

**Total deviations:** 1 environment limitation (verification unrun), 0 code deviations. **Impact:** the code follows the plan as written; correctness is unproven until the plan's verify commands are run.

## Issues Encountered

- PowerShell execution blocked in this agent's sandbox (see above).

## Known Stubs

- Loading state (`$script:SpecData -eq $null`) renders only the CPU placeholder card, and `HostSub` is never made visible. Both are intentional per this plan's Task 1 text and are completed by plan 03-02.

## Next Phase Readiness

- Ready for 03-02 (loading/failed/dimmed states for all six cards and the HostSub maker/model line). Phase 4 readers must use `$script:SpecData.Specs` / `.Host`.

## Self-Check: PASSED

- FOUND: Akari.ps1, UI/MainWindow.xaml (modified)
- FOUND: df495cc, cb0a303 in `git log` on this branch
- NOTE: plan verify commands unrun (environment), see Deviations
