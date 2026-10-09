---
phase: 02-hardware-spec-cards
verified: 2026-10-08T15:01:48Z
status: passed
score: 23/23 must-haves verified
covered_files:
  - .planning/phases/02-hardware-spec-cards/02-02-PLAN.md
  - .planning/phases/02-hardware-spec-cards/02-02-SUMMARY.md
  - .planning/phases/02-hardware-spec-cards/02-PLAN.md
  - .planning/phases/02-hardware-spec-cards/02-SUMMARY.md
  - Akari.ps1
covered_digest: "v3:sha256:823fe372bd3c99a0c48047461c8f42ef7be873c9bdb1ad48459b53ad0e9bef11"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 13/14
  gaps_closed:
    - "User sees motherboard manufacturer/product, BIOS version, and release date (ROADMAP SC3 / SPEC-05): the BIOS ReleaseDate now equals the firmware date in every timezone and culture (CR-01)"
    - "Recommended in the same pass: WR-01 (a reported 0 bytes free gives FreeGB 0) and WR-02 (Label no longer counts toward Disk._Status)"
  gaps_remaining: []
  regressions: []
deferred:
  - truth: "User-visible rendering of the GPU, Disk and Motherboard/BIOS cards ('User sees ... card' in SPEC-03/04/05 and ROADMAP SC1-3)"
    addressed_in: "Phase 3"
    evidence: "Phase 3 goal: 'Home as default landing with card grid, live refresh, and navigation'; SC2: 'User sees specs arranged in a fluid card grid matching the existing dark theme'. $GetSpecsFunc still has no caller in Akari.ps1, so no card is drawn yet."
  - truth: "Spec refresh lifecycle concerns on the Invoke-Code -ResultVar path (WR-06 ResultVar ignored, WR-07 refresh dropped while busy plus Read-Svc/Show-Page on completion, WR-08 BeginInvoke failure leaves Busy stuck, IN-03 SpecData not type-checked)"
    addressed_in: "Phase 3"
    evidence: "Phase 3 SC4: 'User sees freshly queried specs every time Home is shown without UI blocking' (REFR-01)"
advisory:
  - finding: "WR-09: Windows _Status can report OK when Edition failed, because the UBR refinement counts as a second Build success (Akari.ps1 Windows section, lines ~193-214)"
    category: other
    reason: "Found in the 02-02 re-review in Phase 1 code (commit 3b68df1). Phase 2 did not touch this code (REGION_OK vs 210bc5f). It belongs to Phase 1 SC4 / REFR-02 status semantics. Fix: stop incrementing $winSuccess for UBR."
    evidence_status: "none provided (no reproduction on this host; the code-reading argument is sound)"
  - finding: "IN-04: CPU Cores silently falls back to the logical-processor count (Phase 1 code)"
    category: other
    reason: "Phase 1 code, outside Phase 2 scope. Info severity."
    evidence_status: "none provided"
human_verification:
  - test: "Prohibition [SPEC-05] (judgment-tier, flagged unverified-prohibition): confirm that showing the BIOS date as ReleaseDate.ToUniversalTime() formatted with InvariantCulture never presents a date that differs from the firmware's date"
    expected: "Accept the evidence: the 14-line zone/culture/DST/null matrix passes; a real Get-CimInstance Win32_BIOS read under swapped Eastern, Hawaiian and Line Islands zones with en-US, th-TH and ar-SA cultures returns 2026-08-18 every time; the live value equals the raw DMTF firmware string 20260818000000.000000+000. Verifier verdict (non-authoritative): HOLDS."
    why_human: "The prohibition is judgment-tier, with no wired enforcement test. Interactive mode needs an explicit human resolution."
  - test: "Prohibition [SPEC-04] (judgment-tier, flagged unverified-prohibition): confirm that disk values Windows reports are never shown as failed, and free space is never invented"
    expected: "Accept the evidence: FreeSpace 0 gives FreeGB 0 (numeric, counted); FreeSpace null gives 'Not available'; an unlabeled volume gives Label '' and does not affect _Status; live Disk=OK with an unlabeled C:. Verifier verdict (non-authoritative): HOLDS. One residual edge to decide on: a volume with Size = 0 still shows TotalGB 'Not available' and Partial (the plan intends this; a 0-byte volume is not a real reading)."
    why_human: "The prohibition is judgment-tier, with no wired enforcement test. Interactive mode needs an explicit human resolution."
  - test: "Prohibition [SPEC-04/SPEC-05] (judgment-tier, flagged unverified-prohibition): confirm that the Get-Specs path is read-only"
    expected: "Accept the evidence: the $GetSpecsFunc here-string contains only Get-CimInstance, Get-ItemProperty and Get-ChildItem reads. The write-pattern grep (Set-ItemProperty, New-ItemProperty, Remove-Item, reg add, Set-TimeZone, tzutil, Set-Volume) returns 0. The harness timezone swap is an in-process reflection change to the TimeZoneInfo cache, with no system timezone write. Verifier verdict (non-authoritative): HOLDS."
    why_human: "The prohibition is judgment-tier, with no wired enforcement test. Interactive mode needs an explicit human resolution."
  - test: "End-of-phase smoke test (carried forward from the previous verification): launch powershell -ExecutionPolicy Bypass -File Akari.ps1 elevated, click through categories, run one Toggle tweak (Optimize, then Default) and the Advanced-page Read/Apply tuners"
    expected: "Window opens with no error box; rows, Set-Prio and Set-Svc behave as before; 'Done: ...' is logged and the page re-enables after each run"
    why_human: "Risk is now low. Commit 210bc5f edits only the -ResultVar branches of Invoke-Code and the tick, and no caller in Akari.ps1 uses -ResultVar. A non-UI simulation of the real Invoke-Code plus the real tick body on the non-result path (the one tweaks use) passed: log lines, 'Done: ...', Busy reset and toggle state were all correct. The elevated WPF window itself still cannot be launched by the verifier."
---

# Phase 2: Hardware Spec Cards Verification Report

**Phase Goal:** GPU, disk, and motherboard/BIOS cards with hardware-diversity handling
**Verified:** 2026-10-08T15:01:48Z
**Status:** human_needed
**Re-verification:** Yes, after gap-closure plan 02-02 (previous: gaps_found, 13/14)

> **Harness repair (2026-10-09, quick task 261009-mt3):** Cause: Phase 4-03 (`a0750ed`) added `-OperationTimeoutSec 10` to every spec CIM call in Akari.ps1, and the 02-02 `Get-CimInstance` mocks declared only `-ClassName`, so they rejected that parameter. Get-Specs swallowed the error in its per-field try/catch, so the harnesses at `02-02-PLAN.md:132,174,216` silently read zero data and failed (milestone audit C-1). Fix: the mock in all three harnesses now also declares `-OperationTimeoutSec` and `-Filter` (the 04-03-PLAN.md mock shape, still under `[CmdletBinding()]` with no catch-all parameter). The assertions are unchanged, and Akari.ps1 was not touched. Re-run on 2026-10-09, all five 02-02 harnesses green: `PASS: CR-01` (14 ok lines), `PASS live: groups=CPU,Disk,GPU,Motherboard,RAM,Windows ReleaseDate=2026-08-18 ...`, `PASS: WR-01`, `PASS: WR-02`, `PASS live: groups=CPU,Disk,GPU,Motherboard,RAM,Windows ... Disk=OK volumes=4 ...`. The harness evidence behind this report's `passed` status is reproducible again. Caveat: this note does not refresh the covered-input fingerprint. It is stale because Phases 3-4 edited Akari.ps1, and only a verifier re-run (`/gsd-execute-phase 02`) regenerates it.

> **MVP-mode note (carried forward):** ROADMAP marks Phase 2 `Mode: mvp`, but the goal is not a user story. As in the initial verification, this report uses standard goal-backward verification against the four ROADMAP success criteria plus the PLAN must_haves. There is no User Flow Coverage table. To make the mode consistent, run `/gsd-mvp-phase 2` or remove `mode: mvp`.

## Summary of the re-verification

I re-checked everything and did not rely on the SUMMARY or the orchestrator's run:

- **The previously failed truth (SC3 / CR-01) is closed.** `Akari.ps1:345` now reads `$bios.ReleaseDate.ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)`.
  - I ran all five 02-02 `<automated>` harnesses myself on HEAD (`f1394d8`); all printed PASS.
  - I ran the four discriminating harnesses on the pre-fix file (`e6375d8`); all FAILED. Example: Line Islands with th-TH gave `2569-08-18`, and Hawaiian with ar-SA gave `1448-03-04`.
  - The harness builds its mock date with `ToLocalTime()`. To rule out a fixture-only result, I also ran an independent check that uses the real CIM path with no mock. `Get-CimInstance Win32_BIOS` under swapped Eastern, Hawaiian and Line Islands zones returns a Kind=Local value (for example `2026-08-17T20:00-04:00`), and Get-Specs reports `2026-08-18` in all 9 zone and culture combinations.
- **WR-01 and WR-02 are fixed:** `PASS: WR-01`, `PASS: WR-02`, and a live run with `Disk=OK volumes=4` on a host with an unlabeled `C:`.
- **No regressions.**
  - Outside the Disk and BIOS sections (from `# --- Disk ---` through `return $result`), the file is byte-identical to `210bc5f` (`REGION_OK`, 600-line base).
  - Only `Akari.ps1` changed outside `.planning/`.
  - GPU, SMBIOS filter and six-group regression checks pass live.
- **Why the status is `human_needed` and not `passed`:** 02-02 declares three judgment-tier prohibitions. In interactive mode (`auto_advance: false`, `human_verify_mode: end-of-phase`), these need an explicit human sign-off. My (non-authoritative) verdict on all three is that they hold. The carried-forward app-launch smoke test also remains, but it is now low risk.

## Goal Achievement

### Observable Truths

The ROADMAP success criteria (the contract) come first, then the 02-02 must_haves, then the 02-PLAN must_haves (regression checks).

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1: all GPU adapters with model, VRAM (registry fallback for >4 GB), driver version | ✓ VERIFIED (data layer) | The GPU region is byte-identical to `210bc5f` (REGION_OK). Live run: `NVIDIA GeForce RTX 5070`, VRAM 11.9, driver `32.0.16.1742`, `GPU._Status=OK`, `Adapters` is `Object[]`, 1 of 1 WMI adapters listed. Rendering is deferred to Phase 3. |
| 2 | SC2: per-volume free/total for fixed drives only (a DriveType 2 volume is excluded) | ✓ VERIFIED (data layer) | `Where-Object { $_.DriveType -eq 3 }`. The WR-02 harness returns 3 of 4 mocked volumes, dropping the removable G:. Live run: 4 of 4 type-3 volumes with TotalGB/FreeGB. |
| 3 | SC3: motherboard manufacturer/product, BIOS version and release date | ✓ VERIFIED (was ✗ FAILED) | Live run: `ASUSTeK COMPUTER INC. / TUF GAMING B550-PLUS / 3644 / 2026-08-18 / OK`. ReleaseDate is now timezone- and culture-safe (truths 5-9). |
| 4 | SC4: null/filler SMBIOS strings are filtered to "Not available" | ✓ VERIFIED | `Test-SmbiosValue` is unchanged (REGION_OK). Re-ran 10 cases (fillers, padded filler, empty, whitespace, null, real values); 0 mismatches. |
| 5 | CR-01: firmware date `20260818000000.000000+000` gives `2026-08-18` in UTC-5, -8, -10 and +14 | ✓ VERIFIED | Harness h1: 12 `ok` lines. The harness checks that the zone swap took effect (`MockBios.Day -eq 17`). Independent real-CIM run under swapped zones: `2026-08-18` in every case. Pre-fix file: FAIL. |
| 6 | CR-01: Gregorian `yyyy-MM-dd` under every culture (th-TH, ar-SA) | ✓ VERIFIED | h1 th-TH and ar-SA rows `ok`; the real-CIM run agrees. Pre-fix: `2569-08-18`, `1448-03-04/05`. |
| 7 | DST-ambiguous midnight (W. Europe, 2026-10-25) stays `2026-10-25` | ✓ VERIFIED | h1: `ok DST-ambiguous W. Europe \| 2026-10-25`. The harness asserts `IsAmbiguousTime`, so the case is real. |
| 8 | Null ReleaseDate gives "Not available" and Motherboard `_Status` Partial | ✓ VERIFIED | h1: `ok null date \| Not available \| Partial`. The `if ($bios.ReleaseDate)` guard is unchanged. |
| 9 | On the real host, ReleaseDate equals the firmware's raw DMTF yyyyMMdd | ✓ VERIFIED | h2/h5: `ReleaseDate=2026-08-18 firmware=20260818000000.000000+000`. |
| 10 | WR-01: FreeSpace 0 gives FreeGB 0 (numeric, counted) | ✓ VERIFIED | `Akari.ps1:314` `if ($null -ne $disk.FreeSpace)`. h3 `PASS: WR-01` checks for a non-string 0. Pre-fix: `FAIL: full volume FreeGB=Not available`. |
| 11 | WR-01: FreeSpace null still gives "Not available" | ✓ VERIFIED | h3 E: case passes. |
| 12 | WR-02: Label is '' when unlabeled and not counted; healthy volumes give Disk `_Status` OK | ✓ VERIFIED | `$diskFields = 4` (`:295`); initializer `Label = ''` (`:305`); VolumeName line has no increment (`:310`). h4 PASS (C: "" and D: $null both give `''`, F: keeps "Data"). Live: `Vol: C: []`, `Disk._Status=OK`. Pre-fix: FAIL Partial. |
| 13 | WR-02: a missing counted field still gives Partial | ✓ VERIFIED | h4: a FileSystem of `$null` gives `Partial`. The four `$diskSuccess++` sites match `$diskFields = 4`. |
| 14 | Get-Specs returns exactly CPU, Disk, GPU, Motherboard, RAM, Windows | ✓ VERIFIED | h2/h5: `groups=CPU,Disk,GPU,Motherboard,RAM,Windows`, 1589 ms. |
| 15 | Outside the Disk..`return $result` region, Akari.ps1 equals `210bc5f`; only Akari.ps1 changed | ✓ VERIFIED | `REGION_OK` (600-line base region, not vacuous); `git diff --name-only 210bc5f -- . ':!.planning'` gives `Akari.ps1`; the `e6375d8..HEAD` diff has exactly 3 hunks (Disk fields, Disk lines, BIOS date) plus 4 comments. |
| 16 | GPU group has `_Status` + `Adapters`; adapter keys Model, VRAM_GB, DriverVersion, Status | ✓ VERIFIED (regression) | Live output |
| 17 | VRAM registry fallback triggers on capped AdapterRAM | ✓ VERIFIED (regression) | Line 258 unchanged; live 11.9 GB from `qwMemorySize` (the RTX 5070 reports the 4293918720 sentinel) |
| 18 | Disk group has `_Status` + `Volumes`; volume keys Drive, Label, FileSystem, TotalGB, FreeGB | ✓ VERIFIED (regression) | Live output; all 5 keys still present |
| 19 | Motherboard group has `_Status`, Manufacturer, Product, BIOSVersion, ReleaseDate | ✓ VERIFIED (regression) | Live output |
| 20 | `Test-SmbiosValue` is defined before `Get-Specs` with all 17 fillers | ✓ VERIFIED (regression) | `Akari.ps1:104-130` vs `function Get-Specs` at `:132` |
| 21 | Failed fields are "Not available", never `$null`/empty | ✓ VERIFIED | Every counted field starts as `'Not available'`. Label `''` is a deliberate, documented narrowing (02-02 truth): an empty label is a successful read, not a failed field. |
| 22 | Each group's `_Status` is OK, Partial or Failed by success count | ✓ VERIFIED | Disk, GPU and Motherboard tail logic is intact. Zero-volume branch: `$diskTotal = 0` keeps `Failed`. |
| 23 | Phase 1 groups (CPU, RAM, Windows) unchanged by Phase 2 | ✓ VERIFIED | REGION_OK vs `210bc5f`, and the 02-PLAN diff added no lines in those sections (prior verification) |

**Score:** 23/23 truths verified (0 present, behavior-unverified)

The behavior-dependent truths (5-13) are backed by named behavioral harnesses that I ran in-process, not by presence checks. Reliance check: the CR-01 harness creates its own Kind=Local precondition (`$utc.ToLocalTime()`). I confirmed that the production CIM path creates the same precondition (real `Get-CimInstance` returns `Kind=Local` under each swapped zone), so this is not fixture-only reliance. No coincidental-reliance items.

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | User-visible GPU, Disk and Motherboard cards (the "User sees" half of SPEC-03/04/05) | Phase 3 | SC2: "User sees specs arranged in a fluid card grid matching the existing dark theme". `$GetSpecsFunc` has no caller yet. |
| 2 | Refresh-path lifecycle: WR-06, WR-07, WR-08, IN-03 | Phase 3 | SC4: "freshly queried specs every time Home is shown without UI blocking" (REFR-01) |

### Advisory (New Scope, Unevidenced)

| # | Finding | Category | Why Advisory |
|---|---------|----------|--------------|
| 1 | WR-09: Windows `_Status` overcounts Build (UBR increment), so it can report OK while Edition failed | other | New-scope (Phase 1 code, commit 3b68df1). Not modified since the prior verification. No deterministic reproduction. Route to a Phase 1 follow-up. |
| 2 | IN-04: CPU Cores falls back to the logical-processor count | other | New-scope Phase 1 code, info severity |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Akari.ps1` (`$GetSpecsFunc` Get-Specs) | BIOS date in UTC + InvariantCulture; FreeGB accepts 0; Label not counted | ✓ VERIFIED | Contains the exact `ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)` (1 match). `ReleaseDate.ToString(` gives 0 matches; `FreeSpace -gt 0` gives 0; `Label = 'Not available'` gives 0. Parses with 0 errors. |
| `Akari.ps1` (`Invoke-Code -ResultVar` + tick) | Result handoff into `$script:SpecData` | ✓ VERIFIED (unchanged since `210bc5f`) | No caller yet, by design (Phase 3) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Get-Specs Motherboard/BIOS | `Win32_BIOS.ReleaseDate` (Kind=Local) | `ToUniversalTime()` then InvariantCulture | WIRED | `Akari.ps1:345`; behavior proven by h1, h2 and the real-CIM zone swap |
| Get-Specs Disk | `Win32_LogicalDisk.FreeSpace` / `VolumeName` | null-only guard; Label without increment | WIRED | `Akari.ps1:310, 314`; h3, h4, h5 |
| Get-Specs result | `$script:SpecData` | `Invoke-Code ... ResultVar` + tick reading `ResultCollection` | WIRED (unchanged) | Region byte-identical to `210bc5f`; the prior e2e simulation still applies |
| `$script:SpecData` | Home cards | Show-Page | NOT YET (by design) | Phase 3 scope (deferred item 1) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| GPU group | `Adapters[].VRAM_GB` | AdapterRAM / registry `qwMemorySize` | Yes (11.9) | ✓ FLOWING |
| Disk group | `Volumes[].FreeGB/TotalGB/Label` | `Win32_LogicalDisk` | Yes (C: 299/464.7, label '') | ✓ FLOWING |
| Motherboard group | `ReleaseDate` | `Win32_BIOS.ReleaseDate` | Yes, equals the firmware date in every tested zone and culture | ✓ FLOWING (was INACCURATE) |
| `$script:SpecData` | hashtable | runspace `ResultCollection` | Yes | ✓ FLOWING (no UI consumer yet) |

### Behavioral Spot-Checks

All were run by this verifier from Git Bash at the repo root on HEAD `f1394d8`.

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| CR-01 mocked zone/culture/DST/null matrix | 02-02 Task 1 `<automated>` #1 | 14 `ok` lines, `PASS: CR-01`, exit 0 | ✓ PASS |
| CR-01 live vs firmware | 02-02 Task 1 `<automated>` #2 | `PASS live: groups=CPU,Disk,GPU,Motherboard,RAM,Windows ReleaseDate=2026-08-18 firmware=20260818000000.000000+000` | ✓ PASS |
| WR-01 | 02-02 Task 2 `<automated>` | `PASS: WR-01` | ✓ PASS |
| WR-02 mocked | 02-02 Task 3 `<automated>` #1 | `PASS: WR-02` | ✓ PASS |
| WR-02 live | 02-02 Task 3 `<automated>` #2 | `PASS live: ... Disk=OK volumes=4 ms=1589` | ✓ PASS |
| Fail-first (harness discriminates) | same harnesses against `git show e6375d8:Akari.ps1` | h1 exit 1 (th-TH `2569-08-18`, ar-SA `1448-03-04/05`); h3 `FAIL: full volume FreeGB=Not available`; h4 `FAIL: ... _Status=Partial`; h5 `FAIL: ... Disk._Status=Partial` | ✓ PASS (all fail pre-fix) |
| Real CIM BIOS read under swapped zones (independent, no mock) | in-process TimeZoneInfo cache swap + `Get-CimInstance Win32_BIOS` + Get-Specs | 9/9 combinations give `2026-08-18`; raw CIM e.g. `2026-08-17T20:00-04:00 Kind=Local` | ✓ PASS |
| GPU / Disk / MB / SMBIOS regression | live Get-Specs + 10 `Test-SmbiosValue` cases | RTX 5070 11.9 GB OK; 4 volumes OK; MB OK; SMBIOS mismatches 0 | ✓ PASS |
| Non-result Invoke-Code path (the one tweaks use) | real `Invoke-Code` + real `Add_Tick` body extracted from the AST, with UI functions stubbed | log `Sim: optimize \| Memory Compression: Off \| guard ok \| Done: Sim: optimize`, Busy=False, state=True | ✓ PASS |
| Region / scope / read-only guards | plan verification steps 2-4 | `REGION_OK` (600-line base); `Akari.ps1` only; write-pattern count `0` | ✓ PASS |

### Probe Execution

No probes are declared in either PLAN or SUMMARY, and no `scripts/*/tests/probe-*.sh` exist. Not applicable. The 02-02 `<automated>` harnesses (the phase's runnable checks) were executed above.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SPEC-03 | 02-PLAN | GPU card listing all adapters with model, VRAM, driver version | ✓ SATISFIED (data layer; card rendering in Phase 3) | Truths 1, 16, 17 |
| SPEC-04 | 02-PLAN, 02-02-PLAN | Disk card with per-volume free/total for fixed drives | ✓ SATISFIED (data layer; card rendering in Phase 3) | Truths 2, 10-13, 18 |
| SPEC-05 | 02-PLAN, 02-02-PLAN | Motherboard + BIOS card with manufacturer/product, BIOS version, release date | ✓ SATISFIED (data layer; card rendering in Phase 3) (was BLOCKED) | Truths 3-9, 19 |

There are no orphaned requirements. REQUIREMENTS.md maps exactly SPEC-03, SPEC-04 and SPEC-05 to Phase 2, and the plans claim all three. REQUIREMENTS.md still shows them as `Gaps Found` / unchecked. The orchestrator can update that after the human sign-off.

### Anti-Patterns Found

| File | Line | Pattern / Finding | Severity | Impact |
|------|------|-------------------|----------|--------|
| Akari.ps1 | 305 | `Label = ''` hardcoded empty | ℹ️ Info (not a stub) | Intentional, documented contract: an empty label is a successful read. Overwritten by a real `VolumeName` (live: D:, F:, G: labels flow). |
| Akari.ps1 | 267-270 | WR-03: index-based VRAM fallback | ⚠️ Warning (carried, unchanged) | Can attach a ghost adapter's VRAM when the MatchingDeviceId prefix fails. Not reproducible on this single-GPU host. No phase assigned. |
| Akari.ps1 | 256-276 | WR-04: registry VRAM used only for sentinel values | ⚠️ Warning (carried) | Accuracy depends on the vendor sentinel. No phase assigned. |
| Akari.ps1 | 222, 249-283 | WR-05: virtual/basic display adapters listed and counted | ⚠️ Warning (carried) | Spurious entries and `Partial` on RDP/IDD setups. Matches the 02-PLAN truth "all are listed". No phase assigned. |
| Akari.ps1 | 480-523 | WR-06/07/08, IN-03 | ⚠️ Warning (deferred to Phase 3) | Must be handled before refresh-on-show |
| Akari.ps1 | 193-214 | WR-09 (Phase 1 code) | 📋 Advisory | See the Advisory table |
| Akari.ps1 | 258 | IN-01 unreachable `-ge 4GB` | ℹ️ Info | Readability |
| Akari.ps1 | 108-128 | IN-02 filler list incomplete / case-insensitive | ℹ️ Info | Some OEM placeholders shown as values |

There are no TBD, FIXME, XXX, TODO, HACK or PLACEHOLDER markers in `Akari.ps1`.

The previous Blocker (CR-01, line 341) is resolved.

WR-03, WR-04 and WR-05 are pre-existing and untouched since the prior verification, which classed them as warnings. They do not defeat a success criterion on observed hardware. They are hardening debt for the "hardware-diversity handling" clause of the goal and should be scheduled (backlog), not forgotten.

### Human Verification Required

#### 1. Prohibition [SPEC-05]: never show a BIOS date that differs from the firmware

**Test:** Review the evidence: the h1 matrix (14 ok), the real-CIM zone swap (9/9 `2026-08-18`) and the live comparison with the firmware.
**Expected:** Sign off that the prohibition holds. Verifier verdict (non-authoritative): HOLDS.
**Why human:** The prohibition is judgment-tier with no wired enforcement test. Interactive mode needs explicit resolution.

#### 2. Prohibition [SPEC-04]: never report a Windows-reported disk value as failed, never invent free space

**Test:** Review the WR-01/WR-02 harnesses and the live `Disk=OK`. Decide whether `Size = 0` showing TotalGB "Not available" is acceptable (the plan intends this).
**Expected:** Sign off. Verifier verdict (non-authoritative): HOLDS.
**Why human:** The prohibition is judgment-tier.

#### 3. Prohibition [SPEC-04/05]: Get-Specs is read-only

**Test:** Review the write-pattern grep (0 matches) and the reads-only cmdlet set in `$GetSpecsFunc`.
**Expected:** Sign off. Verifier verdict (non-authoritative): HOLDS.
**Why human:** The prohibition is judgment-tier.

#### 4. App launch smoke test (carried forward, low risk)

**Test:** Launch `powershell -ExecutionPolicy Bypass -File Akari.ps1` elevated. Browse categories, run one Toggle tweak (Optimize, then Default), and use the Advanced Read/Apply tuners.
**Expected:** No error dialog; "Done: ..." is logged; the page re-enables.
**Why human:** The elevated WPF window cannot be launched by the verifier. The non-result path has been simulated (PASS), and Phase 2's edits to Invoke-Code and the tick are confined to the unused `-ResultVar` branch.

### Gaps Summary

No gaps remain.

- The one failed truth from the initial verification (SC3: the BIOS release date was wrong west of UTC and in non-Gregorian cultures) is closed by `fbb2bc1`. I proved this with the plan's mocked matrix, a fail-first run against the pre-fix file, and an independent real-CIM check under swapped timezones.
- The two recommended data-accuracy warnings are closed: WR-01 (`cd79bf5`) and WR-02 (`c55c7a0`).
- Nothing outside the Disk and BIOS region changed.

The data layer for all three cards is accurate on this host and robust to timezone and culture. Card rendering and the refresh lifecycle are explicitly Phase 3's work.

The phase is `human_needed` only because the 02-02 plan declared three judgment-tier prohibitions, which need explicit human sign-off in interactive mode, plus the carried-forward app-launch smoke test. Once those are signed off, the phase can be treated as passed.

Backlog note: WR-03, WR-04 and WR-05 (GPU hardware-diversity hardening) and WR-09 (Phase 1 Windows status overcount) remain open with no phase assigned.

---

_Verified: 2026-10-08T15:01:48Z_
_Verifier: Claude (gsd-verifier)_
