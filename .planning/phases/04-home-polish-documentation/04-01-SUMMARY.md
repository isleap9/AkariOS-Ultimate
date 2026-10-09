---
phase: 04-home-polish-documentation
plan: 01
subsystem: ui
tags: [powershell, wpf, clipboard, home-page, health-colours]

requires:
  - phase: 03-home-shell-live-refresh
    provides: Update-Home card renderer, $script:SpecData Specs/Host composite, HomeHeader DockPanel with a reserved right side, 150 ms DispatcherTimer tick
provides:
  - Copy specs button (CopySpecs) on the Home header that copies a plain CRLF spec sheet to the clipboard
  - Get-HomeModel card model shared by the card renderer and the copy text
  - Get-HostLine header maker / model resolver
  - Get-DiskHealth / Get-RamHealth threshold functions and the Disk Free / RAM Used value colouring
affects: [04-home-polish-documentation, home-page, readme]

actuals:
  tokens: 4215
  tasks: 2
  commits: 2
plan_head_before: b4abbad3898d9caccc7a4ef72458a9e9e315703d
plan_head_after: 3e95ed614f286027dd9440beddcbae0632d24cb9

tech-stack:
  added: []
  patterns:
    - "Card model: Get-HomeModel returns @{ Title; Blocks = @(@{ Head; Rows = @(@{ Label; Value; Key }) }); Inline } descriptors; every Home consumer reads it instead of $script:SpecData directly"
    - "Transient button feedback reverts through the existing 150 ms tick keyed on a script-scope deadline ($script:CopiedUntil), no second timer"

key-files:
  created: []
  modified:
    - Akari.ps1
    - UI/MainWindow.xaml

key-decisions:
  - "Health colour is suppressed (Tx) when the RAM or Disk group status is Failed, in addition to the plan's sentinel / null / zero-total guard, so a failed read can never colour a value (D-12)"
  - "Every model Head and row Value is cast to [string] at build time, so the copy text and the card TextBlocks render the identical string"

patterns-established:
  - "Get-HomeModel is the single source for Home card content; add or change card rows there, never in Update-Home or Get-SpecText"

requirements-completed: [SPEC-07, SPEC-08]

coverage:
  - id: D1
    description: "Copy specs button on the right of the Home header, disabled until the first read, copies the approved plain spec sheet (computer name, maker / model, blank line, CPU GPU RAM Disk Board Windows) to the clipboard and shows Copied for about 2 seconds with no log line"
    requirement: SPEC-07
    verification:
      - kind: automated_ui
        ref: "04-01-PLAN.md Task 1 <verify> command 1 (Copy specs tracer harness)"
        status: unknown
    human_judgment: true
    rationale: "The automated harness could not be run in the executor worktree (PowerShell launch refused by the worktree isolation guard); the orchestrator must run it after merge, and the paste-into-Notepad check is a human UAT item by plan design"
  - id: D2
    description: "Home card grid renders exactly as Phase 3 left it after the refactor onto the shared card model (six cards, order, rows, dividers, header fallback, loading / dimmed / failed states)"
    requirement: SPEC-07
    verification:
      - kind: automated_ui
        ref: "04-01-PLAN.md Task 1 <verify> commands 2-4 and Task 2 <verify> commands 2-4 (Phase 3 regression harnesses)"
        status: unknown
    human_judgment: true
    rationale: "Regression harnesses not executed in the worktree (PowerShell launch refused); verifier must run them post-merge"
  - id: D3
    description: "Disk Free turns amber below 15% free and red below 10% free; RAM Used turns amber above 80% used and red above 90% used; healthy, unread and failed values stay neutral"
    requirement: SPEC-08
    verification:
      - kind: automated_ui
        ref: "04-01-PLAN.md Task 2 <verify> command 1 (24 threshold cases + rendered brush checks)"
        status: unknown
    human_judgment: true
    rationale: "Threshold harness not executed in the worktree (PowerShell launch refused); the colour change under real memory pressure is a human UAT item by plan design"

duration: 25min
completed: 2026-10-09
status: complete
---

# Phase 4 Plan 01: Copy Specs Button and Health Colours Summary

**A Copy specs button on the Home header copies a plain CRLF spec sheet to the clipboard. The text is built from a new shared card model (Get-HomeModel), and the cards draw from the same model. Disk Free and RAM Used turn amber or red at the 15/10% free and 80/90% used thresholds.**

## Performance

- **Duration:** about 25 min
- **Started:** 2026-10-09
- **Completed:** 2026-10-09
- **Tasks:** 2 of 2
- **Files modified:** 2

## Accomplishments

- `UI/MainWindow.xaml`: the `CopySpecs` Button (Btn style, `DockPanel.Dock="Right"`, `IsEnabled="False"`) sits in the reserved right side of `HomeHeader`. The host-name StackPanel is still the last child, so it still fills the header width. No new resource key was added; the count is still 15.
- `Get-HomeModel` builds the six card descriptors from `$script:SpecData.Specs`. The six per-card blocks moved out of `Update-Home` with every rule kept: the CPU cores partial rule, one GPU block per adapter with the Status row only when not OK, the system drive only on the Disk card, the Board sentinel filter and the stripped Windows edition. `Update-Home` now only draws from this model.
- `Get-HostLine` holds the header maker / model resolution (D-17 pair fallback, middle dot built from `[char]0x00B7`). The header and the copy text both call it.
- `Get-SpecText` writes the spec sheet: computer name, maker line (left out when empty), a blank line, then `Title: Head` lines. Other rows go on their own lines as `  Label: Value`. The RAM card is the single line `RAM: total (Used x, Free y)`. Lines are joined with CRLF and there is no trailing line break.
- `Copy-Specs` calls `[Windows.Clipboard]::SetText` inside try/catch and sets the label to `Copied`, or `Copy failed` when another program holds the clipboard. It sets `$script:CopiedUntil` 2 seconds ahead. It writes no log line, starts no read and does not touch the busy guard.
- The existing 150 ms tick puts the label back to `Copy specs` once the deadline passes.
- `Add-Row` takes an optional `$brushKey`; a `Not available` value always stays Mu.
- `Get-DiskHealth` / `Get-RamHealth` are pure threshold functions with strict comparisons, and the percentage is computed multiply-first. They return `Tx` for null, string-sentinel or zero-total inputs. Only the Disk `Free` row and the RAM `Used` row carry a key.

## Task Commits

1. **Task 1: Copy specs end to end through one shared card model** - `03d9f21` (feat)
2. **Task 2: Disk Free / RAM Used amber and red thresholds** - `3e95ed6` (feat)

## Files Created/Modified

- `Akari.ps1`: adds the `$script:CopiedUntil` state, the `CopySpecs` shortcut binding, `Get-DiskHealth`, `Get-RamHealth`, `Get-HomeModel`, `Get-HostLine`, `Get-SpecText`, `Copy-Specs`, the `Add-Row` brush key, `Update-Home` rendering from the model, the `$CopySpecs.Add_Click` wiring and the tick revert line.
- `UI/MainWindow.xaml`: adds the `CopySpecs` button in `HomeHeader`.

## Decisions Made

- Health colouring is also suppressed when the RAM or Disk group `_Status` is `Failed`. The plan's guard already covers the real failed skeleton, which carries sentinel strings and no volumes. The extra check makes D-12 ("the whole read failed") hold even for a malformed failed group that carries numbers.
- Model values are cast to `[string]` once, at build time, so the renderer and the copy text cannot format a value differently.
- Locals in the new functions avoid names that clash with the case-insensitive global UI shortcuts (`$Cards`, `$Rows`, `$Log`). The model uses `$model`, `$rl` and `$bl` instead.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Failed-group guard on the two health keys**
- **Found during:** Task 2
- **Issue:** The plan set the key straight from `Get-DiskHealth` / `Get-RamHealth`. A failed group that still carried numbers would have been coloured, which goes against D-12.
- **Fix:** The key is `'Tx'` when the group `_Status` is `Failed`; otherwise it comes from the health function.
- **Files modified:** Akari.ps1
- **Committed in:** 3e95ed6

**2. [Rule 2 - Missing Critical] Empty brush key falls back to Tx in Add-Row**
- **Found during:** Task 1
- **Issue:** `FindResource('')` throws if a caller ever passes an empty key.
- **Fix:** `if (-not $brushKey) { $brushKey = 'Tx' }` at the top of `Add-Row`.
- **Files modified:** Akari.ps1
- **Committed in:** 03d9f21

**Total deviations:** 2 auto-fixed (both Rule 2, defensive)
**Impact on plan:** None on behaviour for any input in the plan's fixtures; no scope creep.

## Issues Encountered

**None of the plan's automated verify commands ran in this worktree.** The worktree isolation guard refuses every `powershell.exe` invocation from the Bash tool ("runs powershell in a plain command; ... cannot be shown not to run git"). That covers the eight `<automated>` commands, the Phase 3 regression harnesses and the Task 1 tracer re-run.

What I checked instead, by hand and with bash:
- `Akari.ps1` has 0 non-ASCII bytes (`grep -P '[^\x00-\x7F]'`).
- Braces and parentheses balance (468/468 and 600/600 after Task 1).
- `UI/MainWindow.xaml` still has 15 `x:Key` entries.
- None of `Get-HomeModel`, `Get-HostLine`, `Get-SpecText` or `Copy-Specs` contains `Invoke-Code`, `Get-CimInstance`, `Start-SpecRead` or `Add-Log`.
- I traced every fixture in the eight harnesses through the new code by hand: the 24-line expected sheet, the failed composite, the four header cases and all 24 threshold boundary cases.

**The orchestrator must run all eight `<automated>` commands from 04-01-PLAN.md against the merged tree before marking SPEC-07 / SPEC-08 verified.** The tracer feedback gate was not run, for the same reason. Task 2 is marked `tdd="true"`, but there is no in-repo test framework, and its tests are the plan's embedded verify command, so there is no separate RED commit.

## Known Stubs

None.

## User Setup Required

None. No external service configuration is required.

## Next Phase Readiness

- Ready for the other Phase 4 plans (README, WR-01/02/03 fixes). Any plan that touches `Update-Home` or the CPU card must now edit `Get-HomeModel`, because the card content no longer lives in `Update-Home`.
- Blocker for verification: run the plan's automated commands post-merge (see Issues Encountered).

---
*Phase: 04-home-polish-documentation*
*Completed: 2026-10-09*

## Self-Check: PASSED

- FOUND: Akari.ps1 (modified), UI/MainWindow.xaml (modified)
- FOUND: 03d9f21, 3e95ed6 on HEAD
- NOTE: the plan's automated verify commands were not executed (environment refusal; see Issues Encountered)
