# Phase 1: Spec Query Engine — Research

**Date:** 2026-10-08
**Purpose:** Answer "What do I need to know to PLAN this phase well?"
**Scope:** CIM/WMI query patterns, Invoke-Code extension, fallback strategies, runspace result capture, hashtable grouping

---

## 1. CIM/WMI Query Patterns for System Specs

### 1.1 CPU Specs — `Win32_Processor`

**Class:** `Win32_Processor` (namespace `root/CIMV2`)

**Key properties for Phase 1:**

| Property | Type | Notes |
|----------|------|-------|
| `Name` | string | Full CPU model string (e.g., "Intel(R) Core(TM) i7-12700K CPU @ 3.60GHz"). May contain extra whitespace — trim it. |
| `NumberOfCores` | uint32 | Physical cores. Reliable on all modern CPUs. |
| `NumberOfLogicalProcessors` | uint32 | Threads (includes hyperthreading/SMT). Reliable on all modern CPUs. |
| `MaxClockSpeed` | uint32 | Max boost/base clock in MHz from SMBIOS. May be NULL on some OEM systems or VMs. |
| `Manufacturer` | string | "GenuineIntel", "AuthenticAMD", etc. Useful for branding. |
| `SocketDesignation` | string | e.g., "LGA1700". May be NULL on some systems. |

**Query pattern:**
```powershell
$cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
```

**Why `Select-Object -First 1`:** Decision D-08. Covers 99%+ of consumer systems (single-socket). Multi-CPU aggregation is out of scope.

**Known issues:**
- `MaxClockSpeed` can be NULL on VMs, some OEM systems, or when SMBIOS data is incomplete. Must handle null → "Not available".
- `Name` may have trailing spaces or extra whitespace. Use `.Trim()`.
- On ARM64 systems, `NumberOfCores` may report 0 or be unreliable. Fallback to `NumberOfLogicalProcessors` if cores is 0.

**Fallback strategy per field (D-09):**
```powershell
$cpuModel = "Not available"
$cpuCores = "Not available"
$cpuThreads = "Not available"
$cpuSpeedMHz = "Not available"

try {
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
    if ($cpu) {
        if ($cpu.Name) { $cpuModel = $cpu.Name.Trim() }
        if ($cpu.NumberOfCores -gt 0) { $cpuCores = $cpu.NumberOfCores }
        elseif ($cpu.NumberOfLogicalProcessors -gt 0) { $cpuCores = $cpu.NumberOfLogicalProcessors }
        if ($cpu.NumberOfLogicalProcessors -gt 0) { $cpuThreads = $cpu.NumberOfLogicalProcessors }
        if ($cpu.MaxClockSpeed -gt 0) { $cpuSpeedMHz = $cpu.MaxClockSpeed }
    }
} catch {
    # Entire query failed — all fields stay "Not available" (D-10)
}
```

### 1.2 RAM Specs — `Win32_OperatingSystem` (primary) + `Win32_PhysicalMemory` (detail)

**Decision D-03:** Use `Win32_OperatingSystem` for total/free in a single query. Compute used as the difference. Matches Task Manager values.

**Class:** `Win32_OperatingSystem`

**Key properties:**

| Property | Type | Unit | Notes |
|----------|------|------|-------|
| `TotalVisibleMemorySize` | uint64 | KB | Total physical RAM visible to OS. Slightly less than installed (hardware reserved). |
| `FreePhysicalMemory` | uint64 | KB | Currently free physical RAM. |
| `TotalVirtualMemorySize` | uint64 | KB | Total virtual memory (pagefile + physical). Not needed for Phase 1. |
| `FreeVirtualMemory` | uint64 | KB | Free virtual memory. Not needed for Phase 1. |

**Query pattern:**
```powershell
$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
$totalKB = $os.TotalVisibleMemorySize
$freeKB = $os.FreePhysicalMemory
$usedKB = $totalKB - $freeKB
$totalGB = [math]::Round($totalKB / 1MB, 1)
$usedGB = [math]::Round($usedKB / 1MB, 1)
$freeGB = [math]::Round($freeKB / 1MB, 1)
```

**Unit conversion:** `TotalVisibleMemorySize` and `FreePhysicalMemory` are in **kilobytes** (KB). Divide by `1MB` (1,048,576) to get GB. This is a common gotcha — many scripts mistakenly treat these as bytes.

**Alternative: `Win32_PhysicalMemory`** (for per-DIMM detail, Phase 2+):
```powershell
$dimms = Get-CimInstance -ClassName Win32_PhysicalMemory
# Capacity is in bytes (uint64)
# Speed is in MHz (uint32) — may be 0 on some systems
# SMBIOSMemoryType is a uint32 code (e.g., 26 = DDR4, 34 = DDR5)
```

**Why `Win32_OperatingSystem` for Phase 1:**
- Single query gets total + free
- Matches Task Manager's "In use" / "Available" values exactly
- `Win32_PhysicalMemory` gives installed RAM (including hardware-reserved), which differs from what Task Manager shows
- Phase 1 success criterion says "total RAM and used/free amounts computed from PhysicalMemory sum" — but D-03 says "agent discretion" and `Win32_OperatingSystem` is the more reliable single-query approach that matches user expectations

**Fallback strategy:**
```powershell
$ramTotalGB = "Not available"
$ramUsedGB = "Not available"
$ramFreeGB = "Not available"

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os -and $os.TotalVisibleMemorySize -gt 0) {
        $totalKB = $os.TotalVisibleMemorySize
        $freeKB = $os.FreePhysicalMemory
        $usedKB = $totalKB - $freeKB
        $ramTotalGB = [math]::Round($totalKB / 1MB, 1)
        $ramUsedGB = [math]::Round($usedKB / 1MB, 1)
        $ramFreeGB = [math]::Round($freeKB / 1MB, 1)
    }
} catch {
    # Query failed — all fields stay "Not available"
}
```

### 1.3 Windows Version Specs — `Win32_OperatingSystem` + Registry

**Decision D-06:** CIM for edition/caption/build; registry for UBR only.

**From `Win32_OperatingSystem`:**

| Property | Type | Notes |
|----------|------|-------|
| `Caption` | string | Full OS name (e.g., "Microsoft Windows 11 Pro"). Reliable. |
| `Version` | string | Version number (e.g., "10.0.22631"). Does NOT include UBR. |
| `BuildNumber` | string | Build number (e.g., "22631"). Does NOT include UBR. |
| `OSArchitecture` | string | "64-bit" or "32-bit". |

**From Registry `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion`:**

| Value | Type | Notes |
|-------|------|-------|
| `UBR` | DWORD | Update Build Revision (e.g., 1234). The missing piece for full build number. |
| `ProductName` | string | e.g., "Windows 11 Pro". More reliable than Caption for edition. |
| `DisplayVersion` | string | e.g., "23H2". Friendly version name (Windows 10 20H2+). |
| `ReleaseId` | string | e.g., "22H2". Older friendly version (pre-20H2). |
| `CurrentBuild` | string | Build number (same as BuildNumber from CIM). |
| `EditionID` | string | e.g., "Professional". Short edition name. |

**Query pattern:**
```powershell
# CIM for edition + build
$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
$edition = $os.Caption
$build = $os.BuildNumber

# Registry for UBR + friendly version
$reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
$ubr = $reg.UBR
$displayVersion = $reg.DisplayVersion
if (-not $displayVersion) { $displayVersion = $reg.ReleaseId }

# Compose full build number
$fullBuild = "$build.$ubr"
```

**Full build number composition:** `"$($os.BuildNumber).$($reg.UBR)"` → e.g., "22631.1234". This is the format shown in `winver.exe`.

**Edition extraction:** `Caption` gives "Microsoft Windows 11 Pro". For a cleaner edition string, use `ProductName` from registry (e.g., "Windows 11 Pro") or `EditionID` (e.g., "Professional"). Agent discretion on exact field name.

**Fallback strategy:**
```powershell
$winEdition = "Not available"
$winVersion = "Not available"
$winBuild = "Not available"

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($os) {
        if ($os.Caption) { $winEdition = $os.Caption }
        if ($os.BuildNumber) { $winBuild = $os.BuildNumber }
    }
} catch { }

try {
    $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    if ($reg) {
        if ($reg.UBR -and $winBuild -ne "Not available") { $winBuild = "$($winBuild).$($reg.UBR)" }
        if ($reg.DisplayVersion) { $winVersion = $reg.DisplayVersion }
        elseif ($reg.ReleaseId) { $winVersion = $reg.ReleaseId }
    }
} catch { }
```

---

## 2. Extending `Invoke-Code` with `-Result` Parameter

### 2.1 Current `Invoke-Code` (Akari.ps1:223-235)

```powershell
function Invoke-Code([string]$code, [string]$label, $meta = $null) {
    if ($script:Busy) { return }
    Set-Busy $true
    Add-Log $label
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('LogQueue', $script:Queue)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $wrapped = $Helpers + "`ntry {`n& {`n" + $code + "`n} *>&1 | Out-String -Stream | ForEach-Object { if (`$_.Trim()) { Write-Log `$_ } }`n} catch { Write-Log ('Error: ' + `$_.Exception.Message) }"
    [void]$ps.AddScript($wrapped)
    $script:Job = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke(); Label = $label; Meta = $meta }
}
```

**Key observations:**
- The code is wrapped in `try { & { ... } *>&1 | Out-String -Stream | ... }` — all output is captured as strings and sent to the log queue.
- The runspace has access to `$LogQueue` (set via `SessionStateProxy.SetVariable`).
- `$script:Job` holds the PowerShell instance, runspace, async handle, label, and meta.
- The DispatcherTimer (line 237-256) checks `$j.Handle.IsCompleted` and calls `EndInvoke`.

### 2.2 The Problem

The current wrapper captures ALL output as strings via `*>&1 | Out-String -Stream`. This means:
- Return values from the scriptblock are stringified and sent to the log.
- There is no way to get a structured object (hashtable) back to the UI thread.

### 2.3 Solution: `-Result` Parameter Pattern (D-13, D-14)

**Approach:** Add a `-Result` parameter that names a script-scope variable. The wrapper captures the return value into a `PSDataCollection` and sets the script-scope variable on completion.

**Modified `Invoke-Code`:**

```powershell
function Invoke-Code([string]$code, [string]$label, $meta = $null, [string]$ResultVar = $null) {
    if ($script:Busy) { return }
    Set-Busy $true
    Add-Log $label
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('LogQueue', $script:Queue)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    
    if ($ResultVar) {
        # Result-capturing mode: output goes to log, return value goes to $ResultVar
        $resultCollection = [System.Management.Automation.PSDataCollection[object]]::new()
        $wrapped = $Helpers + "`ntry {`n`$__result = & {`n" + $code + "`n}`n`$__result`n} catch { Write-Log ('Error: ' + `$_.Exception.Message); `$__result = `$null }"
        [void]$ps.AddScript($wrapped)
        $script:Job = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke($null, $resultCollection); Label = $label; Meta = $meta; ResultVar = $ResultVar; ResultCollection = $resultCollection }
    } else {
        # Standard mode: all output to log (existing behavior)
        $wrapped = $Helpers + "`ntry {`n& {`n" + $code + "`n} *>&1 | Out-String -Stream | ForEach-Object { if (`$_.Trim()) { Write-Log `$_ } }`n} catch { Write-Log ('Error: ' + `$_.Exception.Message) }"
        [void]$ps.AddScript($wrapped)
        $script:Job = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke(); Label = $label; Meta = $meta }
    }
}
```

**Modified DispatcherTimer completion handler:**

```powershell
$timer.Add_Tick({
    $m = $null
    while ($script:Queue.TryDequeue([ref]$m)) { Add-Log $m }
    $j = $script:Job
    if ($j -and $j.Handle.IsCompleted) {
        try {
            if ($j.ResultVar) {
                # Result-capturing mode: extract return value
                $result = $j.Ps.EndInvoke($j.Handle)
                if ($result -and $result.Count -gt 0) {
                    $script:SpecData = $result[$result.Count - 1]
                } else {
                    $script:SpecData = $null
                }
            } else {
                [void]$j.Ps.EndInvoke($j.Handle)
            }
        } catch { Add-Log "Error: $($_.Exception.Message)" }
        foreach ($err in $j.Ps.Streams.Error) { Add-Log "Error: $($err.ToString())" }
        while ($script:Queue.TryDequeue([ref]$m)) { Add-Log $m }
        $j.Ps.Dispose(); $j.Rs.Dispose()
        if ($j.Meta) { $script:State[$j.Meta.Id] = ($j.Meta.Kind -eq 'Apply'); Save-State }
        Add-Log "Done: $($j.Label)"
        $script:Job = $null
        Set-Busy $false
        Read-Svc
        Show-Page
    }
})
```

**How it works:**
1. `BeginInvoke($null, $resultCollection)` — the second parameter is an output buffer that collects return values.
2. The scriptblock assigns its result to `$__result` and then outputs it as the last pipeline object.
3. `EndInvoke($j.Handle)` returns the collected objects from `$resultCollection`.
4. The last object in the collection is the return value (the hashtable).
5. It's stored in `$script:SpecData` (or any script-scope variable name passed via `-ResultVar`).

**Alternative simpler approach** (if the above is too invasive):

Use a `PSDataCollection` directly without modifying `Invoke-Code`'s signature:

```powershell
# In the calling code:
$script:SpecData = $null
$resultCollection = [System.Management.Automation.PSDataCollection[object]]::new()
$rs = [runspacefactory]::CreateRunspace()
$rs.Open()
$rs.SessionStateProxy.SetVariable('LogQueue', $script:Queue)
$ps = [powershell]::Create()
$ps.Runspace = $rs
$wrapped = $Helpers + "`ntry {`n`$__result = & {`n" + $code + "`n}`n`$__result`n} catch { Write-Log ('Error: ' + `$_.Exception.Message); `$__result = `$null }"
[void]$ps.AddScript($wrapped)
$handle = $ps.BeginInvoke($null, $resultCollection)
# ... later, when $handle.IsCompleted:
$result = $ps.EndInvoke($handle)
$script:SpecData = $result[$result.Count - 1]
```

**Recommendation:** The `-Result` parameter approach (D-13) is cleaner and matches the decision. It keeps the runspace lifecycle management inside `Invoke-Code` and the DispatcherTimer, rather than duplicating it in `Get-Specs`.

### 2.4 Threading Considerations

- `BeginInvoke($null, $resultCollection)` is thread-safe — the `PSDataCollection` is synchronized.
- The DispatcherTimer tick runs on the UI thread, so setting `$script:SpecData` there is safe.
- `EndInvoke` must be called exactly once, and it blocks until the async operation completes (which it already is, since we checked `IsCompleted`).
- The `$resultCollection` is disposed when the PowerShell instance is disposed (in the timer tick).

---

## 3. Per-Field Fallback Strategies

### 3.1 Decision Summary

| Decision | Choice |
|----------|--------|
| D-09 | Per-field try/catch — each field gets its own try/catch |
| D-10 | Complete query failure → all fields in that group show "Not available" |
| D-11 | Display text for failed fields: `"Not available"` |
| D-12 | Status values: `'OK'`, `'Partial'`, `'Failed'` |

### 3.2 Status Computation Pattern

```powershell
function Get-Specs {
    $result = @{
        CPU = @{ _Status = 'OK' }
        RAM = @{ _Status = 'OK' }
        Windows = @{ _Status = 'OK' }
    }
    
    # --- CPU ---
    $cpuFields = 0
    $cpuSuccess = 0
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu) {
            $cpuFields = 4
            if ($cpu.Name) { $result.CPU.Model = $cpu.Name.Trim(); $cpuSuccess++ }
            if ($cpu.NumberOfCores -gt 0) { $result.CPU.Cores = $cpu.NumberOfCores; $cpuSuccess++ }
            elseif ($cpu.NumberOfLogicalProcessors -gt 0) { $result.CPU.Cores = $cpu.NumberOfLogicalProcessors; $cpuSuccess++ }
            if ($cpu.NumberOfLogicalProcessors -gt 0) { $result.CPU.Threads = $cpu.NumberOfLogicalProcessors; $cpuSuccess++ }
            if ($cpu.MaxClockSpeed -gt 0) { $result.CPU.SpeedMHz = $cpu.MaxClockSpeed; $cpuSuccess++ }
        }
    } catch { $cpuFields = 4 }
    
    if ($cpuSuccess -eq 0 -and $cpuFields -gt 0) { $result.CPU._Status = 'Failed' }
    elseif ($cpuSuccess -lt $cpuFields) { $result.CPU._Status = 'Partial' }
    
    # --- RAM ---
    # ... similar pattern ...
    
    # --- Windows ---
    # ... similar pattern ...
    
    return $result
}
```

### 3.3 Null/Empty Handling

CIM properties can be:
- `$null` — property not supported on this system
- `0` — property exists but value is zero (e.g., `MaxClockSpeed = 0` on some VMs)
- Empty string — property exists but no data

**Pattern for each field:**
```powershell
# For strings:
if (-not [string]::IsNullOrWhiteSpace($value)) { $result.Field = $value }

# For numbers:
if ($value -gt 0) { $result.Field = $value }
```

### 3.4 SMBIOS Filler Strings (Phase 2 relevance)

Some OEM systems return filler strings like:
- `"To Be Filled By O.E.M."`
- `"Default string"`
- `"None"`
- `"N/A"`

These should be treated as "Not available" in Phase 2. For Phase 1, the main concern is CPU `Name` which is generally reliable.

---

## 4. DispatcherTimer + Show-Page Completion Pattern

### 4.1 Current Flow (Akari.ps1:237-256)

```
DispatcherTimer tick (every 150ms)
  ├── Drain log queue → Add-Log
  ├── Check $script:Job.Handle.IsCompleted
  │   ├── If completed:
  │   │   ├── EndInvoke (get output)
  │   │   ├── Drain error stream
  │   │   ├── Drain remaining log queue
  │   │   ├── Dispose PowerShell + Runspace
  │   │   ├── If Meta: persist toggle state
  │   │   ├── Log "Done: <label>"
  │   │   ├── $script:Job = $null
  │   │   ├── Set-Busy $false
  │   │   ├── Read-Svc (refresh SvcHost display)
  │   │   └── Show-Page (re-render current page)
  └── If not completed: do nothing
```

### 4.2 How Phase 1 Integrates

**Decision D-15:** Completion detection in `Show-Page` — the DispatcherTimer already calls `Show-Page` on job completion. Phase 3 reads the script-scope variable in `Show-Page`.

**For Phase 1 (data layer only):**
1. `Get-Specs` is called via `Invoke-Code` with `-ResultVar 'SpecData'`.
2. The runspace executes `Get-Specs` and returns the hashtable.
3. The DispatcherTimer captures the result into `$script:SpecData`.
4. `Show-Page` is called (existing behavior — re-renders the current page).
5. Phase 3 will read `$script:SpecData` in `Show-Page` to render the Home page.

**Phase 1 deliverable:** The `Get-Specs` function + the `-Result` parameter extension. Phase 3 consumes `$script:SpecData`.

### 4.3 Calling Get-Specs

```powershell
# In Show-Page or a new Show-Home function (Phase 3):
if ($script:Cat -eq 'Home') {
    $script:SpecData = $null  # Clear previous data
    Invoke-Code (Get-Command Get-Specs).ScriptBlock.ToString() "Refreshing system specs..." $null "SpecData"
}
```

**Note:** `Get-Specs` must be defined in the runspace. Since `Invoke-Code` prepends `$Helpers`, and `Get-Specs` is a script-scope function, it needs to be either:
- Defined inside the runspace code string, OR
- Passed as part of the `$Helpers` preamble, OR
- Defined in a dot-sourced file that's available in the runspace

**Best approach:** Define `Get-Specs` as a string constant (like `$Helpers`) and prepend it to the code when calling `Invoke-Code`:

```powershell
$GetSpecsFunc = @'
function Get-Specs {
    # ... full function body ...
    return $result
}
'@

Invoke-Code ($GetSpecsFunc + "`nGet-Specs") "Refreshing system specs..." $null "SpecData"
```

This keeps the function definition self-contained and doesn't require modifying the runspace setup.

---

## 5. Best Practices for Grouping Spec Data into Hashtables

### 5.1 Decision D-01: Grouped Hashtable Structure

```powershell
@{
    CPU = @{
        _Status = 'OK'
        Model = 'Intel(R) Core(TM) i7-12700K CPU @ 3.60GHz'
        Cores = 12
        Threads = 20
        SpeedMHz = 3600
    }
    RAM = @{
        _Status = 'OK'
        TotalGB = 32.0
        UsedGB = 14.2
        FreeGB = 17.8
    }
    Windows = @{
        _Status = 'OK'
        Edition = 'Microsoft Windows 11 Pro'
        Version = '23H2'
        Build = '22631.1234'
    }
}
```

### 5.2 PowerShell 5.1 Hashtable Best Practices

1. **Use `@{}` literal syntax** — fastest and most readable in PS 5.1.
2. **Key order is not guaranteed** — hashtables are unordered. If order matters for display, use `[ordered]` or sort keys when iterating.
3. **Nested hashtables** — fully supported. Access via `$result.CPU.Model`.
4. **Adding keys dynamically** — `$result.CPU.NewKey = 'value'` works fine.
5. **Checking key existence** — `$result.CPU.ContainsKey('Model')` or `$result.CPU.Model -ne $null`.

### 5.3 `[ordered]` Consideration

If Phase 3 needs consistent key ordering for display:
```powershell
$cpu = [ordered]@{
    _Status = 'OK'
    Model = '...'
    Cores = 8
    Threads = 16
    SpeedMHz = 3600
}
```

**Trade-off:** `[ordered]` dictionaries are slightly slower to create and access. For a one-time spec query, this is negligible. **Recommendation:** Use `[ordered]` for the top-level groups (CPU, RAM, Windows) so Phase 3 can iterate in a predictable order. Use regular `@{}` within each group.

### 5.4 Type Consistency

- Keep numeric values as `[int]` or `[double]` — don't mix types for the same key across calls.
- `_Status` is always `[string]`.
- Failed fields are `[string]` ("Not available"), not `$null` — this simplifies Phase 3 display logic (no null checks needed).

### 5.5 Returning from the Runspace

The hashtable is returned as a single object. In the runspace:
```powershell
function Get-Specs {
    $result = @{ ... }
    return $result
}
```

The `return` keyword in PowerShell outputs the object to the pipeline. Since `Invoke-Code` captures the pipeline output, the hashtable becomes the return value.

**Important:** In PowerShell, `return $result` and just `$result` on the last line are equivalent — both output to the pipeline. But `return` is more explicit and matches the codebase style.

---

## 6. Summary: What You Need to Know to Plan

### 6.1 Technical Feasibility

| Concern | Status | Notes |
|---------|--------|-------|
| CIM queries for CPU/RAM/Windows | ✅ Well-documented | Standard `Get-CimInstance` pattern |
| Registry for UBR | ✅ Well-documented | `Get-ItemProperty` on `HKLM:\...\CurrentVersion` |
| Extending Invoke-Code with -Result | ✅ Feasible | `BeginInvoke($null, $collection)` + `EndInvoke` |
| Capturing result in DispatcherTimer | ✅ Feasible | Set `$script:SpecData` in timer tick |
| Per-field fallback | ✅ Feasible | try/catch per field, track success count |
| Hashtable return from runspace | ✅ Feasible | Standard PowerShell pipeline behavior |

### 6.2 Key Risks

1. **`MaxClockSpeed` null on VMs/OEM** — handled by per-field fallback
2. **`Win32_OperatingSystem` unit confusion** — KB vs bytes; must divide by 1MB for GB
3. **Runspace result capture complexity** — the `-Result` parameter adds branching to `Invoke-Code`; must preserve existing behavior for non-result calls
4. **Thread safety** — `$script:SpecData` is set on UI thread (in timer tick), read on UI thread (in Show-Page) — no cross-thread issue
5. **`Get-Specs` function availability in runspace** — must be passed as code string or defined in `$Helpers`

### 6.3 Planning Checklist

- [ ] Define exact field names for each group (CPU, RAM, Windows)
- [ ] Decide on `[ordered]` vs regular `@{}` for top-level groups
- [ ] Design the `-Result` parameter signature for `Invoke-Code`
- [ ] Design the DispatcherTimer modification for result capture
- [ ] Define the `Get-Specs` function body with per-field fallback
- [ ] Decide how `Get-Specs` gets into the runspace (code string vs $Helpers)
- [ ] Plan the `_Status` computation logic
- [ ] Define the "Not available" fallback for each field type
- [ ] Plan integration with Show-Page (Phase 3 reads `$script:SpecData`)

### 6.4 Files to Modify

| File | Change |
|------|--------|
| `Akari.ps1` | Add `-Result` parameter to `Invoke-Code`; modify DispatcherTimer tick to capture result; add `$GetSpecsFunc` string constant; add `$script:SpecData` variable declaration |

### 6.5 Files to Create

| File | Purpose |
|------|---------|
| (none for Phase 1) | `Get-Specs` is defined as a code string in `Akari.ps1`, not a separate file |

---

*Research completed: 2026-10-08*
