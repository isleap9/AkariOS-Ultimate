---
phase: 04-home-polish-documentation
plan: 03
subsystem: ui
tags: [powershell, wpf, runspace, cim, watchdog, home-page]

requires:
  - phase: 04-home-polish-documentation
    provides: Get-HomeModel shared card model, Get-SpecText copy text, Copied revert line in the 150 ms tick (plan 04-01)
  - phase: 03-home-shell-live-refresh
    provides: Start-SpecRead one-flight spec read, spec-completion block of the tick, failure branch with keep-values / switch-page copy
provides:
  - Spec-read watchdog (Deadline from $script:SpecTimeoutSec = 20) that abandons a hung read via the non-blocking BeginStop and undims Home with one log line
  - Deferred disposal of abandoned reads ($script:SpecStale) inside the existing tick
  - -OperationTimeoutSec 10 on all eight spec-read CIM calls
  - Single-writer $script:SpecData (Invoke-Code result-variable path removed)
  - Multi-socket CPU totals plus CPU.Sockets field and a conditional Sockets row
affects: [home-page, verify-work, readme]

actuals:
  tokens: 3392
  tasks: 2
  commits: 2
plan_head_before: d1c6143e02509a884f203451b9091b1cfecd43b2
plan_head_after: 23e836cbb1b0326744a85f2f8509fb796f40717e

tech-stack:
  added: []
  patterns:
    - "Watchdog in the existing tick: a job hashtable carries a Deadline; past it the tick calls only BeginStop, parks the job in a stale list and frees the slot, and a later tick disposes it once Handle.IsCompleted"
    - "Descriptive spec fields (Sockets, Label) never count toward a group's _Status"

key-files:
  created: []
  modified:
    - Akari.ps1

key-decisions:
  - "Spec read timeout is 20 seconds ($script:SpecTimeoutSec), about ten times a normal 1.1-1.7 s read; each CIM call is bounded at 10 seconds so one hung class fails only its own group"
  - "A timed-out read reuses the existing failure branch (msg = 'timed out after 20 seconds'), so the log copy and the first-load failed composite are unchanged"
  - "WR-02 closed by deleting the Invoke-Code result-variable path entirely (reviewer option 1) rather than guarding it; the spec read keeps its own channel"
  - "Sockets row is shown only when Sockets is a number greater than 1, so single-socket and failed reads look exactly as before"

patterns-established:
  - "Never call EndInvoke, Stop or Dispose on a pipeline that may still be running from the UI thread; use BeginStop and dispose later from the tick"

requirements-completed: [SPEC-07, SPEC-08]

coverage:
  - id: D1
    description: "A spec read still running 20 seconds after it started is abandoned without blocking the window: Home undims with the last values (or Not available on a first load), one 'Specs: Read failed (timed out after 20 seconds).' log line, and the hung pipeline is disposed later"
    requirement: SPEC-07
    verification:
      - kind: automated_ui
        ref: "04-03-PLAN.md Task 1 <verify> command 1 (hung-read harness: uninterruptible 6 s sleep, real tick)"
        status: pass
      - kind: automated_ui
        ref: "04-03-PLAN.md Task 1 <verify> commands 2-4 (Phase 3 failure path, live tracer, static guard)"
        status: pass
    human_judgment: true
    rationale: "A real hung WMI provider cannot be produced on demand; the plan's human check (Home keeps refreshing and never stays faded) is end-of-phase UAT"
  - id: D2
    description: "Only the spec read can write the Home data: Invoke-Code takes code, label, meta, and the tweak-completion block no longer reads an output collection"
    requirement: SPEC-07
    verification:
      - kind: other
        ref: "04-03-PLAN.md Task 2 <verify> command 1 (AST checks on Invoke-Code params, ResultVar absence, SpecData assignment locations)"
        status: pass
    human_judgment: true
    rationale: "The plan's human check confirms tweak runs still show their messages and Done line in the real app"
  - id: D3
    description: "CPU card and copied text sum cores and threads across every socket and show a Sockets row/line only on multi-socket machines; New-FailedSpecs CPU carries Sockets = Not available; six-group contract unchanged"
    requirement: SPEC-07
    verification:
      - kind: automated_ui
        ref: "04-03-PLAN.md Task 2 <verify> command 1 (mocked two-socket Xeon read through real Get-Specs, Update-Home, Get-SpecText)"
        status: pass
      - kind: integration
        ref: "04-03-PLAN.md Task 2 <verify> command 4 (live six-group read)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Copy specs button and Disk/RAM health colours from plan 04-01 keep working unchanged"
    requirement: SPEC-08
    verification:
      - kind: automated_ui
        ref: "04-01-PLAN.md all eight <automated> commands, re-run after both 04-03 tasks"
        status: pass
    human_judgment: false

duration: 6min
completed: 2026-10-09
status: complete
---

# Phase 4 Plan 03: Close the Phase 3 Review Findings (WR-01, WR-02, WR-03) Summary

**Fixes for the three Phase 3 review warnings. If a spec read hangs, it is now abandoned after 20 seconds, and the window never blocks while that happens. Each CIM call also has its own 10-second limit. The dormant tweak-result harvest is removed, so only the spec read can write the Home data. The CPU card and the copied text now add up cores and threads across every socket.**

## Performance

- **Duration:** about 6 min
- **Started:** 2026-10-09T09:36Z
- **Completed:** 2026-10-09T09:42Z
- **Tasks:** 2 of 2
- **Files modified:** 1

## Accomplishments

- **WR-01:**
  - All eight `Get-CimInstance` calls in `$GetSpecsFunc` and `$HostIdentityFunc` carry `-OperationTimeoutSec 10`. The `Win32_Service` helper call and `Get-RamKB` are untouched.
  - New state: `$script:SpecTimeoutSec = 20` and `$script:SpecStale`. `Start-SpecRead` stamps each read with a `Deadline`.
  - The tick computes `$late`. A late read gets `BeginStop` only, is parked in `$script:SpecStale` and frees the slot. It then goes through the unchanged failure branch, which writes the contract line and installs the composite on a first load, followed by `Update-Home`.
  - A backwards loop placed before the tweak block disposes parked reads once their handle completes.
- **WR-02:** `Invoke-Code([string]$code, [string]$label, $meta = $null)` now has only the plain path. The tweak-completion `try` is now `try { [void]$j.Ps.EndInvoke($j.Handle) } catch { Add-Log ... }`, and every other line of that block is unchanged.
- **WR-03:**
  - `Get-Specs` reads `@(Win32_Processor)` and sums `NumberOfCores` / `NumberOfLogicalProcessors` with `Measure-Object`. Model and clock still come from the first socket. The cores fallback and the four status fields are as before.
  - It writes `CPU.Sockets`. `New-FailedSpecs` sets CPU `Sockets = 'Not available'`.
  - `Get-HomeModel` adds a `Sockets` row only when Sockets is a number above 1. The card and `Get-SpecText` both pick it up through the model.

## Task Commits

1. **Task 1: WR-01 hung spec read watchdog and per-call CIM timeouts** - `a0750ed` (fix)
2. **Task 2: WR-02 result-harvest removal and WR-03 multi-socket CPU totals** - `23e836c` (fix)

## Files Created/Modified

- `Akari.ps1`: watchdog state, the `Start-SpecRead` Deadline, the tick watchdog and stale disposal, CIM timeouts, the simplified `Invoke-Code` and tweak-completion block, the multi-socket CPU block, `New-FailedSpecs` Sockets, and the `Get-HomeModel` Sockets row.

## Verification Results (run on this host, real powershell.exe)

| Command | Result |
|---------|--------|
| 04-03 Task 1 v1: hung-read harness (6 s uninterruptible sleep, real tick) | PASS |
| 04-03 Task 1 v2: failure path through the tick | PASS |
| 04-03 Task 1 v3: live end-to-end Home tracer | PASS |
| 04-03 Task 1 v4: static guards (busy guard, no Show-Page in spec region, composite, HOME, no -ResultVar) | PASS |
| 04-03 Task 2 v1: AST D-17 checks + mocked two-socket read + card/copy text | PASS |
| 04-03 Task 2 v2: 04-01 Copy specs command (STA) | PASS |
| 04-03 Task 2 v3: Phase 3 six-card content map | PASS |
| 04-03 Task 2 v4: live six-group read | PASS |
| 04-01 all eight `<automated>` commands (regression) | PASS (8/8) |

RED evidence: before any edit, Task 1 v1 failed with `FAIL: a spec-read CIM call has no per-call timeout`. Task 2 v1 failed with `FAIL: Invoke-Code parameters are [code,label,meta,ResultVar], expected [code,label,meta] (D-17)`. Both tasks are `tdd="true"`, but there is no in-repo test framework. The plan's embedded verify commands are the tests, so there is no separate test commit.

## Decisions Made

- I kept the 20-second timeout and the 10-second per-call limit exactly as the plan specified, and recorded both as flagged assumptions. Neither has been observed against a real hung provider.
- A timeout reuses the existing failure branch rather than adding a new log line. The log copy stays the contractual `Specs: Read failed (...)` line with the existing tail.

## Deviations from Plan

None. The plan was executed as written. The CPU card change went into `Get-HomeModel`, as both the plan and the 04-01 handoff specified.

## Issues Encountered

- The harness for the live tracer (04-01 v4 / 04-03 Task 1 v3) prints the composite Host/Specs hashtable to stdout before PASS. It dot-sources `$SpecReadCode`, which emits the read result. This is harness noise, not a failure, and it predates this plan.
- `Akari.ps1` is LF in the working copy and `core.autocrlf=true`, so git prints a CRLF warning on commit. This predates this plan, and the endings were not changed.

## Known Stubs

None.

## User Setup Required

None. No external service configuration is required.

## Next Phase Readiness

- WR-01, WR-02 and WR-03 from `03-REVIEW.md` are closed in code. End-of-phase UAT human checks:
  - Home refreshes and never stays faded.
  - The CPU card looks unchanged on this single-socket PC, with no Sockets line.
  - Tweaks still show their messages and a Done line.
- Not testable here: a real hung WMI provider, and a dual-socket machine (only a mocked one was tested).

---
*Phase: 04-home-polish-documentation*
*Completed: 2026-10-09*

## Self-Check: PASSED

- FOUND: Akari.ps1 (modified)
- FOUND: a0750ed, 23e836c on HEAD
- All 16 automated commands re-run after the final commit: PASS
