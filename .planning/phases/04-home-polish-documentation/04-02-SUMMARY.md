---
phase: 04-home-polish-documentation
plan: 02
subsystem: docs
tags: [readme, documentation, markdown]

requires: []
provides:
  - "README.md rewritten: project intro, Home page (live specs, Copy specs, health colours), 8 categories, apply/revert, requirements, IWR install, run-from-zip, safety, Credits"
affects: [04-01 (README describes the Copy specs label and 15%/10%, 80%/90% thresholds that plan implements)]

actuals:
  tokens: 950
  tasks: 1
  commits: 1
plan_head_before: b4abbad3898d9caccc7a4ef72458a9e9e315703d
plan_head_after: 3e3cf203eab1981a7377db119cd172145e1a9e61

tech-stack:
  added: []
  patterns: ["README sections use level-1 # headings, matching the original file"]

key-files:
  created: []
  modified: [README.md]

key-decisions:
  - "Category one-liners drawn from the real -Name values in Tweaks/*.ps1; Advanced line names the Win32PrioritySeparation and SvcHost split tuners"
  - "IWR sentence, code block and Credits section kept byte-identical to the previous README"

patterns-established: []

requirements-completed: [DOC-01]

coverage:
  - id: D1
    description: "README documents the project, Home page (live specs, Copy specs, amber/red health colours), 8 categories, apply/revert, requirements, IWR install, run-from-zip and safety, in 50 lines with no images and Credits verbatim"
    requirement: DOC-01
    verification:
      - kind: other
        ref: "Plan <automated> README checks replicated with grep/wc (PowerShell blocked by worktree sandbox): line count 50, exact IWR line, Credits last two non-empty lines, no image syntax, one list line per category, all D-13 terms present"
        status: pass
    human_judgment: true
    rationale: "Readability and 'fits about one screen' on GitHub need a human read; the Copy specs label and thresholds must also match what plan 04-01 ships"

duration: 6min
completed: 2026-10-09
status: complete
---

# Phase 4 Plan 2: README Rewrite Summary

**One-screen README (50 lines) covering what Akari is, the Home page with live specs, Copy specs and amber/red Disk/RAM colours, one line per tweak category, Optimize/Default with risk labels, both install routes and a safety note; IWR line and Credits unchanged.**

## Performance

- **Duration:** about 6 min
- **Completed:** 2026-10-09
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Rewrote `README.md` in the D-13 section order: AkariOS Ultimate, Home page, Categories, Apply and revert, Requirements, Install (IWR), Run from a downloaded zip, Safety, Credits.
- Home page section names the `Copy specs` button, clipboard copy, and the thresholds (Disk Free amber <15% / red <10%, RAM Used amber >80% / red >90%).
- Category lines are built from the actual tweak names in `Tweaks/*.ps1`.

## Task Commits

1. **Task 1: Rewrite README.md** - `3e3cf20` (docs)

## Files Created/Modified
- `README.md` - full rewrite (38 insertions, 5 deletions)

## Decisions Made
- Followed the plan's section wording. Category descriptions are a selection of each file's real tweak names, kept to one line each.

## Deviations from Plan

None in content. One verification note: the sandbox blocked `powershell.exe` from inside the worktree, so I could not run the plan's `<automated>` PowerShell command as written. I ran the same checks with `wc`/Grep instead (line count, exact IWR line, Credits last two non-empty lines, no `![`/`<img`, one `- **Category**` line for each of the 8, every required term, and the reboot/revert/amber/red/clipboard topics). All passed.

## Issues Encountered
- Git warned that README.md's LF line endings will be turned into CRLF by autocrlf. This doesn't change the content.

## User Setup Required

None.

## Next Phase Readiness
- The README assumes plan 04-01 ships the button label `Copy specs` and the 15%/10%, 80%/90% thresholds. Check this against the 04-01 SUMMARY after the merge.

## Self-Check: PASSED
- FOUND: README.md
- FOUND: 3e3cf20 (ancestor of HEAD)
