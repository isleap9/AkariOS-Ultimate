---
phase: 02-hardware-spec-cards
plan: 02
subsystem: data
tags: [powershell, cim, wmi, smbios, bios, disk, datetime, culture, gap-closure]
gap_closure: true

requires:
  - phase: 02-hardware-spec-cards
    provides: Get-Specs GPU/Disk/Motherboard groups (02-PLAN, commits ce4de3b..210bc5f)
provides:
  - Motherboard.ReleaseDate formatted from the UTC instant with InvariantCulture (CR-01 fix)
  - Disk FreeGB accepts a reported 0 (WR-01 fix)
  - Disk Label is descriptive ('' when unlabeled) and not counted toward Disk._Status (WR-02 fix)
affects: [03-home-shell, home-page, spec-cards]

actuals:
  tokens: 550
  tasks: 3
  commits: 3
plan_head_before: e6375d82c4c2e75efb9c5d361f65434e2075f6a7
plan_head_after: c55c7a069b57c7c965892bba3d747597bab8d4d4

tech-stack:
  added: []
  patterns:
    - "CIM DateTime values are formatted via ToUniversalTime() + InvariantCulture, never local time or current culture"
    - "Descriptive fields (Label) can be empty and are excluded from the _Status success count; only fallible fields are counted"

key-files:
  created: []
  modified:
    - Akari.ps1

key-decisions:
  - "BIOS ReleaseDate = ReleaseDate.ToUniversalTime().ToString('yyyy-MM-dd', InvariantCulture); SMBIOS dates are midnight UTC"
  - "FreeSpace = 0 is a valid reading (FreeGB 0, counted); only null FreeSpace is 'Not available'"
  - "Unlabeled volume Label is '' (not 'Not available'); Disk counts 4 fields per volume (Drive, FileSystem, TotalGB, FreeGB)"

patterns-established:
  - "Gap-closure edits stay inside the Get-Specs Disk and Motherboard/BIOS region; everything else byte-identical to 210bc5f (REGION_OK)"

requirements-completed: [SPEC-05, SPEC-04]

coverage:
  - id: D1
    description: "CR-01: BIOS ReleaseDate equals the firmware date in every timezone (UTC-5/-8/-10/+14, DST-ambiguous) and culture (en-US, th-TH, ar-SA); null date gives 'Not available' + Partial"
    requirement: "SPEC-05"
    verification:
      - kind: other
        ref: "grep -cF \"ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)\" Akari.ps1 -> 1; grep -cF 'ReleaseDate.ToString(' -> 0; comment grep -> 1"
        status: pass
      - kind: unit
        ref: "02-02-PLAN Task 1 <automated> #1 (mocked zone/culture matrix, expects 14 ok lines + PASS: CR-01)"
        status: unknown
      - kind: integration
        ref: "02-02-PLAN Task 1 <automated> #2 (live: groups + ReleaseDate == raw Get-WmiObject firmware yyyyMMdd)"
        status: unknown
    human_judgment: true
    rationale: "The powershell.exe harnesses could not be run inside this worktree-isolated executor (the isolation guard refuses every powershell.exe invocation). The orchestrator/verifier must run the Task 1 harnesses from the main checkout before marking SPEC-05."
  - id: D2
    description: "WR-01: a fixed volume with FreeSpace 0 reports FreeGB 0 (numeric, counted); null FreeSpace still 'Not available'"
    requirement: "SPEC-04"
    verification:
      - kind: other
        ref: "grep -cF 'if ($null -ne $disk.FreeSpace) { $vol.FreeGB = [math]::Round($disk.FreeSpace / 1GB, 1); $diskSuccess++ }' Akari.ps1 -> 1; 'FreeSpace -gt 0' -> 0; comment grep -> 1"
        status: pass
      - kind: unit
        ref: "02-02-PLAN Task 2 <automated> (mocked Win32_LogicalDisk, expects PASS: WR-01)"
        status: unknown
    human_judgment: true
    rationale: "Mocked harness unrun (same isolation-guard block); verifier must run Task 2 harness."
  - id: D3
    description: "WR-02: Label not counted; healthy unlabeled volumes give Disk._Status OK and Label ''; missing FileSystem still gives Partial; DriveType 2 excluded"
    requirement: "SPEC-04"
    verification:
      - kind: other
        ref: "Task 3 greps: diskFields = 4 -> 1, = 5 -> 0, \"Label = ''; FileSystem = 'Not available'\" -> 1, \"Label = 'Not available'\" -> 0, VolumeName line -> 1, 'VolumeName; $diskSuccess++' -> 0, comment -> 1"
        status: pass
      - kind: unit
        ref: "02-02-PLAN Task 3 <automated> #1 (mocked volumes, expects PASS: WR-02)"
        status: unknown
      - kind: integration
        ref: "02-02-PLAN Task 3 <automated> #2 (live, expects PASS live: ... Disk=OK)"
        status: unknown
    human_judgment: true
    rationale: "Mocked and live harnesses unrun (isolation-guard block); verifier must run both Task 3 commands."
  - id: D4
    description: "No regression outside the Disk..return region; only Akari.ps1 changed; Get-Specs path stays read-only"
    verification:
      - kind: other
        ref: "diff --strip-trailing-cr of sed-stripped 210bc5f:Akari.ps1 vs Akari.ps1 -> REGION_OK (base region 600 lines)"
        status: pass
      - kind: other
        ref: "git diff --name-only 210bc5f -- . ':!.planning' -> Akari.ps1"
        status: pass
      - kind: other
        ref: "sed -n '/^$GetSpecsFunc = @/,/^.@$/p' Akari.ps1 | grep -cE 'Set-ItemProperty|New-ItemProperty|Remove-Item|reg add|Set-TimeZone|tzutil|Set-Volume' -> 0"
        status: pass
    human_judgment: false

duration: 2min
completed: 2026-10-08
status: complete
---

# Phase 2 Plan 02: Spec Data Accuracy Gap Closure Summary

**The BIOS release date is now taken from the UTC instant and formatted with the invariant culture, so it matches the firmware date in every timezone and calendar. A full disk reports 0 GB free instead of "Not available", and an unlabeled volume no longer marks a healthy disk as Partial. This closes 02-VERIFICATION gap 1 (CR-01) plus review warnings WR-01 and WR-02.**

## Performance

- **Duration:** about 2 min
- **Started:** 2026-10-08T14:47:51Z
- **Completed:** 2026-10-08T14:49:51Z
- **Tasks:** 3/3
- **Files modified:** 1 (`Akari.ps1`)

## Accomplishments

- **CR-01 (BLOCKER, SPEC-05 / SC3):** `$biosDate = $bios.ReleaseDate.ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)`. The null guard, `$mbSuccess++` and the try/catch are unchanged.
- **WR-01 (SPEC-04):** `if ($null -ne $disk.FreeSpace) { ... }`. A reported 0 bytes now gives FreeGB 0 and counts as a successful read. A null FreeSpace still gives "Not available".
- **WR-02 (SPEC-04):** `$diskFields = 4`. The Label initializer is `''`, and the VolumeName line no longer increments `$diskSuccess`.
- Four lowercase intent comments were added (AGENTS.md style). No new functions, keys or files.

## Task Commits

| Finding | Task | Commit | Type |
|---|---|---|---|
| CR-01 | Task 1 (tracer): BIOS date in UTC + InvariantCulture | `fbb2bc1` | fix |
| WR-01 | Task 2: 0 bytes free = 0 GB | `cd79bf5` | fix |
| WR-02 | Task 3: Label not counted toward Disk status | `c55c7a0` | fix |

## Files Created/Modified

- `Akari.ps1`: edits inside the `$GetSpecsFunc` here-string, in the Get-Specs `# --- Disk ---` and `# --- Motherboard / BIOS ---` sections only

## Verification Results

Results that passed in this executor:

- Task 1 greps: `ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)` = 1, `ReleaseDate.ToString(` = 0, `# smbios date is midnight utc` = 1
- Task 2 greps: exact FreeSpace line = 1, `FreeSpace -gt 0` = 0, `# 0 bytes free is a real reading` = 1
- Task 3 greps: `diskFields = 4` = 1, `diskFields = 5` = 0, `Label = ''; FileSystem = 'Not available'` = 1, `Label = 'Not available'` = 0, the exact VolumeName line = 1, `VolumeName; $diskSuccess++` = 0, `# empty label is a valid reading, not a failed field` = 1. The exact `$vol = @{ ... }` initializer is also present (1)
- Region guard: `REGION_OK`, checked after each of the 3 tasks against `210bc5f` (600-line base region, so the check is not vacuous)
- Scope guard: `git diff --name-only 210bc5f -- . ':!.planning'` prints `Akari.ps1` only
- Read-only guard (verification step 4): `0`
- No file deletions in any commit, and no untracked files

**Not run: every `<automated>` powershell.exe harness** (CR-01 matrix, CR-01 live, WR-01, WR-02, WR-02 live). This executor ran in an isolated worktree, and its Bash guard refuses every `powershell.exe` invocation ("cannot be shown not to run git"), with both `-Command` and `-File`. I stopped after those two forms and did not look for a workaround. So I have **no PASS output lines** to record, and the fail-first steps (Steps 1 of each task) were not observed either. The precondition fact was confirmed read-only: `HKLM\SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine PowerShellVersion = 5.1.26100.8875`.

**Action for the orchestrator/verifier:** from Git Bash at the main-checkout repo root, after merging this worktree, run the five `<automated>` commands from 02-02-PLAN.md. Expected results: `PASS: CR-01` (14 `ok` lines), `PASS live: groups=CPU,Disk,GPU,Motherboard,RAM,Windows ...`, `PASS: WR-01`, `PASS: WR-02`, and `PASS live: ... Disk=OK ...`. Mark SPEC-04/SPEC-05 Complete in REQUIREMENTS.md only after they pass.

## Decisions Made

- I followed the plan's exact line texts. Label `''` is the chosen representation for an unlabeled volume, following the plan's Task 3 rationale and the 02-REVIEW WR-02 fix. It narrows 02-PLAN's "Not available, never empty" rule to counted fields only.

## Deviations from Plan

**1. [Rule 3 - Blocking] powershell.exe verification harnesses could not be executed in the isolated worktree**
- **Found during:** Task 1 (precondition and fail-first step)
- **Issue:** The worktree isolation guard rejects all `powershell.exe` commands, so the fail-first runs, the post-fix `<automated>` harnesses and the tracer feedback-gate re-run could not happen.
- **Fix:** Applied the exactly-specified edits. Verified them with every grep, region, scope and read-only acceptance criterion that does not need PowerShell. Recorded the harness results as `unknown` in `coverage`, with `human_judgment: true`. The tracer gate could not re-run `<verify>`. I continued to Tasks 2 and 3 because they edit a separate section (Disk) and do not depend on the Task 1 line. The orchestrator must run the harnesses after merge.
- **Files modified:** none beyond the plan
- **Commits:** fbb2bc1, cd79bf5, c55c7a0
- **Requirements:** I did not run `requirements.mark-complete`, so SPEC-04 and SPEC-05 are left for the orchestrator to mark after the harnesses pass. 02 already had to revert a premature Complete once.

**Total deviations:** 1 (verification environment blocker). **Impact:** the code changes match the plan character for character. Behavioural proof is pending a run from an unrestricted shell.

## Issues Encountered

- Composite `git ...` pipelines were also refused by the isolation guard, so the region diff was run in split steps. `git show 210bc5f:Akari.ps1` was written to the scratchpad and both sides were `sed`-stripped to files before `diff`. The result is equivalent to the plan's one-liner.

## Notes for Phase 3

- **Supersedes the 02-SUMMARY note** "Disk `_Status` is `Partial` whenever a volume has no label". An unlabeled volume now has `Label = ''` and does not affect `_Status`. Render the drive letter alone (for example "C:") when Label is `''`. Label is never `'Not available'`.
- `Disk.Volumes[].FreeGB` can be numeric `0` (a full disk). Do not treat a falsy 0 as missing; check for the string `'Not available'` instead.
- `Disk._Status` counts 4 fields per volume (Drive, FileSystem, TotalGB, FreeGB).
- `Motherboard.ReleaseDate` is always an invariant, Gregorian `yyyy-MM-dd` string equal to the firmware date, or `'Not available'`.
- WR-06 (ResultVar ignored), WR-07 (refresh dropped while busy; Read-Svc/Show-Page on completion; refresh-loop risk), WR-08 (BeginInvoke failure leaves Busy stuck) and IN-03 (SpecData not type-checked) all still need handling before refresh-on-show is wired (REFR-01).

## Deferred (no phase assigned)

- WR-03: index-based VRAM registry fallback
- WR-04: registry VRAM used only for sentinel AdapterRAM values
- WR-05: virtual/basic display adapters listed and counted
- IN-01: unreachable `-ge 4GB` clause on a uint32
- IN-02: incomplete SMBIOS filler list; make `-icontains` explicit

## User Setup Required

None. No external service configuration is required.

## Next Phase Readiness

- The code for CR-01, WR-01 and WR-02 is in place. Phase 2 gap 1 can close once the orchestrator's harness run shows PASS for all five commands.
- The end-of-phase human check from 02-VERIFICATION (launch the elevated app, run a Toggle tweak and the Advanced tuners) is still pending and unchanged. This plan does not touch Invoke-Code or the tick.

## Self-Check: PASSED

- FOUND: Akari.ps1
- FOUND: fbb2bc1, cd79bf5, c55c7a0 (ancestors of HEAD)
- commits measured: 3 (`git rev-list --count e6375d8..HEAD` before the SUMMARY commit)
- No stubs introduced (Label `''` is an intentional empty-value reading, documented above)
