---
phase: 01-spec-query-engine
plan: 1
subsystem: data
tags: [powershell, cim, wmi, runspace, specs, registry]

requires: []
provides:
  - Get-Specs function returning grouped hashtable (CPU, RAM, Windows)
  - Invoke-Code -Result parameter for runspace result capture
  - $script:SpecData script-scope variable for spec data
  - DispatcherTimer result capture into $script:SpecData
affects: [02-hardware-spec-cards, 03-home-shell]

tech-stack:
  added: []
  patterns:
    - "Invoke-Code -Result parameter pattern for runspace result capture"
    - "PSDataCollection[object] for thread-safe result collection"
    - "Per-field try/catch with success tracking for CIM queries"
    - "Here-string constant for runspace function definitions"

key-files:
  created: []
  modified:
    - Akari.ps1

key-decisions:
  - "Used Win32_OperatingSystem for RAM (not Win32_PhysicalMemory) — matches Task Manager values"
  - "Select-Object -First 1 for CPU query — covers single-socket consumer systems"
  - "Per-field try/catch is the fallback strategy — most granular error handling"
  - "Get-Specs defined as here-string constant, not separate file"

patterns-established:
  - "Invoke-Code -Result: PSDataCollection captures return value, DispatcherTimer extracts last object"
  - "Per-field fallback: initialize to 'Not available', increment success counter, compute _Status"

requirements-completed: [SPEC-01, SPEC-02, SPEC-06, REFR-02]

duration: 12min
completed: 2026-10-08
---

# Phase 1: Spec Query Engine Summary

**Get-Specs function with CIM/registry queries, per-field fallback, and Invoke-Code -Result extension for runspace result capture**

## Performance

- **Duration:** 12 min
- **Started:** 2026-10-08T15:00:00Z
- **Completed:** 2026-10-08T15:12:00Z
- **Tasks:** 4
- **Files modified:** 1

## Accomplishments

- Extended Invoke-Code with -Result parameter using PSDataCollection for thread-safe result capture
- Added Get-Specs function querying CPU (Win32_Processor), RAM (Win32_OperatingSystem), and Windows (CIM + registry) specs
- Per-field fallback to "Not available" with _Status tracking (OK/Partial/Failed)
- Modified DispatcherTimer tick to capture result hashtable into $script:SpecData

## Task Commits

1. **Task 1.1: Extend Invoke-Code with -Result parameter** - `3b68df1` (feat)
2. **Task 1.2: Add $script:SpecData variable declaration** - `3b68df1` (feat)
3. **Task 1.3: Add $GetSpecsFunc here-string constant** - `3b68df1` (feat)
4. **Task 1.4: Modify DispatcherTimer tick to capture result** - `3b68df1` (feat)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified

- `Akari.ps1` - Added Invoke-Code -Result parameter, $script:SpecData declaration, $GetSpecsFunc here-string with Get-Specs function, DispatcherTimer result capture

## Decisions Made

- Used Win32_OperatingSystem for RAM total/free (matches Task Manager) instead of Win32_PhysicalMemory
- Select-Object -First 1 for CPU query covers 99%+ of consumer systems
- Per-field try/catch with success counter for granular _Status computation
- Get-Specs as here-string constant ($GetSpecsFunc) prepended to runspace code

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- $script:SpecData ready for Phase 3 Show-Page to consume
- Get-Specs function available for Phase 3 to invoke via Invoke-Code
- Invoke-Code -Result parameter available for any future runspace result capture needs

---
*Phase: 01-spec-query-engine*
*Completed: 2026-10-08*
