---
phase: 02-hardware-spec-cards
verified: 2026-10-08T14:19:52Z
status: gaps_found
score: 13/14 must-haves verified
covered_files:
  - .planning/phases/02-hardware-spec-cards/02-PLAN.md
  - .planning/phases/02-hardware-spec-cards/02-SUMMARY.md
  - Akari.ps1
covered_digest: "v3:sha256:b5389df27b5fc9fd3b7b48afd0af65af571bca25b50fd42f827056983092d774"
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "User sees motherboard manufacturer/product, BIOS version, and release date (ROADMAP SC3 / SPEC-05; plan truth: BIOS ReleaseDate is formatted as yyyy-MM-dd)"
    status: partial
    reason: "The BIOS release date is wrong for every user west of UTC and in non-Gregorian cultures (code review CR-01, reproduced). Get-CimInstance turns the SMBIOS datetime '20260818000000.000000+000' (midnight UTC) into a Kind=Local DateTime. Akari.ps1:341 then formats it with .ToString('yyyy-MM-dd'), using the local clock and the current culture's calendar. Reproduced on this host: the Eastern and Pacific code paths produce 2026-08-17 for a BIOS dated 2026-08-18, and th-TH produces 2569-08-18. Manufacturer, Product and BIOSVersion are correct. Only ReleaseDate fails, but a wrong value shown as fact defeats the core value ('accurate specs')."
    artifacts:
      - path: "Akari.ps1"
        issue: "line 341: $bios.ReleaseDate.ToString('yyyy-MM-dd') formats a local-time DateTime with the current culture; needs UTC conversion and InvariantCulture"
    missing:
      - "Format the BIOS date as $bios.ReleaseDate.ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)"
      - "Re-check by converting the raw '20260818000000.000000+000' through a UTC-5 zone and the th-TH culture: both must give 2026-08-18"
      - "Recommended in the same gap-closure plan (warnings, same data-accuracy concern): WR-01, treat FreeSpace = 0 as 0 GB rather than 'Not available' (Akari.ps1:311)"
deferred:
  - truth: "User-visible rendering of the GPU, Disk and Motherboard/BIOS cards ('User sees ... card' in SPEC-03/04/05 and ROADMAP SC1-3)"
    addressed_in: "Phase 3"
    evidence: "Phase 3 goal: 'Home as default landing with card grid, live refresh, and navigation'; SC2: 'User sees specs arranged in a fluid card grid matching the existing dark theme'. The Phase 2 PLAN Notes scope this phase to the Get-Specs data layer: 'Phase 3 ... reads $script:SpecData in Show-Page and renders GPU, Disk, and Motherboard cards'."
  - truth: "Spec refresh lifecycle concerns on the Invoke-Code -ResultVar path (code review WR-06, WR-07, WR-08: ignored ResultVar name, dropped refresh while busy, Read-Svc/Show-Page on completion, BeginInvoke failure leaves Busy stuck)"
    addressed_in: "Phase 3"
    evidence: "Phase 3 SC4: 'User sees freshly queried specs every time Home is shown without UI blocking'; REFR-01 is mapped to Phase 3"
human_verification:
  - test: "Launch the elevated app (powershell -ExecutionPolicy Bypass -File Akari.ps1), click through several categories, run one Toggle tweak (Optimize/Default) and the Advanced-page tuners (Read/Apply)"
    expected: "Window opens with no error box. Tweak rows, Set-Prio and Set-Svc behave as before Phase 2. The log shows 'Done: ...' and the page is re-enabled after each run."
    why_human: "Commit 210bc5f changed the shared Invoke-Code and DispatcherTimer tick used by every tweak. A non-UI simulation exercised only the -ResultVar branch, so the elevated WPF window and the non-result path need a human click-through."
---

# Phase 2: Hardware Spec Cards Verification Report

**Phase Goal:** GPU, disk, and motherboard/BIOS cards with hardware-diversity handling
**Verified:** 2026-10-08T14:19:52Z
**Status:** gaps_found
**Re-verification:** No (initial verification)

> **MVP-mode note:** ROADMAP marks Phase 2 `Mode: mvp`, but the goal is not a user story. `user-story.validate` returns `valid: false`: no "As a ..., I want to ..., so that ...". Under the MVP rules the verifier would refuse. The orchestrator explicitly asked for verification, so this report uses standard goal-backward verification against the four ROADMAP success criteria (already user-facing "User sees ..." statements) plus the PLAN must_haves. There is no User Flow Coverage table. To make the mode consistent, run `/gsd-mvp-phase 2` or remove `mode: mvp` from the phase. Phase 1 has the same mismatch.

## Goal Achievement

### Observable Truths

ROADMAP success criteria (contract) come first, then PLAN must_haves not already covered by an SC.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1: All GPU adapters with model, VRAM (registry fallback for >4 GB), driver version | ✓ VERIFIED (data layer) | `Akari.ps1:216-290`. Every `Win32_VideoController` instance is iterated with no filter. Live run: `NVIDIA GeForce RTX 5070; VRAM_GB=11.9; DriverVersion=32.0.16.1742`. AdapterRAM is the NVIDIA sentinel 4293918720; the fallback resolved `qwMemorySize=12820938752` through the `MatchingDeviceId` prefix match (`pci\ven_10de&dev_2f04&subsys_53231462`), not the index heuristic. Rendering is deferred to Phase 3. |
| 2 | SC2: Per-volume free/total space for fixed drives only | ✓ VERIFIED (data layer) | `Akari.ps1:292-321`. `Where-Object { $_.DriveType -eq 3 }`. Live run: 4 volumes (C:, D:, F:, G:, all type 3) with TotalGB/FreeGB populated. Warnings WR-01 and WR-02 below. Rendering is deferred to Phase 3. |
| 3 | SC3: Motherboard manufacturer/product, BIOS version, and release date | ✗ FAILED (partial) | Manufacturer, Product and BIOSVersion are correct (`ASUSTeK COMPUTER INC.` / `TUF GAMING B550-PLUS` / `3644`). **ReleaseDate is inaccurate west of UTC and in non-Gregorian cultures** (CR-01, reproduced; see the CR-01 spot-checks). |
| 4 | SC4: Null/filler SMBIOS strings filtered to "Not available" | ✓ VERIFIED | `Test-SmbiosValue` (`Akari.ps1:104-130`) is applied to Manufacturer, Product and SMBIOSBIOSVersion (lines 333-340). 15 cases run: fillers, padded fillers, null, empty and whitespace give `False`; real values give `True`. Matching is case-insensitive (`-contains`), which is stricter than the plan's "case-sensitive" wording (IN-02). |
| 5 | Get-Specs returns six groups CPU, RAM, Windows, GPU, Disk, Motherboard | ✓ VERIFIED | Live run `GROUPS=CPU,Disk,GPU,Motherboard,RAM,Windows`. |
| 6 | GPU group has `_Status` + `Adapters` array; adapter keys Model, VRAM_GB, DriverVersion, Status | ✓ VERIFIED | `Adapters` is `Object[]`, and the keys are present (live output). |
| 7 | VRAM registry fallback triggers on `-eq 4294967295 -or -ge 4GB` | ✓ VERIFIED | Line 258. Extended with `-ge 4293918720` (an improvement, documented deviation). Reads `qwMemorySize`, then `qwSize`. |
| 8 | Disk group has `_Status` + `Volumes` array with Drive, Label, FileSystem, TotalGB, FreeGB | ✓ VERIFIED | `Volumes` is `Object[]` with 4 entries, and the keys are present. |
| 9 | Motherboard group has `_Status`, Manufacturer, Product, BIOSVersion, ReleaseDate | ✓ VERIFIED (structure) | Lines 344-347; live output. The accuracy of ReleaseDate is covered by truth 3. |
| 10 | `Test-SmbiosValue` is defined before `Get-Specs` with all 17 fillers | ✓ VERIFIED | Lines 104-130, before `function Get-Specs` at line 132; 17 entries. |
| 11 | Failed fields are `"Not available"`, never `$null` or empty | ✓ VERIFIED | Every per-field local or hashtable value starts as `'Not available'` (lines 251, 304, 324-327). |
| 12 | Each new group's `_Status` is OK, Partial or Failed by success count | ✓ VERIFIED | Lines 289-290, 320-321, 348-349. Live run: GPU OK, Motherboard OK, Disk Partial (unlabeled C:, WR-02). |
| 13 | Phase 1 groups (CPU, RAM, Windows) unchanged | ✓ VERIFIED | `git diff fe014fb..HEAD -- Akari.ps1` removes only the 2 `Invoke-Code` lines (the documented deviation fix). No Get-Specs lines were removed. |
| 14 | Only `Akari.ps1` modified, no new files | ✓ VERIFIED | `git diff --stat fe014fb..HEAD -- . ':!.planning'` shows `Akari.ps1` only. |

**Score:** 13/14 truths verified (0 present, behavior-unverified)

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | User-visible GPU, Disk and Motherboard cards (the "User sees" half of SPEC-03/04/05) | Phase 3 | Phase 3 SC2: "User sees specs arranged in a fluid card grid matching the existing dark theme" |
| 2 | Refresh-path lifecycle issues WR-06, WR-07, WR-08 | Phase 3 | Phase 3 SC4: "freshly queried specs every time Home is shown without UI blocking" (REFR-01) |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Akari.ps1` (`$GetSpecsFunc`) | Test-SmbiosValue + GPU/Disk/Motherboard groups | ✓ VERIFIED | Substantive (about 175 added lines). Parses with 0 errors and runs in 1.6-1.8 s under PS 5.1. |
| `Akari.ps1` (`Invoke-Code -ResultVar` + tick) | Result handoff into `$script:SpecData` | ✓ VERIFIED (wired) | Non-UI simulation of the real extracted `Invoke-Code` and `Add_Tick` body: `SpecData` becomes a Hashtable with all 6 keys, Busy resets to False, and the job clears. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Get-Specs` | `Test-SmbiosValue` | same here-string, defined first | WIRED | Called at lines 333, 334 and 340 |
| `Get-Specs` GPU | display-class registry | `HardwareInformation.qwMemorySize` | WIRED | Fired on the live host through the MatchingDeviceId match |
| `Invoke-Code ... 'SpecData'` | `$script:SpecData` | `ResultCollection` read in tick | WIRED | e2e simulation PASS |
| `$script:SpecData` | Home cards | Show-Page | NOT YET (by design) | Phase 3 scope; no consumer exists yet |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| GPU group | `Adapters[].VRAM_GB` | `Win32_VideoController.AdapterRAM` / registry `qwMemorySize` | Yes (11.9) | ✓ FLOWING |
| Disk group | `Volumes[].FreeGB/TotalGB` | `Win32_LogicalDisk` | Yes | ✓ FLOWING |
| Motherboard group | `ReleaseDate` | `Win32_BIOS.ReleaseDate` | Yes, but timezone- and culture-dependent | ⚠️ FLOWING, INACCURATE (CR-01) |
| `$script:SpecData` | hashtable | runspace `ResultCollection` | Yes | ✓ FLOWING (no UI consumer yet) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Akari.ps1 parses | `Parser::ParseFile` | 0 errors | ✓ PASS |
| Get-Specs returns 6 groups, real data | extract `$GetSpecsFunc` from the AST, dot-source, `Get-Specs` (PS 5.1) | 6 groups, 1766 ms | ✓ PASS |
| VRAM fallback above 4 GB | same run | RTX 5070 shows 11.9 GB (AdapterRAM sentinel 4293918720) | ✓ PASS |
| Fixed drives only | same run vs `Win32_LogicalDisk` | 4/4 type-3 volumes | ✓ PASS (host has no removable drive to exclude) |
| SMBIOS filler filtering | `Test-SmbiosValue` over 15 inputs | all as expected | ✓ PASS |
| `-ResultVar` handoff | extracted `Invoke-Code` + tick body, stubbed UI functions | SpecData Hashtable, Busy=False | ✓ PASS |
| CR-01 BIOS date, UTC-negative zone | raw `20260818000000.000000+000`, local `2026-08-18T02:00+02:00 Kind=Local`, converted to Eastern/Pacific | `2026-08-17` | ✗ FAIL |
| CR-01 BIOS date, non-Gregorian culture | `ReleaseDate.ToString('yyyy-MM-dd')` under th-TH | `2569-08-18` | ✗ FAIL |

### Probe Execution

No probes are declared in the PLAN or SUMMARY, and no `scripts/*/tests/probe-*.sh` exist. Not applicable.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SPEC-03 | 02-PLAN | GPU card listing all adapters with model, VRAM, driver version | ✓ SATISFIED (data layer; card rendering → Phase 3) | Truths 1, 6, 7 |
| SPEC-04 | 02-PLAN | Disk card with per-volume free/total for fixed drives | ✓ SATISFIED (data layer; card rendering → Phase 3) | Truths 2, 8 |
| SPEC-05 | 02-PLAN | Motherboard + BIOS card with manufacturer/product, BIOS version, release date | ✗ BLOCKED | Release date inaccurate (CR-01). `REQUIREMENTS.md` already marks SPEC-05 `[x]` Complete, which is premature. |

There are no orphaned requirements. REQUIREMENTS.md maps exactly SPEC-03, SPEC-04 and SPEC-05 to Phase 2, and all three are claimed by 02-PLAN.

### Anti-Patterns Found

| File | Line | Pattern / Finding | Severity | Impact |
|------|------|-------------------|----------|--------|
| Akari.ps1 | 341 | CR-01: local-time, current-culture BIOS date format | 🛑 Blocker | Wrong date shown as fact for the Americas and some cultures; defeats SC3 and the core value |
| Akari.ps1 | 311 | WR-01: `FreeSpace -gt 0` drops a valid 0 | ⚠️ Warning | 100%-full volume shows "Not available"; rare (exactly 0 bytes free) |
| Akari.ps1 | 294, 308 | WR-02: Label counted as a fallible field | ⚠️ Warning | Disk `_Status=Partial` on healthy machines (observed: C: unlabeled). C: label shows "Not available" rather than blank. |
| Akari.ps1 | 267-270 | WR-03: index-based VRAM fallback | ⚠️ Warning | Can attach a ghost or another adapter's VRAM when the MatchingDeviceId prefix fails. The plan accepted this as threat T2. Not reproducible on this single-GPU host. |
| Akari.ps1 | 256-276 | WR-04: registry VRAM used only for sentinel values | ⚠️ Warning | Accuracy depends on the vendor using one of two sentinels |
| Akari.ps1 | 222, 249-283 | WR-05: virtual and basic display adapters listed and counted | ⚠️ Warning | Spurious GPU entries and `Partial` on RDP or IDD setups. This is consistent with the plan's "all are listed" truth but weakens hardware-diversity handling. |
| Akari.ps1 | 476-523 | WR-06/07/08: ResultVar contract, refresh loop risk, Busy stuck on BeginInvoke throw | ⚠️ Warning (deferred to Phase 3) | Phase 3 must handle these before wiring refresh-on-show |
| Akari.ps1 | 258 | IN-01: unreachable `-ge 4GB` on a uint32 | ℹ️ Info | Readability |
| Akari.ps1 | 108-128 | IN-02: filler list incomplete (`O.E.M.` passes) | ℹ️ Info | Some OEM placeholders shown as values |
| Akari.ps1 | 512 | IN-03: SpecData not type-checked | ℹ️ Info | Fragile to stray output |

There are no TBD, FIXME, XXX, TODO or HACK markers in `Akari.ps1`.

### Human Verification Required

#### 1. App launch and unchanged tweak behavior after the Invoke-Code change

**Test:** Launch `powershell -ExecutionPolicy Bypass -File Akari.ps1` elevated. Browse categories, run one Toggle tweak (Optimize, then Default), and use the Advanced-page Read/Apply tuners.
**Expected:** No error dialog; rows, Set-Prio and Set-Svc behave as before; "Done: ..." is logged and the page re-enables.
**Why human:** Commit 210bc5f edited the shared `Invoke-Code` and DispatcherTimer tick. Only the `-ResultVar` branch was exercised, in a non-UI simulation.

### Gaps Summary

The data layer is real, wired and runs: GPU (with a working 64-bit VRAM fallback), fixed-disk volumes, and SMBIOS-filtered board/BIOS fields reach `$script:SpecData` through a repaired `Invoke-Code -ResultVar` path. Three of the four success criteria hold.

One criterion fails: the **BIOS release date is not accurate across the user base.** The SMBIOS date is a midnight-UTC value. Get-CimInstance converts it to local time, and line 341 formats that with the current culture. Every user in a UTC-negative timezone (all of the Americas) sees the previous day, and Thai or Hijri-calendar locales see a different year. The SUMMARY's integration test passed only because the dev host is UTC+2. The project's core value is "if the specs are wrong ... the page fails its purpose", so a reproducible wrong value presented as fact is a blocker rather than a warning, even though the fix is one line (`.ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)`).

The eight review warnings do not individually defeat the goal. WR-01 (0-free-space volume) and WR-02 (Partial on healthy disks) are worth fixing in the same gap-closure pass because they are cheap and concern data accuracy and status semantics. WR-03, WR-04 and WR-05 are hardware-diversity hardening (VRAM matching and virtual adapters) that could not be reproduced on this single-dGPU host. WR-06, WR-07 and WR-08 belong to the refresh lifecycle that Phase 3 owns and must be handled before Phase 3 wires refresh-on-show (especially WR-07's Show-Page re-entry loop risk).

Process notes: REQUIREMENTS.md already marks SPEC-05 Complete, which should be reverted until CR-01 is fixed. The phase's `mode: mvp` tag conflicts with its non-user-story goal.

---

_Verified: 2026-10-08T14:19:52Z_
_Verifier: Claude (gsd-verifier)_
