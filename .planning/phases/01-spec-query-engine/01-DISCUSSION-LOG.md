# Phase 1: Spec Query Engine - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-08
**Phase:** 1-Spec Query Engine
**Areas discussed:** Result structure, Data sources, Fallback behavior, Data return mechanism

---

## Result Structure

### Q1: What shape should the spec query return?

| Option | Description | Selected |
|--------|-------------|----------|
| Grouped hashtable | `@{ CPU = @{...}; RAM = @{...}; Windows = @{...} }` — matches existing codebase patterns | ✓ |
| Flat hashtable | `@{ 'CPU.Model' = '...'; 'CPU.Cores' = 8; ... }` — easier for Phase 3 to consume directly | |
| PSObject | Custom typed object with properties — more structured, but new pattern | |

**User's choice:** Grouped hashtable
**Notes:** None

### Q2: Within each group, how should fields be organized?

| Option | Description | Selected |
|--------|-------------|----------|
| Flat within group | `CPU = @{ Model = '...'; Cores = 8; Threads = 16; SpeedMHz = 3600 }` | ✓ |
| Nested sub-groups | `CPU = @{ Info = @{ Model = '...' }; Cores = @{ Physical = 8; Logical = 16 } }` | |
| You decide | Agent picks the most practical structure | |

**User's choice:** Flat within group
**Notes:** None

### Q3: How should RAM used/free be computed?

| Option | Description | Selected |
|--------|-------------|----------|
| Win32_OperatingSystem | TotalVisibleMemorySize - FreePhysicalMemory = used. Matches Task Manager. | |
| Win32_ComputerSystem only | TotalPhysicalMemory for total; used = total - free. | |
| You decide | Agent picks the most reliable inbox source | ✓ |

**User's choice:** You decide
**Notes:** Agent will use Win32_OperatingSystem for total/free in a single query, compute used as the difference.

### Q4: Should the result include metadata about query success/failure per group?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, include status | Each group gets a `_Status` field ('OK' or 'Partial') | ✓ |
| No, just data | Only spec fields; Phase 3 handles 'Not available' per-field | |
| You decide | Agent picks based on Phase 3 needs | |

**User's choice:** Yes, include status
**Notes:** Status values later refined to three states: 'OK' / 'Partial' / 'Failed'

---

## Data Sources

### Q1: What source strategy should each spec group use?

| Option | Description | Selected |
|--------|-------------|----------|
| CIM for all | Win32_Processor (CPU), Win32_ComputerSystem+Win32_OperatingSystem (RAM), Win32_OperatingSystem (Windows) | ✓ |
| Registry for all | Registry keys for Windows edition/build; CIM only where registry lacks data | |
| Hybrid | Registry for Windows edition/build; CIM for CPU and RAM | |

**User's choice:** CIM for all
**Notes:** None

### Q2: Win32_OperatingSystem doesn't expose UBR — how should we handle Windows build info?

| Option | Description | Selected |
|--------|-------------|----------|
| CIM + registry for UBR | Win32_OperatingSystem for edition/caption/build; registry for UBR only | ✓ |
| CIM only, skip UBR | Use only Win32_OperatingSystem; build number without UBR | |
| You decide | Agent picks the best approach | |

**User's choice:** CIM + registry for UBR
**Notes:** Minimal registry use — only for UBR which CIM cannot provide

### Q3: Which CIM class should be used for CPU specs?

| Option | Description | Selected |
|--------|-------------|----------|
| Win32_Processor | Standard CIM class. Has Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed | ✓ |
| Win32_Processor + registry | CIM for model/cores/threads; registry for additional details | |

**User's choice:** Win32_Processor
**Notes:** None

### Q4: Should the query handle multiple instances or just the first?

| Option | Description | Selected |
|--------|-------------|----------|
| First instance only | Use Select-Object -First 1 for CPU. Covers 99%+ of consumer systems | ✓ |
| Aggregate all | Sum cores/threads across all CPUs, list all models | |
| You decide | Agent picks based on what's most practical | |

**User's choice:** First instance only
**Notes:** None

---

## Fallback Behavior

### Q1: How granular should the fallback be?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-field try/catch | Each field gets its own try/catch. Most granular. | ✓ |
| Per-group try/catch | Each group gets one try/catch. All fields in group show 'Not available' if any fails. | |
| Hybrid | Per-group try/catch with per-field fallback within. | |

**User's choice:** Per-field try/catch
**Notes:** None

### Q2: When an entire CIM query fails, what should happen?

| Option | Description | Selected |
|--------|-------------|----------|
| All fields 'Not available' | If the query itself fails, every field in that group shows 'Not available' | ✓ |
| Group status 'Failed' | Mark the group _Status as 'Failed' and show 'Not available' for all fields | |
| You decide | Agent picks the most robust approach | |

**User's choice:** All fields 'Not available'
**Notes:** None

### Q3: What exact text should be shown for failed fields?

| Option | Description | Selected |
|--------|-------------|----------|
| 'Not available' | Matches REFR-02 wording exactly | ✓ |
| 'N/A' | Shorter, more compact | |
| You decide | Agent picks the most appropriate text | |

**User's choice:** 'Not available'
**Notes:** None

### Q4: What values should the _Status field have for each group?

| Option | Description | Selected |
|--------|-------------|----------|
| 'OK' / 'Partial' / 'Failed' | Three states: all fields OK, some failed, entire query failed | ✓ |
| 'OK' / 'Failed' only | Two states: query succeeded or failed | |
| You decide | Agent picks the most useful status values | |

**User's choice:** 'OK' / 'Partial' / 'Failed'
**Notes:** None

---

## Data Return Mechanism

### Q1: How should spec data get back from the background runspace to the UI thread?

| Option | Description | Selected |
|--------|-------------|----------|
| Extend Invoke-Code | Add a -Result parameter to Invoke-Code that captures the return value | ✓ |
| New Get-Specs function | Create a dedicated function that creates its own runspace | |
| Shared variable | Set a script-scope variable from within the runspace | |

**User's choice:** Extend Invoke-Code
**Notes:** Reuses existing runspace + DispatcherTimer infrastructure

### Q2: How should the -Result parameter capture the return value?

| Option | Description | Selected |
|--------|-------------|----------|
| Script-scope variable | Invoke-Code sets $script:Specs when the job completes | ✓ |
| Callback function | Invoke-Code calls a specified function when the job completes | |
| You decide | Agent picks the most practical approach | |

**User's choice:** Script-scope variable
**Notes:** None

### Q3: How should Phase 3 know when spec data is ready?

| Option | Description | Selected |
|--------|-------------|----------|
| In Show-Page | The DispatcherTimer already calls Show-Page on job completion. Phase 3 reads the variable in Show-Page. | ✓ |
| Separate completion flag | Set a $script:SpecsReady flag when the query completes | |
| You decide | Agent picks the most practical approach | |

**User's choice:** In Show-Page
**Notes:** No extra infrastructure needed

### Q4: Should the spec query be a single function or multiple functions?

| Option | Description | Selected |
|--------|-------------|----------|
| Single function | One Get-Specs function that queries all three groups and returns the full grouped hashtable | ✓ |
| Multiple functions | Separate Get-CPU, Get-RAM, Get-Windows functions | |
| You decide | Agent picks the most practical structure | |

**User's choice:** Single function
**Notes:** One runspace execution for all three groups

---

## Agent's Discretion

- RAM used/free computation approach (D-03) — agent picks the most reliable inbox source
- Exact field names within each group (as long as they're descriptive and consistent)
- Whether to include additional helpful fields beyond the minimum

## Deferred Ideas

None — discussion stayed within phase scope.
