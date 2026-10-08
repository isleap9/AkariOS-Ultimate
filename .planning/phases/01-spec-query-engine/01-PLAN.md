---
phase: 1
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - Akari.ps1
autonomous: true
requirements:
  - SPEC-01
  - SPEC-02
  - SPEC-06
  - REFR-02
---

# Plan 1: Spec Query Engine — Data Layer

## Objective

Deliver the complete data layer for the Home page: a `Get-Specs` function that queries CPU, RAM, and Windows specs via CIM/registry with per-field fallback, executed in the background runspace via an extended `Invoke-Code` that captures the result into `$script:SpecData` for Phase 3 to consume.

## Phase Goal

Reliable background queries for CPU, RAM, and Windows specs with per-field fallback.

## Requirements Addressed

| ID | Description | How This Plan Delivers |
|----|-------------|----------------------|
| SPEC-01 | CPU card with model, core/thread counts, and base speed | `Get-Specs` queries `Win32_Processor` for `Name`, `NumberOfCores`, `NumberOfLogicalProcessors`, `MaxClockSpeed` |
| SPEC-02 | RAM card with total installed memory and used/free amounts in GB | `Get-Specs` queries `Win32_OperatingSystem` for `TotalVisibleMemorySize` and `FreePhysicalMemory`, computes used as difference |
| SPEC-06 | Windows card with edition, friendly version, and full build number (incl. UBR) | `Get-Specs` queries `Win32_OperatingSystem` for `Caption`/`BuildNumber` and registry `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` for `UBR`/`DisplayVersion` |
| REFR-02 | "Not available" for individual fields that fail to query | Per-field try/catch with success tracking; failed fields default to `"Not available"` string |

## must_haves

- `Invoke-Code` accepts a `-Result` parameter (string, default `$null`) that names a script-scope variable to receive the return value
- `Invoke-Code` preserves existing behavior when `-Result` is not provided (all output to log queue)
- `$script:SpecData` is declared as `$null` at script scope
- `$GetSpecsFunc` here-string constant contains the full `Get-Specs` function definition
- `Get-Specs` returns a grouped hashtable with keys `CPU`, `RAM`, `Windows`
- Each group contains a `_Status` field with value `'OK'`, `'Partial'`, or `'Failed'`
- CPU group contains fields: `Model` (string), `Cores` (int), `Threads` (int), `SpeedMHz` (int)
- RAM group contains fields: `TotalGB` (double), `UsedGB` (double), `FreeGB` (double)
- Windows group contains fields: `Edition` (string), `Version` (string), `Build` (string)
- Failed fields are the string `"Not available"`, never `$null` or empty
- DispatcherTimer tick captures the result hashtable into `$script:SpecData` when job has `ResultVar`
- DispatcherTimer tick calls `Show-Page` after capturing result (existing behavior preserved)
- `Get-Specs` is invoked via `Invoke-Code` with `-ResultVar 'SpecData'` parameter

## truths

- Only `Akari.ps1` is modified — no new files created
- `Get-Specs` is a here-string constant (`$GetSpecsFunc`) prepended to runspace code, not a separate file
- The DispatcherTimer already calls `Show-Page` on job completion — Phase 3 reads spec data there
- CIM is the primary data source; registry is used only for UBR and DisplayVersion
- `Win32_OperatingSystem` is used for RAM (not `Win32_PhysicalMemory`) — matches Task Manager values
- `Select-Object -First 1` is used for CPU query — covers single-socket consumer systems
- Per-field try/catch is the fallback strategy — most granular error handling
- The `-Result` parameter uses `PSDataCollection[object]` for thread-safe result capture

## Tasks

<task id="1.1" type="execute" wave="1">
<title>Extend Invoke-Code with -Result parameter</title>
<read_first>
- Akari.ps1 (lines 223-235 — current Invoke-Code function)
- .planning/phases/01-spec-query-engine/01-RESEARCH.md (section 2 — Invoke-Code extension pattern)
- .planning/phases/01-spec-query-engine/01-PATTERNS.md (section 2.2 — Invoke-Code patterns)
</read_first>
<action>
Modify the `Invoke-Code` function signature at Akari.ps1 line 223 to add a `[string]$ResultVar = $null` parameter. When `$ResultVar` is provided (non-empty), use result-capturing mode: create a `[System.Management.Automation.PSDataCollection[object]]::new()` collection, wrap the code as `$__result = & { <code> }; $__result` (assign result to variable then output as last pipeline object), call `$ps.BeginInvoke($null, $resultCollection)` instead of `$ps.BeginInvoke()`, and store `ResultVar` and `ResultCollection` in the `$script:Job` hashtable. When `$ResultVar` is `$null` or empty, preserve the existing behavior exactly: wrap as `& { <code> } *>&1 | Out-String -Stream | ForEach-Object { if ($_.Trim()) { Write-Log $_ } }` and call `$ps.BeginInvoke()`. The `$script:Job` hashtable in result-capturing mode must include keys `ResultVar` (string) and `ResultCollection` (PSDataCollection). The existing `Ps`, `Rs`, `Handle`, `Label`, `Meta` keys are preserved in both modes.
</action>
<acceptance_criteria>
- Akari.ps1 line 223 contains `function Invoke-Code([string]$code, [string]$label, $meta = $null, [string]$ResultVar = $null)`
- The function body contains a conditional branch checking `if ($ResultVar)` for result-capturing mode
- Result-capturing mode creates `[System.Management.Automation.PSDataCollection[object]]::new()`
- Result-capturing mode calls `$ps.BeginInvoke($null, $resultCollection)` (two-argument overload)
- Standard mode calls `$ps.BeginInvoke()` (zero-argument, existing behavior)
- `$script:Job` in result-capturing mode contains `ResultVar` and `ResultCollection` keys
- Existing callers (Set-Prio, Set-Svc, row button handlers) continue to work unchanged — they do not pass `-Result`
</acceptance_criteria>
</task>

<task id="1.2" type="execute" wave="1">
<title>Add $script:SpecData variable declaration</title>
<read_first>
- Akari.ps1 (lines 32-37 — script-scope variable declarations)
- .planning/phases/01-spec-query-engine/01-PATTERNS.md (section 2.4 — script-scope hashtable state)
</read_first>
<action>
Add `$script:SpecData = $null` to the script-scope variable declarations block at Akari.ps1 around line 37 (after `$script:Queue` declaration). This variable will hold the grouped hashtable returned by `Get-Specs` after the DispatcherTimer captures it. Initialize to `$null` so Phase 3 can check for `$null` to determine if spec data is available.
</action>
<acceptance_criteria>
- Akari.ps1 contains `$script:SpecData = $null` in the script-scope variable declarations block (near lines 32-37)
- The variable is declared at script scope (not function scope)
- No other variables are removed or renamed
</acceptance_criteria>
</task>

<task id="1.3" type="execute" wave="1">
<title>Add $GetSpecsFunc here-string constant with Get-Specs function</title>
<read_first>
- Akari.ps1 (lines 70-100 — $Helpers here-string pattern)
- Akari.ps1 (lines 348 — Get-RamKB CIM query pattern)
- .planning/phases/01-spec-query-engine/01-RESEARCH.md (sections 1.1-1.3 — CIM query patterns for CPU, RAM, Windows)
- .planning/phases/01-spec-query-engine/01-RESEARCH.md (section 3 — per-field fallback strategies)
- .planning/phases/01-spec-query-engine/01-PATTERNS.md (section 2.5 — per-field error handling patterns)
- .planning/phases/01-spec-query-engine/01-CONTEXT.md (decisions D-01 through D-16)
</read_first>
<action>
Add a `$GetSpecsFunc` here-string constant (using `@'...'@` syntax, placed after the `$Helpers` constant around line 100) containing the full `Get-Specs` function definition. The function must:

1. Initialize the result hashtable: `$result = @{ CPU = @{ _Status = 'OK' }; RAM = @{ _Status = 'OK' }; Windows = @{ _Status = 'OK' } }`

2. CPU section — query `Win32_Processor` with `Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1`. Initialize local variables `$cpuModel`, `$cpuCores`, `$cpuThreads`, `$cpuSpeedMHz` all to `"Not available"`. Track `$cpuFields = 4` and `$cpuSuccess = 0`. Inside try/catch: if `$cpu.Name` is non-empty, set `$cpuModel = $cpu.Name.Trim()` and increment `$cpuSuccess`. If `$cpu.NumberOfCores -gt 0`, set `$cpuCores = $cpu.NumberOfCores` and increment; elseif `$cpu.NumberOfLogicalProcessors -gt 0`, set `$cpuCores = $cpu.NumberOfLogicalProcessors` and increment. If `$cpu.NumberOfLogicalProcessors -gt 0`, set `$cpuThreads = $cpu.NumberOfLogicalProcessors` and increment. If `$cpu.MaxClockSpeed -gt 0`, set `$cpuSpeedMHz = $cpu.MaxClockSpeed` and increment. After the try/catch, set `$result.CPU.Model = $cpuModel`, `$result.CPU.Cores = $cpuCores`, `$result.CPU.Threads = $cpuThreads`, `$result.CPU.SpeedMHz = $cpuSpeedMHz`. Compute `_Status`: if `$cpuSuccess -eq 0` set `'Failed'`, elseif `$cpuSuccess -lt $cpuFields` set `'Partial'`, else leave `'OK'`.

3. RAM section — query `Win32_OperatingSystem` with `Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop`. Initialize `$ramTotalGB`, `$ramUsedGB`, `$ramFreeGB` all to `"Not available"`. Track `$ramFields = 3` and `$ramSuccess = 0`. Inside try/catch: if `$os.TotalVisibleMemorySize -gt 0`, compute `$totalKB = $os.TotalVisibleMemorySize`, `$freeKB = $os.FreePhysicalMemory`, `$usedKB = $totalKB - $freeKB`, then `$ramTotalGB = [math]::Round($totalKB / 1MB, 1)`, `$ramUsedGB = [math]::Round($usedKB / 1MB, 1)`, `$ramFreeGB = [math]::Round($freeKB / 1MB, 1)`, incrementing `$ramSuccess` for each. After try/catch, set `$result.RAM.TotalGB`, `$result.RAM.UsedGB`, `$result.RAM.FreeGB`. Compute `_Status` same pattern as CPU.

4. Windows section — two separate try/catch blocks. First: query `Win32_OperatingSystem` for `$os.Caption` (edition) and `$os.BuildNumber` (build). Initialize `$winEdition`, `$winVersion`, `$winBuild` all to `"Not available"`. Track `$winFields = 3` and `$winSuccess = 0`. If `$os.Caption` non-empty, set `$winEdition = $os.Caption` and increment. If `$os.BuildNumber` non-empty, set `$winBuild = $os.BuildNumber` and increment. Second: query registry `Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue`. If `$reg.UBR` is non-zero and `$winBuild` is not `"Not available"`, set `$winBuild = "$($winBuild).$($reg.UBR)"` and increment `$winSuccess`. If `$reg.DisplayVersion` non-empty, set `$winVersion = $reg.DisplayVersion` and increment; elseif `$reg.ReleaseId` non-empty, set `$winVersion = $reg.ReleaseId` and increment. After both try/catch blocks, set `$result.Windows.Edition`, `$result.Windows.Version`, `$result.Windows.Build`. Compute `_Status` same pattern.

5. Return `$result` at the end of the function.

The here-string must be a single `@'...'@` block. The function body uses 4-space indentation matching the `$Helpers` style. No fenced code blocks — the here-string is a PowerShell construct, not a markdown code block.
</action>
<acceptance_criteria>
- Akari.ps1 contains a `$GetSpecsFunc = @'` here-string constant
- The here-string contains `function Get-Specs {`
- The function initializes `$result` with three groups: `CPU`, `RAM`, `Windows`, each with `_Status = 'OK'`
- CPU section queries `Win32_Processor` with `-ErrorAction Stop` and `Select-Object -First 1`
- CPU section uses `.Trim()` on `$cpu.Name`
- CPU section checks `-gt 0` for numeric fields
- RAM section queries `Win32_OperatingSystem` with `-ErrorAction Stop`
- RAM section divides by `1MB` (not `1GB`) for GB conversion
- RAM section uses `[math]::Round(..., 1)` for one decimal place
- Windows section queries `Win32_OperatingSystem` for Caption and BuildNumber
- Windows section queries registry `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` for UBR and DisplayVersion
- Windows section composes full build as `"$($winBuild).$($reg.UBR)"` when UBR is available
- Each section has its own try/catch block
- Failed fields are the string `"Not available"` (not `$null`)
- `_Status` is computed per group based on success count vs total fields
- The function ends with `return $result`
</acceptance_criteria>
</task>

<task id="1.4" type="execute" wave="1">
<title>Modify DispatcherTimer tick to capture result</title>
<read_first>
- Akari.ps1 (lines 237-256 — current DispatcherTimer tick)
- .planning/phases/01-spec-query-engine/01-RESEARCH.md (section 2.3 — modified DispatcherTimer completion handler)
- .planning/phases/01-spec-query-engine/01-PATTERNS.md (section 2.3 — DispatcherTimer + Show-Page completion patterns)
</read_first>
<action>
Modify the DispatcherTimer tick at Akari.ps1 lines 237-256. In the `if ($j -and $j.Handle.IsCompleted)` block, replace the single `try { [void]$j.Ps.EndInvoke($j.Handle) } catch { ... }` with a conditional: `if ($j.ResultVar) { $result = $j.Ps.EndInvoke($j.Handle); if ($result -and $result.Count -gt 0) { $script:SpecData = $result[$result.Count - 1] } else { $script:SpecData = $null } } else { [void]$j.Ps.EndInvoke($j.Handle) }`. The `EndInvoke` call in result-capturing mode returns the collected objects from the `PSDataCollection`; the last object is the return value (the hashtable). The existing error stream draining (`foreach ($err in $j.Ps.Streams.Error)`), log queue draining, disposal, Meta state saving, `Set-Busy $false`, `Read-Svc`, and `Show-Page` calls are all preserved unchanged. The `try/catch` around the entire completion block is preserved.
</action>
<acceptance_criteria>
- The DispatcherTimer tick contains `if ($j.ResultVar)` conditional
- Result-capturing mode calls `$j.Ps.EndInvoke($j.Handle)` and stores result in `$script:SpecData`
- Standard mode calls `[void]$j.Ps.EndInvoke($j.Handle)` (existing behavior)
- `$script:SpecData` is set to `$result[$result.Count - 1]` when result collection is non-empty
- `$script:SpecData` is set to `$null` when result collection is empty
- `Show-Page` is still called after result capture (line 253 equivalent)
- `Set-Busy $false` is still called
- `Read-Svc` is still called
- Error stream draining (`$j.Ps.Streams.Error`) is preserved
- Log queue draining before and after EndInvoke is preserved
</acceptance_criteria>
</task>

## Verification

### Manual Verification Steps

1. **Invoke-Code extension**: Run `powershell -ExecutionPolicy Bypass -File Akari.ps1` and verify the app launches without errors. Check that existing tweaks (row buttons) still work — they use `Invoke-Code` without `-Result` and must function identically.

2. **Get-Specs function**: The function is defined as a here-string constant. Verify it is syntactically valid by checking that the app parses Akari.ps1 without syntax errors (the here-string is parsed at script load time).

3. **Result capture**: The DispatcherTimer modification is exercised when any `Invoke-Code` call completes. Verify that existing tweak executions still complete and log "Done: <label>" messages.

4. **Spec data structure**: Phase 3 will consume `$script:SpecData`. The structure is verified by the acceptance criteria for task 1.3 — the hashtable has the correct keys, field names, and fallback values.

### Automated Verification

```powershell
# Syntax check: parse Akari.ps1 without executing
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile("$PWD\Akari.ps1", [ref]$null, [ref]$errors)
if ($errors.Count -eq 0) { Write-Host "PASS: No syntax errors" } else { Write-Host "FAIL: $($errors.Count) syntax errors"; $errors | ForEach-Object { Write-Host $_.ToString() } }
```

### Integration Verification (Phase 3 will execute this)

```powershell
# This command will be run by Phase 3 to verify the data layer end-to-end:
# 1. Set $script:Cat = 'Home'
# 2. Call Invoke-Code ($GetSpecsFunc + "`nGet-Specs") "Refreshing system specs..." $null "SpecData"
# 3. Wait for $script:Job to complete
# 4. Verify $script:SpecData is a hashtable with CPU, RAM, Windows keys
# 5. Verify each group has _Status and the expected fields
```

## Success Criteria

| Criterion | Verification |
|-----------|-------------|
| `Invoke-Code` accepts `-Result` parameter | Source assertion: function signature contains `[string]$ResultVar = $null` |
| Existing `Invoke-Code` callers work unchanged | Behavior: row buttons, Set-Prio, Set-Svc all function identically |
| `$script:SpecData` declared | Source assertion: `$script:SpecData = $null` exists in script-scope declarations |
| `Get-Specs` returns grouped hashtable | Source assertion: function body contains `return $result` with CPU/RAM/Windows groups |
| CPU fields: Model, Cores, Threads, SpeedMHz | Source assertion: `$result.CPU.Model`, `$result.CPU.Cores`, `$result.CPU.Threads`, `$result.CPU.SpeedMHz` |
| RAM fields: TotalGB, UsedGB, FreeGB | Source assertion: `$result.RAM.TotalGB`, `$result.RAM.UsedGB`, `$result.RAM.FreeGB` |
| Windows fields: Edition, Version, Build | Source assertion: `$result.Windows.Edition`, `$result.Windows.Version`, `$result.Windows.Build` |
| Per-field fallback to "Not available" | Source assertion: local variables initialized to `"Not available"` before try/catch |
| _Status computed per group | Source assertion: `_Status` set to `'Failed'`, `'Partial'`, or `'OK'` based on success count |
| DispatcherTimer captures result | Source assertion: `if ($j.ResultVar)` conditional with `$script:SpecData` assignment |
| Show-Page called after capture | Source assertion: `Show-Page` still called after result capture in timer tick |
| No new files created | Filesystem assertion: only `Akari.ps1` is modified |

## Threat Model

### ASVS L1 Threats

| Threat | Severity | Mitigation |
|--------|----------|------------|
| **T1: Runspace code injection via -Result parameter** | Low | The `-Result` parameter accepts a variable name (string), not code. The `PSDataCollection` is created server-side. No user input reaches the runspace code string. The `Get-Specs` function is a constant here-string, not dynamically constructed from user input. |
| **T2: CIM query failure causing UI thread block** | Low | CIM queries run in the background runspace via `Invoke-Code`. The UI thread is never blocked. The `$script:Busy` guard prevents concurrent execution. Per-field try/catch ensures partial failures don't crash the runspace. |
| **T3: Registry read failure for UBR** | Low | Registry read uses `-ErrorAction SilentlyContinue`. If the key is missing, `$reg` is `$null` and the UBR field stays `"Not available"`. The Windows group `_Status` reflects the partial failure. |
| **T4: MaxClockSpeed null on VMs/OEM systems** | Low | Per-field check `if ($cpu.MaxClockSpeed -gt 0)` — null/0 values are caught and the field stays `"Not available"`. CPU group `_Status` becomes `'Partial'`. |
| **T5: Win32_OperatingSystem unit confusion (KB vs bytes)** | Low | RAM section explicitly divides by `1MB` (1,048,576) not `1GB`. The `[math]::Round(..., 1)` ensures consistent decimal precision. |
| **T6: Thread safety of $script:SpecData** | Low | `$script:SpecData` is set on the UI thread (in DispatcherTimer tick) and read on the UI thread (in Show-Page). No cross-thread access. The `PSDataCollection` is synchronized by .NET. |
| **T7: Hashtable key collision with _Status** | Low | `_Status` is a reserved key. The field names (Model, Cores, Threads, SpeedMHz, TotalGB, UsedGB, FreeGB, Edition, Version, Build) do not collide with `_Status`. |

### Blocking Threats

None. All threats are Low severity. No High or Medium severity threats identified for this data-layer phase.

## Dependencies

- **Phase 1 depends on**: Nothing (first phase)
- **Phase 1 is consumed by**: Phase 3 (Home Shell & Live Refresh) reads `$script:SpecData` in `Show-Page`

## Notes

- The `Get-Specs` function is NOT called during Phase 1 — it is only defined and the infrastructure to call it is built. Phase 3 will invoke it via `Invoke-Code` when the Home page is shown.
- The `-Result` parameter is a general-purpose extension — future phases can use it for any runspace code that needs to return structured data.
- The `$GetSpecsFunc` here-string is placed after `$Helpers` and before the window XAML parsing, matching the existing code organization.
