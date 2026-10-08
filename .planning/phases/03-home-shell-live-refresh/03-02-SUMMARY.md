---
phase: 03-home-shell-live-refresh
plan: 02
subsystem: ui
tags: [powershell, wpf, home-page, spec-cards, refresh-states, smbios]

requires:
  - phase: 03-home-shell-live-refresh
    provides: "03-01 Home shell: $script:SpecData = @{ Specs; Host }, Start-SpecRead, tick spec harvest, Update-Home and card helpers"
provides:
  - "Dimming scope: only the Cards WrapPanel and HostSub fade to 0.6 while $script:SpecJob is in flight or $script:SpecPending is set; HostName never dims"
  - "First-load state: all six cards (CPU, GPU, RAM, Disk, Board, Windows) show the title and Loading (U+2026), HostSub collapsed"
  - "Failed-group look: Add-Headline takes a brush key; a Failed group headlines Not available in Mu and still lists its rows; zero-item GPU/Disk cards show only the headline"
  - "Set-HomeDim: fades earlier values once Start-SpecRead starts or defers a read, because Show-Page draws before the read starts"
  - "Home header: HostSub = Maker U+00B7 Model from Host, pair-level fallback to the motherboard pair when either value is filler (D-17), tooltip carries the full text, collapsed when nothing survives"
affects: [phase-04-copy-specs]

actuals:
  tokens: 1941
  tasks: 2
  commits: 2

plan_head_before: ef6614a68f87b51c741a7857b2c8737d654625be
plan_head_after: c6f000c82bb0773417a0a6819af6e944344afd13

tech-stack:
  added: []
  patterns:
    - "Visual read state derives only from $script:SpecJob / $script:SpecPending; no separate UI flag"
    - "Header identity resolved from the composite read in hand; no CIM on the UI thread"

key-files:
  created: []
  modified:
    - Akari.ps1

key-decisions:
  - "Add-Headline keeps the sentinel rule: text equal to Not available is always Mu, whatever brush key the caller passes; otherwise the brush key (default Tx) is used"
  - "A Failed multi-instance group that still has items (every field sentinel) headlines each block Not available in Mu; rows and dividers stay"
  - "Added Set-HomeDim, called from Start-SpecRead, because Show-Page renders before it starts the read: without it a normal Home re-show would never fade. It dims only when earlier data exists, so the first-load Loading cards stay at full opacity"
  - "The header fallback also treats a null or whitespace Host value as filler, not just the Not available sentinel"

patterns-established:
  - "Home opacity is recomputed on every Update-Home from read state, so the swap from dimmed to fresh happens in one synchronous pass"

requirements-completed: [SHELL-02, SHELL-03, REFR-01]

coverage:
  - id: D1
    description: "First Home show: six cards each show their title and Loading in Mu, HostSub hidden, full opacity"
    requirement: "SHELL-02"
    verification: []
    human_judgment: true
    rationale: "Task 1 verify #1 could not run in this sandbox (powershell.exe refused by the worktree isolation guard); the orchestrator must run it"
  - id: D2
    description: "While a read is in flight or waiting on a tweak, the cards and maker/model line fade, the computer name stays bright, nothing is cleared, and opacity returns to 1 when the read completes"
    requirement: "REFR-01"
    verification: []
    human_judgment: true
    rationale: "Task 1 verify #1 unrun (sandbox); the faded look during a live refresh is also an end-of-phase UAT check"
  - id: D3
    description: "Partial and Failed groups show Not available for missing fields; Failed headlines are muted; zero-item GPU/Disk cards show only the headline"
    requirement: "SHELL-02"
    verification: []
    human_judgment: true
    rationale: "Task 1 verify #1 unrun (sandbox)"
  - id: D4
    description: "A failed read never leaves a card on Loading: earlier values are kept, or the failed look is shown, with exactly one Specs: Read failed line; a successful read logs nothing"
    requirement: "REFR-01"
    verification: []
    human_judgment: true
    rationale: "Task 1 verify #2 (fabricated failing runspace through the real tick) unrun (sandbox)"
  - id: D5
    description: "Home header shows the computer name plus Maker U+00B7 Model, with the pair-level SMBIOS filler fallback to the motherboard pair, a single value alone, or the line hidden"
    requirement: "SHELL-03"
    verification: []
    human_judgment: true
    rationale: "Task 2 verify #1 (four header cases) and #2 (Phase 2 six-group regression) unrun (sandbox); the narrow-window ellipsis and tooltip are UAT checks"

duration: 8min
completed: 2026-10-08
status: complete
---

# Phase 3 Plan 2: Refresh States, Failure Handling, Host Header Summary

**Update-Home now renders every read state: six Loading cards on first show, a dimmed grid and maker/model line (never the computer name) while a read runs or waits out a tweak, muted Not available headlines for failed groups, and a Maker · Model header that falls back to the motherboard pair whenever either system value is SMBIOS filler.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-10-08T20:10:00Z
- **Completed:** 2026-10-08T20:18:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- `Update-Home` computes `$dim = ($null -ne $script:SpecJob -or $script:SpecPending)` right after clearing the grid and sets `Cards.Opacity` (0.6 or 1). `HostSub.Opacity` copies it. `HostName`, `Rows` and `Page` never dim.
- Loading branch builds all six cards in fixed order with `Add-Loading` and collapses `HostSub` (text and tooltip cleared).
- `Add-Headline($card, $text, $brushKey = 'Tx')`. Each card checks `_Status -eq 'Failed'` and headlines `Not available` in `Mu`. Rows still render through the existing path. GPU and Disk with zero items show only the headline.
- `Set-HomeDim` (new, called at both exits of `Start-SpecRead`) fades earlier values once a read starts or is deferred.
- Failure copy and the D-18 composite in the tick were confirmed verbatim, with no change needed: `Specs: Read failed ({msg}). Showing last known values.` / `... Switch to another page and back to Home to try again.`, and `@{ Specs = New-FailedSpecs; Host = @{ Manufacturer = 'Not available'; Model = 'Not available' } }`.
- Header block at the end of the data branch: reads `$d.Host`, falls back to `$d.Specs.Motherboard.Manufacturer/Product` per D-17, filters out the sentinel, and joins with `' ' + [char]0x00B7 + ' '`. The tooltip is set to the full text. When nothing survives, `HostSub` is collapsed.

## Task Commits

1. **Task 1: render every refresh state (Loading, dimmed re-read, partial and failed groups)**: `cd2a7a2` (feat)
2. **Task 2: resolve the friendly host header with SMBIOS-filler fallback**: `c6f000c` (feat)

## Files Created/Modified

- `Akari.ps1`: dimming scope, six-card loading state, failed-group headlines, `Set-HomeDim`, header maker/model resolution

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Normal Home re-show never dimmed**
- **Found during:** Task 1
- **Issue:** `Show-Page` calls `Update-Home; Start-SpecRead` in that order (03-01 contract). So `Update-Home` always sees `SpecJob = $null` on a normal re-show and draws at opacity 1. The read then starts with no redraw, which means the "faded while updating" state would never appear.
- **Fix:** Added `Set-HomeDim`, called from `Start-SpecRead` after the job starts and in the busy-defer branch. It sets both elements to 0.6 only when earlier data exists, so first-load Loading cards stay at full opacity as the plan's truths require. The Show-Page order is unchanged.
- **Files modified:** Akari.ps1
- **Committed in:** cd2a7a2

### Verification not executed (environment)

**2. [unrun-verify] All four `<automated>` verify commands could not be run**
- **Issue:** The worktree isolation guard refuses every `powershell.exe` invocation from Bash. Even `powershell.exe -NoProfile -Command "1+1"` was refused. This is the known limit the orchestrator flagged.
- **Mitigation:** I wrote the implementation against each acceptance criterion and traced each verify script by hand against the code:
  - six loading cards with U+2026
  - opacity 0.6/1 transitions for the job and pending states
  - `Children[0].Child.Children[1]` being the Mu `Not available` headline
  - the zero-item GPU card having exactly 2 children
  - the four header cases
  - the failing-runspace tick path, with one log line each time and keep-values with opacity restored

  Static checks that could run all passed: `Akari.ps1` is pure ASCII, `function Test-SmbiosValue` appears once, and there is no `Get-CimInstance` inside `Update-Home`. `Get-Specs` is untouched.
- **Action for orchestrator:** run Task 1 verify #1 and #2 and Task 2 verify #1 and #2 from the main checkout.

**Total deviations:** 1 auto-fixed (Rule 1), 1 environment limitation. **Impact:** the auto-fix is needed for the refreshing state to be visible. Correctness stays unproven until the verify commands run.

## Issues Encountered

- PowerShell execution was blocked in the agent sandbox (see above).

## Known Stubs

None. The 03-01 stubs (single CPU loading card, `HostSub` never visible) are resolved by this plan.

## User Setup Required

None.

## Next Phase Readiness

- Phase 3 plans complete pending orchestrator verification. Phase 4 readers use `$script:SpecData.Specs` / `.Host`. `Warn`/`Bad` remain unused on Home.

## Self-Check: PASSED

- FOUND: Akari.ps1 (modified)
- FOUND: cd2a7a2, c6f000c on this branch (`git rev-list --count ef6614a..HEAD` = 2)
- NOTE: plan verify commands unrun (environment), see Deviations

## Orchestrator Verification (post-merge)

The executor could not run PowerShell. After it returned, the orchestrator ran all four 03-02 `<automated>` verify commands, plus the five 03-01 commands as a regression, against the worktree with `powershell.exe -STA`. All 9 exited 0 with PASS.
