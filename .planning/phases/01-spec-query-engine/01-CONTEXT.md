# Phase 1: Spec Query Engine - Context

**Gathered:** 2026-10-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Build reliable background CIM/registry queries for CPU, RAM, and Windows specs with per-field fallback. This phase delivers the data layer — a single `Get-Specs` function that runs in the existing background runspace and returns a grouped hashtable of spec data. Phase 3 consumes this data for the Home page card grid.

</domain>

<decisions>
## Implementation Decisions

### Result Structure
- **D-01:** Grouped hashtable — `@{ CPU = @{...}; RAM = @{...}; Windows = @{...} }`. Matches existing codebase patterns (all state is script-scope hashtables).
- **D-02:** Flat within each group — simple key-value pairs per group (e.g., `CPU = @{ Model = '...'; Cores = 8; Threads = 16; SpeedMHz = 3600 }`). No nested sub-groups.
- **D-03:** RAM computation — agent discretion. Use `Win32_OperatingSystem` for total/free in a single query, compute used as the difference. Matches Task Manager values.
- **D-04:** Include `_Status` field per group — `'OK'`, `'Partial'`, or `'Failed'`. Phase 3 uses this to show/hide cards or adjust display.

### Data Sources
- **D-05:** CIM for all spec queries — comprehensive and consistent. No registry except where CIM lacks data.
- **D-06:** CIM + registry for UBR — `Win32_OperatingSystem` for edition/caption/build; registry `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` for UBR only. Minimal registry use.
- **D-07:** `Win32_Processor` for CPU specs — Name (model), NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed. One query for all CPU fields.
- **D-08:** First instance only — use `Select-Object -First 1` for CPU. Covers 99%+ of consumer systems; multi-CPU aggregation is out of scope.

### Fallback Behavior
- **D-09:** Per-field try/catch — each field gets its own try/catch. If CPU model fails but cores succeed, model shows "Not available" but cores show real values. Most granular.
- **D-10:** Complete query failure → all fields in that group show "Not available". Clean and predictable.
- **D-11:** Display text for failed fields: `"Not available"` — matches REFR-02 wording exactly.
- **D-12:** Status values: `'OK'` (all fields succeeded), `'Partial'` (some fields failed), `'Failed'` (entire query failed).

### Data Return Mechanism
- **D-13:** Extend `Invoke-Code` with a `-Result` parameter — captures the return value into a script-scope variable. Reuses existing runspace + DispatcherTimer infrastructure.
- **D-14:** Script-scope variable for result capture — `Invoke-Code` sets the variable when the job completes. Phase 3 reads it after completion.
- **D-15:** Completion detection in `Show-Page` — the DispatcherTimer already calls `Show-Page` on job completion. Phase 3 reads the script-scope variable in `Show-Page`. No extra infrastructure.
- **D-16:** Single `Get-Specs` function — one function that queries all three groups (CPU, RAM, Windows) and returns the full grouped hashtable. One runspace execution.

### Agent Discretion
- RAM used/free computation approach (D-03) — agent picks the most reliable inbox source
- Exact field names within each group (as long as they're descriptive and consistent)
- Whether to include additional helpful fields beyond the minimum (e.g., CPU socket, RAM type/speed)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Definition
- `.planning/ROADMAP.md` — Phase 1 goal, requirements (SPEC-01, SPEC-02, SPEC-06, REFR-02), success criteria
- `.planning/REQUIREMENTS.md` — Detailed requirement definitions for spec cards, fallback behavior
- `.planning/PROJECT.md` — Key decisions, constraints, architecture context

### Codebase Maps
- `.planning/codebase/ARCHITECTURE.md` — System architecture, component responsibilities, Invoke-Code pattern
- `.planning/codebase/STACK.md` — Technology stack, runtime constraints
- `.planning/codebase/CONVENTIONS.md` — Code style, naming patterns, function design
- `.planning/codebase/STRUCTURE.md` — File organization, entry points

### Source Code
- `Akari.ps1` — Invoke-Code function (line 223), Get-RamKB (line 348), DispatcherTimer (line 237), Show-Page, $script:Busy guard
- `UI/MainWindow.xaml` — UI layout, named elements, dark theme resources

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Invoke-Code` function (`Akari.ps1:223`): Background runspace execution with log pumping. Will be extended with `-Result` parameter for spec data return.
- `DispatcherTimer` + `$script:Queue` (`Akari.ps1:237-256`): 150ms tick drains log queue and completes jobs. Calls `Show-Page` on completion — Phase 3 reads spec data here.
- `Get-RamKB` (`Akari.ps1:348`): Existing CIM query pattern using `Get-CimInstance Win32_ComputerSystem`.
- `$script:Busy` guard: Prevents concurrent runspace execution. Spec queries must respect this.
- `$Helpers` preamble: Logging and registry helpers available inside runspaces.

### Established Patterns
- Background execution: All non-UI work runs in a runspace via `Invoke-Code`. Spec queries follow this pattern.
- CIM queries: `Get-CimInstance` is the standard for system info. Used throughout the codebase.
- Script-scope state: All shared state is `$script:` variables (hashtables, not objects).
- Per-field error handling: Existing code uses `-ErrorAction SilentlyContinue` and try/catch for defensive reads.
- DispatcherTimer completion: `Show-Page` is called when a job completes — this is where Phase 3 will read spec data.

### Integration Points
- `Invoke-Code` extension: Add `-Result` parameter that captures return value into a script-scope variable on job completion.
- `Show-Page` function: Called by DispatcherTimer on job completion. Phase 3 reads the spec data variable here.
- `$script:Busy` guard: Spec query sets busy during execution, preventing concurrent operations.
- `Get-Specs` function: New function that composes CIM queries and returns the grouped hashtable.

</code_context>

<specifics>
## Specific Ideas

- The grouped hashtable structure should be: `@{ CPU = @{ _Status = 'OK'; Model = '...'; Cores = 8; Threads = 16; SpeedMHz = 3600 }; RAM = @{ _Status = 'OK'; TotalGB = 16; UsedGB = 8; FreeGB = 8 }; Windows = @{ _Status = 'OK'; Edition = 'Pro'; Version = '23H2'; Build = '22631.1234' } }`
- The `_Status` field is reserved and should not conflict with spec field names.
- Field names should be descriptive and consistent (e.g., `SpeedMHz` not `Speed`, `TotalGB` not `Total`).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 1-Spec Query Engine*
*Context gathered: 2026-10-08*
