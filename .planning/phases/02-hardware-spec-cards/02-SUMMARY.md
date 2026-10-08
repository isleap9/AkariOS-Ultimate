---
phase: 02-hardware-spec-cards
plan: 2
subsystem: data
tags: [powershell, cim, wmi, registry, smbios, gpu, disk, bios, runspace]

requires:
  - phase: 01-spec-query-engine
    provides: Get-Specs here-string ($GetSpecsFunc), Invoke-Code -ResultVar, $script:SpecData, per-field fallback pattern
provides:
  - Get-Specs GPU group (Adapters array; Model, VRAM_GB, DriverVersion, Status per adapter) with 64-bit registry VRAM fallback
  - Get-Specs Disk group (Volumes array; Drive, Label, FileSystem, TotalGB, FreeGB per fixed volume)
  - Get-Specs Motherboard group (Manufacturer, Product, BIOSVersion, ReleaseDate) with SMBIOS filler filtering
  - Test-SmbiosValue helper inside $GetSpecsFunc
  - Working Invoke-Code -ResultVar path on PowerShell 5.1 (Phase 1 latent bug fixed)
affects: [03-home-shell, home-page, spec-cards]

actuals:
  tokens: 2519
  tasks: 3
  commits: 4
plan_head_before: fe014fb86ae66116ba0a7b2e51e2cb344f94ece2
plan_head_after: 210bc5fd22680e6c831305cfd15019e21468af44

tech-stack:
  added: []
  patterns:
    - "Multi-instance spec groups use an array of hashtables (GPU.Adapters, Disk.Volumes) appended with += ,$item"
    - "SMBIOS strings pass through Test-SmbiosValue before use; fillers become 'Not available'"
    - "Capped uint32 AdapterRAM resolved via HardwareInformation.qwMemorySize, matched by MatchingDeviceId then index"

key-files:
  created: []
  modified:
    - Akari.ps1

key-decisions:
  - "VRAM fallback reads HardwareInformation.qwMemorySize (the value Windows actually writes); qwSize kept as legacy name"
  - "Capped AdapterRAM detection includes NVIDIA's 0xFFF00000 (4293918720) sentinel; capped with no registry value reports 'Not available' rather than a wrong 4 GB"
  - "Registry VRAM key matched to adapter by MatchingDeviceId prefix of PNPDeviceID first, index ('{0:D4}') as fallback"
  - "Invoke-Code -ResultVar passes an empty completed PSDataCollection as input and the tick reads $j.ResultCollection"

patterns-established:
  - "Array-group _Status: total = items x fieldsPerItem; zero items => 'Failed'"

requirements-completed: [SPEC-03, SPEC-04, SPEC-05]

coverage:
  - id: D1
    description: "GPU group lists all adapters with model, VRAM (registry fallback for >4 GB), driver version"
    requirement: "SPEC-03"
    verification:
      - kind: integration
        ref: "scratchpad verify-specs.ps1: Get-Specs on RTX 5070 host -> Model/VRAM_GB=11.9/DriverVersion populated, _Status OK"
        status: pass
    human_judgment: false
  - id: D2
    description: "Disk group with per-volume free/total space for fixed drives only"
    requirement: "SPEC-04"
    verification:
      - kind: integration
        ref: "scratchpad verify-specs.ps1: 4 fixed NTFS volumes returned with TotalGB/FreeGB"
        status: pass
    human_judgment: false
  - id: D3
    description: "Motherboard + BIOS group with SMBIOS filler filtering and yyyy-MM-dd release date"
    requirement: "SPEC-05"
    verification:
      - kind: integration
        ref: "scratchpad verify-specs.ps1: ASUSTeK TUF GAMING B550-PLUS / BIOS 3644 / 2026-08-18; Test-SmbiosValue 9 cases pass"
        status: pass
    human_judgment: false
  - id: D4
    description: "Get-Specs result flows through Invoke-Code -ResultVar and the DispatcherTimer tick into $script:SpecData"
    verification:
      - kind: integration
        ref: "scratchpad verify-e2e.ps1: real Invoke-Code + real Add_Tick body -> $script:SpecData hashtable with all 6 groups"
        status: pass
    human_judgment: false
  - id: D5
    description: "App still launches and existing tweak rows / tuners behave identically"
    verification:
      - kind: other
        ref: "[System.Management.Automation.Language.Parser]::ParseFile Akari.ps1 -> 0 errors"
        status: pass
    human_judgment: true
    rationale: "Launching the elevated WPF window and clicking tweak buttons needs a human; only the parse check is automated"

duration: 5min
completed: 2026-10-08
status: complete
---

# Phase 2 Plan 2: Hardware Spec Cards Data Layer Summary

**Get-Specs now returns GPU (all adapters, true 64-bit VRAM from `HardwareInformation.qwMemorySize`), fixed-disk volumes, and SMBIOS-filtered motherboard/BIOS groups. A latent Phase 1 bug that kept `Invoke-Code -ResultVar` from ever delivering results on PowerShell 5.1 is also fixed.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-10-08T14:07:39Z
- **Completed:** 2026-10-08T14:12:18Z
- **Tasks:** 3/3 (plus 1 deviation fix)
- **Files modified:** 1 (`Akari.ps1`)

## Accomplishments

- `Test-SmbiosValue` helper (17 filler strings, null/whitespace rejection) defined before `Get-Specs` in `$GetSpecsFunc`
- GPU group: every `Win32_VideoController` instance becomes an entry in `Adapters`. Capped AdapterRAM is resolved from the display-class registry. On the test host the RTX 5070 reads 11.9 GB instead of a wrong 4 GB.
- Disk group: `Win32_LogicalDisk` with `DriveType -eq 3`, per-volume Drive/Label/FileSystem/TotalGB/FreeGB, and a guard for null FreeSpace
- Motherboard group: `Win32_BaseBoard` + `Win32_BIOS` with filler filtering, BIOS date as `yyyy-MM-dd`
- `Invoke-Code -ResultVar` now works end to end, so `$script:SpecData` gets populated. Before this fix it threw on `BeginInvoke`.

## Task Commits

1. **Task 2.1: Test-SmbiosValue + GPU group** - `ce4de3b` (feat)
2. **Task 2.2: Disk group** - `ab1fdcf` (feat)
3. **Task 2.3: Motherboard/BIOS group** - `287e609` (feat)
4. **Deviation: Invoke-Code -ResultVar fix** - `210bc5f` (fix)

## Files Created/Modified

- `Akari.ps1` - `$GetSpecsFunc` extended with `Test-SmbiosValue`, GPU, Disk, Motherboard sections; `Invoke-Code` result branch and DispatcherTimer tick fixed

## Verification Results

- Parse check (`Parser::ParseFile`): PASS, 0 errors; `$GetSpecsFunc` body parses on its own
- Running `Get-Specs` directly (PS 5.1, 1.4 s): all 6 groups; CPU/RAM/Windows unchanged from Phase 1
- `Test-SmbiosValue` unit cases: 9/9 PASS
- Integration (real `Invoke-Code` + real tick scriptblock extracted from Akari.ps1): `$script:SpecData` is a hashtable with CPU, Disk, GPU, Motherboard, RAM, Windows. Every adapter, volume, and motherboard key is present.
- All task acceptance-criteria greps: PASS. `git diff` since phase start removes no Phase 1 lines from Get-Specs.
- Not automated: launching the elevated WPF app and clicking through tweaks/tuners (left for end-of-phase human verify)

## Decisions Made

See `key-decisions` in frontmatter. The main one: the VRAM registry value name and the capped-value detection were corrected after checking them against real hardware.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Wrong registry value name and incomplete capped-VRAM detection**
- **Found during:** Task 2.1 (runtime check)
- **Issue:** The plan and research read `HardwareInformation.qwSize`, but Windows writes the 64-bit size to `HardwareInformation.qwMemorySize`. NVIDIA also reports AdapterRAM as 4293918720 (0xFFF00000), which matches neither `-eq 4294967295` nor `-ge 4GB`. Result: an RTX 5070 showed 4 GB.
- **Fix:** Read `qwMemorySize` first, falling back to `qwSize`. Added `-ge 4293918720` to the capped check, keeping the plan's original condition. A capped value with no registry match reports `Not available` instead of a wrong number. Registry keys are matched by `MatchingDeviceId` first, then by index, so iGPU+dGPU systems whose key order differs from WMI order still get correct VRAM. REG_BINARY sizes are decoded with `BitConverter`.
- **Files modified:** Akari.ps1
- **Verification:** RTX 5070 now reports 11.9 GB (12820938752 bytes, matching the driver)
- **Commit:** ce4de3b

**2. [Rule 2 - Missing critical] Select-Object -First 1 on board/BIOS queries**
- **Found during:** Task 2.3
- **Issue:** Research 3.6 notes rare multi-instance `Win32_BIOS`. `.Trim()` on an array would throw and silently drop the whole group.
- **Fix:** Added `| Select-Object -First 1` to both queries
- **Commit:** 287e609

**3. [Rule 1 - Bug] Invoke-Code -ResultVar path broken on PowerShell 5.1 (Phase 1 code)**
- **Found during:** Plan-level integration verification
- **Issue:** `$ps.BeginInvoke($null, $resultCollection)` throws "Cannot find an overload for BeginInvoke" in PS 5.1, which also leaves `Set-Busy` stuck on. Separately, `EndInvoke` returns nothing when the caller supplies the output buffer, so the tick would always set `$script:SpecData = $null`. Phase 3 depends on this path directly.
- **Fix:** Pass an empty completed `PSDataCollection[object]` as input. The tick now reads `$j.ResultCollection` after `EndInvoke`. The non-result path is untouched.
- **Files modified:** Akari.ps1
- **Verification:** `verify-e2e.ps1` passes with the fix and fails on the pre-fix revision with the overload error
- **Commit:** 210bc5f

**Total deviations:** 3 auto-fixed (2 Rule 1, 1 Rule 2). **Impact:** All three are needed for correct, live specs. No scope creep, no new files.

## Issues Encountered

- `-contains` is case-insensitive, while plan truths say the filler match is "case-sensitive". The acceptance criteria require `-contains`, which was kept. Case-insensitive matching is stricter about placeholders like "To be filled by O.E.M.", so this works in the user's favour.
- Commits went to `main`: the protected-branch assertion flags `main`, but the orchestrator specified sequential execution on `main` (branching_strategy `none`, matching all prior phase commits).

## Notes for Phase 3

- Disk `_Status` is `Partial` whenever a volume has no label (common for C:), because Label counts as one of 5 fields. Phase 3 should not show a warning badge on Disk `Partial` alone, or should treat `Label = 'Not available'` as "no label".
- VRAM is binary GB (bytes/1GB), so a 12 GB card shows 11.9 when the driver reports 12227 MiB. This matches GPU-Z and the driver.
- Numbers are doubles; format them with invariant culture when rendering if a decimal point (not comma) is wanted.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `$script:SpecData` now actually populates via `Invoke-Code ($GetSpecsFunc + "`nGet-Specs") '...' $null 'SpecData'`
- Ready for Phase 3 (Home Shell & Live Refresh) to render all six groups

## Self-Check: PASSED

- FOUND: Akari.ps1
- FOUND: ce4de3b, ab1fdcf, 287e609, 210bc5f (all ancestors of HEAD)
- evaluation-scope (02-02, commits-only): resolved, 4 commits
- No stubs (only a comment containing the word "placeholder")
