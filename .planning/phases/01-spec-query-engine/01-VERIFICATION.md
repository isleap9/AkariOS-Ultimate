---
phase: 01-spec-query-engine
verified: 2026-10-09T13:56:24Z
status: passed
score: 23/23 must-haves verified
covered_files:
  - .planning/phases/01-spec-query-engine/01-PLAN.md
  - .planning/phases/01-spec-query-engine/01-SUMMARY.md
  - Akari.ps1
covered_digest: "v3:sha256:e20d24b7c3bd0cd4e0221ede978ea7138f71a23da4c6a6e7cdc62b8ac55ac6f3"
behavior_unverified: 0
overrides_applied: 0
---

# Verification Report: Phase 01 Spec Query Engine

## Phase Goal

Deliver reliable background queries for CPU, RAM, and Windows specs with per-field fallback.

## Status: PASSED

## Score: 23/23 must-haves verified

## Verdict

All six ROADMAP success criteria were verified against live code execution on the host machine. The `$GetSpecsFunc` here-string in `Akari.ps1` implements the complete spec query engine as specified in `01-PLAN.md`. Every success criterion, must-have, and requirement claim in the plan holds up against runtime evidence.

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User sees CPU model, core/thread counts, and base speed queried from CIM | VERIFIED | Live run: Model "AMD Ryzen 7 5800X 8-Core Processor", Cores 8, Threads 16, SpeedMHz 3801, Sockets 1. Model and clock taken from first Win32_Processor instance; cores/threads summed across all sockets. |
| 2 | User sees total RAM and used/free amounts computed from PhysicalMemory sum | VERIFIED | Live run: TotalGB 31.9 (equals Win32_ComputerSystem.TotalPhysicalMemory), UsedGB 11.6, FreeGB 20.3. Used+Free equals Total. Source is Win32_OperatingSystem.TotalVisibleMemorySize / FreePhysicalMemory, divided by 1MB. |
| 3 | User sees Windows edition, friendly version, and full build number (incl. UBR) | VERIFIED | Live run: Edition "Microsoft Windows 11 Pro" (Win32_OperatingSystem.Caption), Version "26H2" (registry DisplayVersion), Build "26300.9457" (BuildNumber + UBR composed as "$($winBuild).$($reg.UBR)"). |
| 4 | Individual fields that fail to query show "Not available" instead of blank or error | VERIFIED | All four CPU fields initialized to "Not available" before the try block. Mock matrix H2 confirmed: a throwing CIM query, an empty CPU object, a zero RAM read, a missing registry key, and a throwing registry read each degrade only their own group to "Not available" with no null, blank, or thrown field. |
| 5 | Get-Specs returns a grouped hashtable with keys CPU, RAM, Windows | VERIFIED | Live run returned exactly `CPU,Disk,GPU,Motherboard,RAM,Windows` - includes the three Phase 1 groups plus the Phase 2 additions. |
| 6 | Each group contains a _Status field with value OK, Partial, or Failed | VERIFIED | Every group uses the pattern `if ok=0 -> Failed, elseif ok<fields -> Partial, else OK`. Live run: CPU OK, RAM OK, Windows OK. |
| 7 | CPU group contains Model (string), Cores (int), Threads (int), SpeedMHz (int) | VERIFIED | Live run types: Model String, Cores Int32, Threads Int32, SpeedMHz UInt32 (raw CIM type is UInt32; numeric and correct). |
| 8 | RAM group contains TotalGB (double), UsedGB (double), FreeGB (double) | VERIFIED | All three live values are Double, rounded to one decimal via `[math]::Round(..., 1)`. |
| 9 | Windows group contains Edition (string), Version (string), Build (string) | VERIFIED | All three live values are String. Build composes the UBR suffix only when both the base build and the registry UBR are present. |
| 10 | Failed fields are the string "Not available", never null or empty | VERIFIED | Mock matrix checked every CPU, RAM, and Windows field under five failure modes. Zero nulls and zero empty strings observed. |
| 11 | Get-Specs is defined as a here-string constant, not a separate file | VERIFIED | AST extraction returned 11,746 characters from `$GetSpecsFunc = @'...'@`. `return $result` present. |
| 12 | Only Akari.ps1 is modified - no new files created | VERIFIED | `git show --name-only 3b68df1` returns exactly `Akari.ps1`. |
| 13 | $script:SpecData declared as null at script scope | VERIFIED | Line 38: `$script:SpecData = $null`. |
| 14 | CIM is the primary data source; registry used only for UBR and DisplayVersion | VERIFIED | All eight `Get-CimInstance` calls are inside `$GetSpecsFunc` / `$HostIdentityFunc`. The single `Get-ItemProperty` reads only `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion`. |
| 15 | Win32_OperatingSystem is used for RAM (not Win32_PhysicalMemory) | VERIFIED | RAM block queries `Win32_OperatingSystem`; grep for `Win32_PhysicalMemory` in Akari.ps1 returns zero matches. |
| 16 | Per-field try/catch is the fallback strategy | VERIFIED | CPU, RAM, and Windows each have their own try/catch. Each field has its own conditional guard and its own success counter increment. |
| 17 | CPU query covers every socket (summed cores/threads) | VERIFIED | Mock H7 with two 20-core sockets returned Cores 40, Threads 80, Sockets 2, model and clock from the first socket, status OK. |
| 18 | Every CIM call in the read path carries a per-call timeout | VERIFIED | Eight Get-CimInstance calls found; zero without `-OperationTimeoutSec 10` (added in Phase 4-03, a1950ed... see History section). |
| 19 | Result capture writes only from the spec-read completion path | VERIFIED | The tick's tweak-completion block (`$j = $script:Job`) contains no `ResultCollection` or `SpecData` reference. `$script:SpecData = $last` appears in the `$sj` block only. |
| 20 | Existing Invoke-Code callers work unchanged | VERIFIED | Real `Invoke-Code` + real `$Helpers` preamble + real tick body executed end to end: log contained "Sim: optimize", "Memory Compression: Off", "guard ok", "Done: Sim: optimize"; Busy reset to false; toggle state saved; Read-Svc and Show-Page still called. |
| 21 | Tweak completion still logs, resets busy, saves state, and re-renders | VERIFIED | Same run as truth 20: Save-State called once, Read-Svc true, Show-Page true, no error stream entries. |
| 22 | Akari.ps1 parses with zero syntax errors | VERIFIED | AST parse of Akari.ps1 reports 0 errors. |
| 23 | The spec read issues no writes (read-only) | VERIFIED | Write-pattern grep over the extracted read code (Set-ItemProperty, New-ItemProperty, Remove-Item, reg add, Set-TimeZone, tzutil, Set-Volume, Set-Content) returns zero hits. Read cmdlets present: Get-CimInstance, Get-ItemProperty, Get-ChildItem. |

## Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `Akari.ps1` (`$GetSpecsFunc`) | VERIFIED | 11,746-char here-string containing `function Get-Specs`, the CPU/RAM/Windows blocks, and `return $result`. Parses cleanly. |
| `Akari.ps1` (`$SpecReadCode`) | VERIFIED | Composes `$GetSpecsFunc + HostIdentity + @'try { @{ Specs = Get-Specs; Host = Get-HostIdentity } } catch { $_.Exception.Message }'@`. Extracted verbatim from the AST. |
| `Akari.ps1` (`Invoke-Code`) | VERIFIED | Signature `function Invoke-Code([string]$code, [string]$label, $meta = $null)`. Runs real tweak bodies in a runspace and pumps output to the log queue. |
| `Akari.ps1` (`$timer.Add_Tick`) | VERIFIED | 3,233-char tick body containing the spec-completion block, the tweak-completion block, log/queue draining, and `$script:SpecData` assignment. |
| `Akari.ps1` (`$script:SpecData` decl) | VERIFIED | Line 38. |

## Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| `$SpecReadCode` | `$script:SpecData` | `$timer.Add_Tick` reads `$sj.ResultCollection` and assigns `$last` (which carries the `Specs` key) | WIRED |
| `Start-SpecRead` | real runspace | `BeginInvoke($inputCollection, $resultCollection)` with a `Deadline` of `SpecTimeoutSec` | WIRED |
| Tweak buttons | `Invoke-Code` | `Invoke-Code $t.Apply.ToString() ...` | WIRED |
| `Get-Specs` | CIM | 7 `Get-CimInstance` calls with `-OperationTimeoutSec 10` | WIRED |
| `Get-Specs` | registry UBR/DisplayVersion | 1 `Get-ItemProperty` on `CurrentVersion` | WIRED |

## Data-Flow Trace (Level 4)

| Value | Source | Flows | Status |
|-------|--------|-------|--------|
| CPU Model / Cores / Threads / SpeedMHz | `Win32_Processor` (CIM) | Yes - equals raw CIM values | FLOWING |
| RAM TotalGB / UsedGB / FreeGB | `Win32_OperatingSystem` (CIM) | Yes - matches TotalPhysicalMemory and FreePhysicalMemory | FLOWING |
| Windows Edition | `Win32_OperatingSystem.Caption` | Yes - matches raw Caption | FLOWING |
| Windows Version | registry `DisplayVersion` | Yes - matches raw value | FLOWING |
| Windows Build | `Win32_OperatingSystem.BuildNumber` + registry `UBR` | Yes - matches "26300.9457" | FLOWING |

## Behavioral Spot-Checks

| Check | Result | Status |
|-------|--------|--------|
| Live CPU/RAM/Windows values vs independent CIM ground truth | All 20 assertions PASS | PASS |
| Live composite read through real runspace + real tick body | SpecData populated, no error, SpecJob cleared | PASS |
| CIM totally down (every query throws) | CPU/RAM Failed, all fields "Not available", registry-sourced Version survives, no crash | PASS |
| Composite read throws | Tick logs "Specs: Read failed", SpecData falls back to New-FailedSpecs (first load) | PASS |
| Mock matrix: CPU throw, OS throw, empty CPU object, CPU partial, zero RAM, zero free RAM, missing registry, throwing registry | 10/10 scenarios PASS, zero failures | PASS |
| Two-socket CPU mock (Phase 4-03 change) | Cores 40, Threads 80, Sockets 2, status OK | PASS |
| Real Invoke-Code + real tick on the non-result path | Log lines, Busy reset, state saved, Show-Page called | PASS |

## History (phases that changed Phase 1 code)

- **Phase 2** (`ce4de3b`, `ab1fdcf`, `287e609`) added `Test-SmbiosValue` and the GPU, Disk, and Motherboard/BIOS groups inside the same `$GetSpecsFunc` here-string. The Phase 1 CPU/RAM/Windows blocks were not touched.
- **Phase 3** (`df495cc`) added `$HostIdentityFunc`, `$SpecReadCode`, `Start-SpecRead`, and the `$script:SpecJob` completion block. The Phase 1 `Invoke-Code -ResultVar` harvest path became unused dormant code.
- **Phase 4-03** (`a0750ed`, WR-01) added `-OperationTimeoutSec 10` to all eight CIM calls in the read path and added the 20-second watchdog/`SpecStale` disposal list.
- **Phase 4-03** (`23e836c`, WR-02) removed the dormant `Invoke-Code -ResultVar` parameter and its result-harvest branch, leaving only the spec-read path able to write `$script:SpecData`.
- **Phase 4-03** (`23e836c`, WR-03) replaced the single-instance CPU read with a per-socket `Measure-Object` sum and added `CPU.Sockets`.

All of these are additive to, or deliberate removals of, the Phase 1 mechanism. Every Phase 1 must-have that survives was re-verified against the current tree.

## Requirements Coverage

| Requirement | Source | Status | Evidence |
|-------------|--------|--------|----------|
| SPEC-01 | 01-PLAN | SATISFIED | Truth 1; live CIM values match raw `Win32_Processor` |
| SPEC-02 | 01-PLAN | SATISFIED | Truth 2; RAM total/used/free from `Win32_OperatingSystem` with used computed as difference |
| SPEC-06 | 01-PLAN | SATISFIED | Truth 3; edition, DisplayVersion, and `BuildNumber.UBR` |
| REFR-02 | 01-PLAN | SATISFIED | Truth 4; 10-scenario mock matrix, zero null/blank fields |

**Orphaned requirements:** none. `REQUIREMENTS.md` maps exactly SPEC-01, SPEC-02, SPEC-06, and REFR-02 to Phase 1, and 01-PLAN claims all four.

## Anti-Patterns Found

| File | Pattern | Severity | Notes |
|------|---------|----------|-------|
| Akari.ps1 | TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER | none | Zero case-sensitive matches |
| Akari.ps1 | `return @{}` stub | none | Zero matches in the read path |
| Akari.ps1 | "not implemented" / "coming soon" | none | Zero matches |
| Akari.ps1 | write cmdlets in the read path | none | Zero matches |

## Human Verification Required

None. Every must-have was verified by executing the real code against live CIM and registry data, or by the mocked failure matrix.

---

*Verified: 2026-10-09T13:56:24Z*
