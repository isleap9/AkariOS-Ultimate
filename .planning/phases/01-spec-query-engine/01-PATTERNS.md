# Phase 1: Spec Query Engine — Pattern Mapping

**Date:** 2026-10-08
**Purpose:** Map each file to be created/modified to its role, data flow, and closest existing analog in the codebase, with concrete code excerpts.

---

## 1. Files to Create/Modify

| File | Action | Role | Data Flow |
|------|--------|------|-----------|
| `Akari.ps1` | **Modify** | Host script — extend `Invoke-Code` with `-Result` param, modify DispatcherTimer tick to capture result, add `$GetSpecsFunc` string constant, add `$script:SpecData` variable | UI thread → runspace (send code) → runspace → UI thread (receive hashtable via `$script:SpecData`) |
| *(none)* | — | `Get-Specs` is defined as a code string inside `Akari.ps1`, not a separate file | — |

**Summary:** Only one file is modified. No new files are created. The `Get-Specs` function lives as a here-string constant (`$GetSpecsFunc`) in `Akari.ps1`, prepended to the runspace code when invoked.

---

## 2. Pattern Mapping

### 2.1 CIM Query Patterns (`Get-CimInstance` usage)

**Role in Phase 1:** Query `Win32_Processor`, `Win32_OperatingSystem`, and `Win32_ComputerSystem` for CPU, RAM, and Windows specs.

**Closest analog: `Get-RamKB` — `Akari.ps1:348`**

```powershell
function Get-RamKB { [math]::Ceiling((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) * 1048576 }
```

- Single-line CIM query, no error handling (relies on the caller's context).
- Uses `Get-CimInstance` with class name as positional parameter.
- Returns a computed value.

**Second analog: `Run-Trusted` CIM query — `Akari.ps1:88`**

```powershell
$service = Get-CimInstance -ClassName Win32_Service -Filter "Name='TrustedInstaller'"
$DefaultBinPath = $service.PathName
```

- Uses `-ClassName` and `-Filter` parameters explicitly.
- Accesses a property on the returned object.

**Third analog: `Tweaks/Check.ps1:11` — BIOS check**

```powershell
$instanceID = (Get-CimInstance Win32_BaseBoard).Product
```

- Same positional class-name pattern as `Get-RamKB`.
- Property access via dot notation.

**Pattern to follow for `Get-Specs`:**

```powershell
# Simple query, first instance:
$cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1

# With filter (if needed):
$service = Get-CimInstance -ClassName Win32_Service -Filter "Name='TrustedInstaller'"
```

**Key conventions:**
- Use `-ClassName` and `-Filter` for clarity (matches `Run-Trusted` style).
- Use `-ErrorAction Stop` inside try/catch blocks for per-field fallback (D-09).
- Pipe to `Select-Object -First 1` for single-instance classes (D-08).
- Access properties via dot notation; `.Trim()` string values that may have trailing whitespace.

---

### 2.2 Invoke-Code Runspace Execution Patterns

**Role in Phase 1:** Extend `Invoke-Code` with a `-Result` parameter that captures the return value into a script-scope variable, reusing the existing runspace + DispatcherTimer infrastructure.

**Closest analog: `Invoke-Code` itself — `Akari.ps1:223-235`**

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

**Callers (how `Invoke-Code` is invoked):**

`Set-Prio` — `Akari.ps1:331`:
```powershell
Invoke-Code "Set-Reg '$PrioKey' 'Win32PrioritySeparation' $v`nWrite-Log 'Win32PrioritySeparation = $hex'" "Win32PrioritySeparation: setting $hex"
```

`Set-Svc` — `Akari.ps1:360`:
```powershell
Invoke-Code "Set-Reg '$SvcKey' 'SvcHostSplitThresholdInKB' ([uint32]$v)`nWrite-Log 'SvcHostSplitThresholdInKB = $v (restart to apply)'" "SvcHost split threshold: setting $v KB"
```

**Pattern to follow for `-Result` extension:**

The extension adds a `[string]$ResultVar = $null` parameter. When provided:
1. Create a `PSDataCollection[object]` as the output buffer.
2. Use `BeginInvoke($null, $resultCollection)` instead of `BeginInvoke()`.
3. Wrap the code to assign `$__result` and output it as the last pipeline object.
4. Store `ResultVar` and `ResultCollection` in the `$script:Job` hashtable.
5. In the DispatcherTimer tick, call `EndInvoke` and extract the last object from the collection into the named script-scope variable.

**Key conventions:**
- The `$Helpers` here-string is always prepended to the code.
- The `try { & { ... } *>&1 | Out-String -Stream | ... }` wrapper captures all output as log strings.
- The `-Result` mode changes the wrapper to `$__result = & { ... }; $__result` so the return value is the last pipeline object.
- `$script:Busy` guard prevents concurrent execution — spec queries must respect this.

---

### 2.3 DispatcherTimer + Show-Page Completion Patterns

**Role in Phase 1:** The DispatcherTimer tick is the only cross-thread bridge. It drains the log queue, completes background jobs, and calls `Show-Page`. Phase 1 extends it to capture the result hashtable into `$script:SpecData`.

**Closest analog: DispatcherTimer tick — `Akari.ps1:237-256`**

```powershell
$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    $m = $null
    while ($script:Queue.TryDequeue([ref]$m)) { Add-Log $m }
    $j = $script:Job
    if ($j -and $j.Handle.IsCompleted) {
        try { [void]$j.Ps.EndInvoke($j.Handle) } catch { Add-Log "Error: $($_.Exception.Message)" }
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
$timer.Start()
```

**`Show-Page` — `Akari.ps1:194-218`:**

```powershell
function Show-Page {
    $q = $Search.Text.Trim()
    $Rows.Children.Clear()
    if ($q) {
        $Heading.Text = "Results for `"$q`""
        $list = @($script:Tweaks | Where-Object { "$($_.Name) $($_.Description)" -like "*$q*" })
    } else {
        $Heading.Text = $script:Cat
        $list = @($script:Tweaks | Where-Object { $_.Category -eq $script:Cat })
    }
    $adv = (-not $q -and $script:Cat -eq 'Advanced')
    $Tuner.Visibility = if ($adv) { 'Visible' } else { 'Collapsed' }
    $SvcTuner.Visibility = $Tuner.Visibility
    foreach ($t in $list) {
        if (-not $script:RowCache.ContainsKey($t.Id)) { $script:RowCache[$t.Id] = New-Row $t }
        [void]$Rows.Children.Add($script:RowCache[$t.Id])
        Update-Row $t
    }
    if (-not $list.Count -and -not $adv) {
        $msg = [Windows.Controls.TextBlock]::new()
        $msg.Text = if ($q) { 'No scripts match.' } else { 'Nothing here yet.' }
        $msg.Foreground = $window.FindResource('Mu')
        [void]$Rows.Children.Add($msg)
    }
}
```

**Pattern to follow for result capture:**

In the DispatcherTimer tick, after `EndInvoke`, check if the job has a `ResultVar`:

```powershell
if ($j.ResultVar) {
    $result = $j.Ps.EndInvoke($j.Handle)
    if ($result -and $result.Count -gt 0) {
        $script:SpecData = $result[$result.Count - 1]
    } else {
        $script:SpecData = $null
    }
} else {
    [void]$j.Ps.EndInvoke($j.Handle)
}
```

**Key conventions:**
- The timer tick runs on the UI thread — setting `$script:SpecData` is thread-safe.
- `EndInvoke` is called exactly once; it blocks until completion (already done since `IsCompleted` was checked).
- `Show-Page` is always called last — Phase 3 reads `$script:SpecData` there.
- The `$script:Queue` is drained before and after `EndInvoke` to ensure all log messages are processed.

---

### 2.4 Hashtable-Based State Management

**Role in Phase 1:** The spec data is returned as a grouped hashtable (`@{ CPU = @{...}; RAM = @{...}; Windows = @{...} }`). All shared state in the codebase uses script-scope hashtables.

**Closest analog: `$script:State` — `Akari.ps1:60-63`**

```powershell
$script:State = @{}
if (Test-Path $StatePath) {
    try { (Get-Content $StatePath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:State[$_.Name] = [bool]$_.Value } } catch { }
}
```

- Script-scope hashtable initialized as `@{}`.
- Keys are strings, values are typed (`[bool]`).
- Populated from JSON, but the pattern of key-value storage is the same.

**Second analog: `$script:RowCache` — `Akari.ps1:33`**

```powershell
$script:RowCache   = @{}
```

- Script-scope hashtable, checked with `.ContainsKey()`, accessed by key.

**Third analog: `$script:Job` — `Akari.ps1:234`**

```powershell
$script:Job = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke(); Label = $label; Meta = $meta }
```

- Script-scope hashtable with mixed value types (objects, strings, handles).
- Keys are PascalCase.

**Pattern to follow for `$script:SpecData`:**

```powershell
# Declaration (near other script-scope vars, ~line 37):
$script:SpecData = $null

# In Get-Specs (runspace code string):
$result = @{
    CPU = @{ _Status = 'OK'; Model = '...'; Cores = 8; Threads = 16; SpeedMHz = 3600 }
    RAM = @{ _Status = 'OK'; TotalGB = 16.0; UsedGB = 8.0; FreeGB = 8.0 }
    Windows = @{ _Status = 'OK'; Edition = '...'; Version = '...'; Build = '...' }
}
return $result
```

**Key conventions:**
- Use `@{}` literal syntax for hashtables.
- Use `$script:` prefix for all shared mutable state.
- Keys are PascalCase for top-level groups (`CPU`, `RAM`, `Windows`).
- `_Status` is a reserved key per group — `'OK'`, `'Partial'`, or `'Failed'`.
- Failed fields are `[string]` `"Not available"`, not `$null` — simplifies Phase 3 display logic.
- Use `[ordered]` for top-level groups if Phase 3 needs predictable iteration order.

---

### 2.5 Per-Field Error Handling Patterns

**Role in Phase 1:** Each spec field gets its own try/catch. If CPU model fails but cores succeed, model shows "Not available" but cores show real values (D-09). Complete query failure → all fields in that group show "Not available" (D-10).

**Closest analog: `Get-State` — `Akari.ps1:175-181`**

```powershell
function Get-State($t) {
    if ($t.Detect) {
        try { $r = & $t.Detect; if ($r -is [bool]) { return $r } } catch { }
    }
    if ($script:State.ContainsKey($t.Id)) { return [bool]$script:State[$t.Id] }
    return $null
}
```

- try/catch with empty catch — swallows errors and falls through.
- Returns `$null` on failure (caller decides what to do).

**Second analog: `Tweaks/Check.ps1:57-60` — per-drive try/catch**

```powershell
Get-Volume | Where-Object {$_.DriveLetter} | Sort-Object DriveLetter | ForEach-Object {
    try {
        $percentRemain = ($_.SizeRemaining / $_.Size) * 100
        Write-Host "$($_.DriveLetter): Free space = $($percentRemain.ToString().substring(0,4))%"
    } catch {}
}
```

- Per-item try/catch inside a loop — exactly the per-field pattern needed.
- Empty catch block — suppress and continue.

**Third analog: `-ErrorAction SilentlyContinue` pattern (pervasive in `Tweaks/Windows.ps1`)**

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\..." -ErrorAction SilentlyContinue | Out-Null
```

- Used for destructive/optional operations where failure is acceptable.
- Combined with `| Out-Null` to suppress output.

**Pattern to follow for per-field fallback in `Get-Specs`:**

```powershell
# Initialize all fields to "Not available"
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

**Key conventions:**
- Use `-ErrorAction Stop` inside try/catch to force catch on failure.
- Use `-ErrorAction SilentlyContinue` for optional reads outside try/catch.
- Empty catch blocks are acceptable — the codebase uses them pervasively.
- Track success count per group to compute `_Status`:
  - `$success -eq 0` → `'Failed'`
  - `$success -lt $total` → `'Partial'`
  - `$success -eq $total` → `'OK'`
- Null/empty handling: use `[string]::IsNullOrWhiteSpace()` for strings, `-gt 0` for numbers.

---

## 3. Data Flow Summary

```
UI Thread                          Runspace
─────────                          ─────────
                                   
Get-Specs defined as               
$GetSpecsFunc here-string          
                                   
Invoke-Code $GetSpecsFunc ──────→  Runspace opens
  "Refreshing specs..."              $Helpers prepended
  $null (meta)                       Get-Specs executes:
  "SpecData" (ResultVar)               ├── CIM query (CPU)
                                       ├── CIM query (RAM)
                                       ├── CIM + Registry (Windows)
                                       └── return $result (hashtable)
                                   
DispatcherTimer tick (150ms) ←───── $result output to PSDataCollection
  $j.Handle.IsCompleted              
  $result = $j.Ps.EndInvoke()       
  $script:SpecData = $result[-1]    
  Show-Page()  ← Phase 3 reads $script:SpecData here
```

---

## 4. Concrete Code Excerpts

### 4.1 Current `Invoke-Code` (to be extended) — `Akari.ps1:223-235`

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

### 4.2 Current DispatcherTimer tick (to be extended) — `Akari.ps1:237-256`

```powershell
$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    $m = $null
    while ($script:Queue.TryDequeue([ref]$m)) { Add-Log $m }
    $j = $script:Job
    if ($j -and $j.Handle.IsCompleted) {
        try { [void]$j.Ps.EndInvoke($j.Handle) } catch { Add-Log "Error: $($_.Exception.Message)" }
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
$timer.Start()
```

### 4.3 CIM query analog — `Get-RamKB` at `Akari.ps1:348`

```powershell
function Get-RamKB { [math]::Ceiling((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) * 1048576 }
```

### 4.4 CIM query with filter — `Run-Trusted` at `Akari.ps1:88`

```powershell
$service = Get-CimInstance -ClassName Win32_Service -Filter "Name='TrustedInstaller'"
$DefaultBinPath = $service.PathName
```

### 4.5 Per-item try/catch analog — `Tweaks/Check.ps1:57-60`

```powershell
Get-Volume | Where-Object {$_.DriveLetter} | Sort-Object DriveLetter | ForEach-Object {
    try {
        $percentRemain = ($_.SizeRemaining / $_.Size) * 100
        Write-Host "$($_.DriveLetter): Free space = $($percentRemain.ToString().substring(0,4))%"
    } catch {}
}
```

### 4.6 Script-scope hashtable state — `Akari.ps1:33-37`

```powershell
$script:RowCache   = @{}
$script:Cat    = 'Windows'
$script:Busy   = $false
$script:Job    = $null
$script:Queue  = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
```

### 4.7 `$Helpers` here-string (runspace preamble) — `Akari.ps1:70-100`

```powershell
$Helpers = @'
$ProgressPreference = 'SilentlyContinue'
function Write-Log([string]$m) { if ($m -and $m.Trim()) { [void]$LogQueue.Enqueue($m.TrimEnd()) } }
function Write-Host {
    param([Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object, $ForegroundColor, $BackgroundColor, [switch]$NoNewline, $Separator = ' ')
    Write-Log (($Object | ForEach-Object { "$_" }) -join $Separator)
}
function Clear-Host { }
function show-menu { }
function Pause { }
function Set-Reg($Path, $Name, $Value, $Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}
function Remove-Reg($Path, $Name) { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue }
function Run-Trusted([String]$command) {
    # ... TrustedInstaller hijack helper ...
}
'@
```

---

## 5. Key Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| `MaxClockSpeed` null on VMs/OEM | Per-field try/catch with `-gt 0` check → "Not available" |
| `Win32_OperatingSystem` KB vs bytes confusion | Divide by `1MB` (1,048,576) for GB conversion |
| `-Result` param adds branching to `Invoke-Code` | Preserve existing behavior when `$ResultVar` is `$null` — two distinct code paths |
| Thread safety of `$script:SpecData` | Set on UI thread (timer tick), read on UI thread (Show-Page) — no cross-thread issue |
| `Get-Specs` not available in runspace | Pass as code string constant (`$GetSpecsFunc`) prepended to `Invoke-Code` call |
| `BeginInvoke($null, $collection)` overload | Use `[System.Management.Automation.PSDataCollection[object]]::new()` — thread-safe synchronized collection |

---

*Pattern mapping completed: 2026-10-08*
