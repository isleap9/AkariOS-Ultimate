---
phase: 2
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - Akari.ps1
autonomous: true
requirements:
  - SPEC-03
  - SPEC-04
  - SPEC-05
---

# Plan 1: Hardware Spec Cards — GPU, Disk, Motherboard/BIOS

## Objective

Extend the `Get-Specs` function (defined in the `$GetSpecsFunc` here-string in `Akari.ps1`) with three new spec groups: GPU (all adapters with model, VRAM with registry fallback for >4GB, driver version), Disk (per-volume free/total space for fixed drives only), and Motherboard/BIOS (board manufacturer/product, BIOS version, release date with SMBIOS filler string filtering). Each group follows the Phase 1 per-field fallback pattern with `_Status` tracking.

## Phase Goal

GPU, disk, and motherboard/BIOS cards with hardware-diversity handling.

## Requirements Addressed

| ID | Description | How This Plan Delivers |
|----|-------------|----------------------|
| SPEC-03 | GPU card listing all adapters with model, VRAM, and driver version | `Get-Specs` queries `Win32_VideoController` for all instances, with registry fallback via `HardwareInformation.qwSize` for VRAM >4GB |
| SPEC-04 | Disk card with per-volume free/total space for fixed drives | `Get-Specs` queries `Win32_LogicalDisk` filtered by `DriveType -eq 3`, computes per-volume total/free/used in GB |
| SPEC-05 | Motherboard + BIOS card with board manufacturer/product, BIOS version, and release date | `Get-Specs` queries `Win32_BaseBoard` and `Win32_BIOS`, filters SMBIOS filler strings via `Test-SmbiosValue` helper |

## must_haves

- `Get-Specs` result hashtable contains six groups: `CPU`, `RAM`, `Windows`, `GPU`, `Disk`, `Motherboard`
- GPU group contains `_Status` and `Adapters` array; each adapter has `Model`, `VRAM_GB`, `DriverVersion`, `Status`
- GPU VRAM uses registry fallback via `HardwareInformation.qwSize` when `AdapterRAM -eq 4294967295` or `AdapterRAM -ge 4GB`
- Disk group contains `_Status` and `Volumes` array; each volume has `Drive`, `Label`, `FileSystem`, `TotalGB`, `FreeGB`
- Disk query filters by `DriveType -eq 3` (fixed drives only)
- Motherboard group contains `_Status`, `Manufacturer`, `Product`, `BIOSVersion`, `ReleaseDate`
- `Test-SmbiosValue` helper function is defined inside `$GetSpecsFunc` before `Get-Specs`
- `Test-SmbiosValue` filters common SMBIOS filler strings: `"To Be Filled By O.E.M."`, `"Default string"`, `"None"`, `"N/A"`, `"Not Specified"`, `"Not Available"`, `"System Product Name"`, `"System Manufacturer"`, `"System Version"`, `"System Serial Number"`, `"Base Board Version"`, `"Base Board Product"`, `"Base Board Manufacturer"`, `"BIOS Version"`, `"BIOS Date"`, `"x.x"`, `"0"`
- Failed fields are the string `"Not available"`, never `$null` or empty
- Each new group has `_Status` computed as `'OK'`, `'Partial'`, or `'Failed'` based on success count vs total fields
- Phase 1 groups (CPU, RAM, Windows) remain unchanged
- Only `Akari.ps1` is modified — no new files created

## truths

- Only `Akari.ps1` is modified — the `$GetSpecsFunc` here-string is extended with three new group queries and the `Test-SmbiosValue` helper
- GPU and Disk groups use arrays of hashtables (one per adapter/volume), while Motherboard uses flat key-value pairs (single board/BIOS)
- The registry VRAM fallback uses index-based matching (registry subkey `0000`, `0001`, ... maps to WMI instance index 0, 1, ...) — works on 99%+ of systems
- `Win32_VideoController` returns all adapters including integrated GPUs and basic display adapters — all are listed
- `Win32_LogicalDisk` is filtered by `DriveType -eq 3` to exclude USB, network, CD/DVD, and RAM disks
- `Win32_BaseBoard` and `Win32_BIOS` each return a single instance — no iteration needed
- SMBIOS filler string filtering is case-sensitive exact match after `.Trim()`
- BIOS `ReleaseDate` is formatted as `yyyy-MM-dd` string
- The `Test-SmbiosValue` function is defined inside the `$GetSpecsFunc` here-string, before `Get-Specs`, so it's available when `Get-Specs` runs
- Phase 1 per-field fallback pattern is preserved: initialize to `"Not available"`, increment success counter, compute `_Status`
- For GPU and Disk, `$total` is computed as `$items.Count * $fieldsPerItem`; if 0 items, `$total = 0` and `_Status = 'Failed'`

## Tasks

<task id="2.1" type="execute" wave="1">
<title>Add Test-SmbiosValue helper and GPU group to Get-Specs</title>
<read_first>
- Akari.ps1 (lines 103-187 — current $GetSpecsFunc here-string with Get-Specs function)
- .planning/phases/02-hardware-spec-cards/02-RESEARCH.md (section 1 — GPU specs, Win32_VideoController, VRAM registry fallback)
- .planning/phases/02-hardware-spec-cards/02-RESEARCH.md (section 7 — Test-SmbiosValue helper function)
- .planning/phases/01-spec-query-engine/01-PATTERNS.md (section 2.5 — per-field error handling patterns)
- .planning/phases/01-spec-query-engine/01-RESEARCH.md (section 3 — per-field fallback strategies)
</read_first>
<action>
Modify the `$GetSpecsFunc` here-string in `Akari.ps1` (currently lines 103-187) to add two things before the `return $result` statement:

1. **Test-SmbiosValue helper function** — Define a new function `Test-SmbiosValue` inside the here-string, before `Get-Specs`. The function takes a `[string]$Value` parameter. It returns `$false` if `[string]::IsNullOrWhiteSpace($Value)` is true. It defines a `$fillers` array containing these exact strings: `'To Be Filled By O.E.M.'`, `'Default string'`, `'None'`, `'N/A'`, `'Not Specified'`, `'Not Available'`, `'System Product Name'`, `'System Manufacturer'`, `'System Version'`, `'System Serial Number'`, `'Base Board Version'`, `'Base Board Product'`, `'Base Board Manufacturer'`, `'BIOS Version'`, `'BIOS Date'`, `'x.x'`, `'0'`. It trims the input value and checks if `$fillers -contains $trimmed`. If yes, returns `$false`; otherwise returns `$true`.

2. **GPU group** — Add `GPU = @{ _Status = 'OK'; Adapters = @() }` to the `$result` initialization hashtable. Then add a GPU query section before `return $result`:

   - Initialize `$gpuAdapters = @()`, `$gpuFields = 3`, `$gpuSuccess = 0`, `$gpuTotal = 0`
   - Try/catch block: query `$gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)`
   - If `$gpus.Count -eq 0`, set `$result.GPU._Status = 'Failed'`
   - Else: build a `$regVram` hashtable by querying registry path `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`. Get child items matching `^\d{4}$`, sort by `PSChildName`. For each key, read `HardwareInformation.qwSize` property. If non-null, store in `$regVram[$key.PSChildName]`.
   - Iterate `$gpus` by index `$i` from 0 to `$gpus.Count - 1`. For each GPU:
     - Create `$adapter = @{ Model = 'Not available'; VRAM_GB = 'Not available'; DriverVersion = 'Not available'; Status = 'OK' }`
     - Increment `$gpuTotal += $gpuFields`
     - If `$gpu.Name` non-empty: set `$adapter.Model = $gpu.Name.Trim()`, increment `$gpuSuccess`
     - Get `$vramBytes = $gpu.AdapterRAM`. If `$vramBytes -eq 4294967295 -or $vramBytes -ge 4GB`: look up `$regKey = '{0:D4}' -f $i` in `$regVram`. If exists, set `$vramBytes = $regVram[$regKey]`
     - If `$vramBytes -gt 0 -and $vramBytes -ne 4294967295`: set `$adapter.VRAM_GB = [math]::Round($vramBytes / 1GB, 1)`, increment `$gpuSuccess`
     - If `$gpu.DriverVersion` non-empty: set `$adapter.DriverVersion = $gpu.DriverVersion`, increment `$gpuSuccess`
     - If `$gpu.Status -and $gpu.Status -ne 'OK'`: set `$adapter.Status = $gpu.Status`
     - Append `$adapter` to `$gpuAdapters` using `$gpuAdapters += ,$adapter` (comma operator to append as single element)
   - After loop: set `$result.GPU.Adapters = $gpuAdapters`
   - Compute `_Status`: if `$gpuSuccess -eq 0 -and $gpuTotal -gt 0` set `'Failed'`, elseif `$gpuSuccess -lt $gpuTotal` set `'Partial'`
   - Catch block: set `$result.GPU._Status = 'Failed'`

The GPU section must be inserted after the Windows section and before `return $result`. The `Test-SmbiosValue` function must be defined before `function Get-Specs {` so it's available when `Get-Specs` runs.
</action>
<acceptance_criteria>
- Akari.ps1 `$GetSpecsFunc` here-string contains `function Test-SmbiosValue` with `param([string]$Value)`
- `Test-SmbiosValue` checks `[string]::IsNullOrWhiteSpace($Value)` and returns `$false` for null/empty
- `Test-SmbiosValue` defines a `$fillers` array containing all 17 filler strings listed in the action
- `Test-SmbiosValue` uses `$fillers -contains $trimmed` for comparison
- `Test-SmbiosValue` is defined before `function Get-Specs {` in the here-string
- `$result` initialization includes `GPU = @{ _Status = 'OK'; Adapters = @() }`
- GPU section queries `Win32_VideoController` with `-ErrorAction Stop`
- GPU section wraps query in `@()` to ensure array type
- GPU section checks `$gpus.Count -eq 0` for no-GPU case
- GPU section queries registry `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`
- GPU section filters registry subkeys by `^\d{4}$` pattern
- GPU section reads `HardwareInformation.qwSize` property
- GPU section checks `$vramBytes -eq 4294967295 -or $vramBytes -ge 4GB` for registry fallback
- GPU section uses `'{0:D4}' -f $i` for registry subkey lookup
- GPU section uses `$gpuAdapters += ,$adapter` (comma operator) to append adapters
- GPU section computes `_Status` based on `$gpuSuccess` vs `$gpuTotal`
- GPU catch block sets `$result.GPU._Status = 'Failed'`
- Phase 1 CPU, RAM, Windows sections remain unchanged
</acceptance_criteria>
</task>

<task id="2.2" type="execute" wave="1">
<title>Add Disk group to Get-Specs</title>
<read_first>
- Akari.ps1 (lines 103-187 — current $GetSpecsFunc here-string, will be modified by task 2.1)
- .planning/phases/02-hardware-spec-cards/02-RESEARCH.md (section 2 — Disk specs, Win32_LogicalDisk, DriveType filtering)
- .planning/phases/01-spec-query-engine/01-PATTERNS.md (section 2.5 — per-field error handling patterns)
</read_first>
<action>
Modify the `$GetSpecsFunc` here-string in `Akari.ps1` to add a Disk group. This task assumes task 2.1 has been applied (the here-string now contains `Test-SmbiosValue` and the GPU group).

1. Add `Disk = @{ _Status = 'OK'; Volumes = @() }` to the `$result` initialization hashtable (after the GPU entry).

2. Add a Disk query section after the GPU section and before `return $result`:

   - Initialize `$diskVolumes = @()`, `$diskFields = 5`, `$diskSuccess = 0`, `$diskTotal = 0`
   - Try/catch block: query `$disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DriveType -eq 3 })`
   - If `$disks.Count -eq 0`, set `$result.Disk._Status = 'Failed'`
   - Else: iterate each `$disk` in `$disks`:
     - Create `$vol = @{ Drive = 'Not available'; Label = 'Not available'; FileSystem = 'Not available'; TotalGB = 'Not available'; FreeGB = 'Not available' }`
     - Increment `$diskTotal += $diskFields`
     - If `$disk.DeviceID` non-empty: set `$vol.Drive = $disk.DeviceID`, increment `$diskSuccess`
     - If `$disk.VolumeName` non-empty: set `$vol.Label = $disk.VolumeName`, increment `$diskSuccess`
     - If `$disk.FileSystem` non-empty: set `$vol.FileSystem = $disk.FileSystem`, increment `$diskSuccess`
     - If `$disk.Size -gt 0`: set `$vol.TotalGB = [math]::Round($disk.Size / 1GB, 1)`, increment `$diskSuccess`
     - If `$null -ne $disk.FreeSpace -and $disk.FreeSpace -gt 0`: set `$vol.FreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)`, increment `$diskSuccess`
     - Append `$vol` to `$diskVolumes` using `$diskVolumes += ,$vol`
   - After loop: set `$result.Disk.Volumes = $diskVolumes`
   - Compute `_Status`: if `$diskSuccess -eq 0 -and $diskTotal -gt 0` set `'Failed'`, elseif `$diskSuccess -lt $diskTotal` set `'Partial'`
   - Catch block: set `$result.Disk._Status = 'Failed'`

The Disk section must be inserted after the GPU section and before `return $result`.
</action>
<acceptance_criteria>
- `$result` initialization includes `Disk = @{ _Status = 'OK'; Volumes = @() }`
- Disk section queries `Win32_LogicalDisk` with `-ErrorAction Stop`
- Disk section filters by `Where-Object { $_.DriveType -eq 3 }` (fixed drives only)
- Disk section wraps query in `@()` to ensure array type
- Disk section checks `$disks.Count -eq 0` for no-fixed-drives case
- Disk section uses `$diskFields = 5` (Drive, Label, FileSystem, TotalGB, FreeGB)
- Disk section checks `$disk.Size -gt 0` before converting to GB
- Disk section checks `$null -ne $disk.FreeSpace -and $disk.FreeSpace -gt 0` before converting to GB
- Disk section divides by `1GB` (not `1MB`) for byte-to-GB conversion
- Disk section uses `[math]::Round(..., 1)` for one decimal place
- Disk section uses `$diskVolumes += ,$vol` (comma operator) to append volumes
- Disk section computes `_Status` based on `$diskSuccess` vs `$diskTotal`
- Disk catch block sets `$result.Disk._Status = 'Failed'`
- Phase 1 CPU, RAM, Windows sections remain unchanged
- GPU group from task 2.1 remains unchanged
</acceptance_criteria>
</task>

<task id="2.3" type="execute" wave="1">
<title>Add Motherboard/BIOS group to Get-Specs</title>
<read_first>
- Akari.ps1 (lines 103-187 — current $GetSpecsFunc here-string, will be modified by tasks 2.1 and 2.2)
- .planning/phases/02-hardware-spec-cards/02-RESEARCH.md (section 3 — Motherboard & BIOS specs, Win32_BaseBoard, Win32_BIOS, SMBIOS filler filtering)
- .planning/phases/02-hardware-spec-cards/02-RESEARCH.md (section 7 — Test-SmbiosValue helper function)
- .planning/phases/01-spec-query-engine/01-PATTERNS.md (section 2.5 — per-field error handling patterns)
</read_first>
<action>
Modify the `$GetSpecsFunc` here-string in `Akari.ps1` to add a Motherboard/BIOS group. This task assumes tasks 2.1 and 2.2 have been applied (the here-string now contains `Test-SmbiosValue`, GPU group, and Disk group).

1. Add `Motherboard = @{ _Status = 'OK' }` to the `$result` initialization hashtable (after the Disk entry).

2. Add a Motherboard/BIOS query section after the Disk section and before `return $result`:

   - Initialize `$mbManufacturer = 'Not available'`, `$mbProduct = 'Not available'`, `$biosVersion = 'Not available'`, `$biosDate = 'Not available'`
   - Set `$mbFields = 4` and `$mbSuccess = 0`
   - First try/catch: query `$board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop`
     - If `$board` is non-null:
       - If `Test-SmbiosValue $board.Manufacturer` returns `$true`: set `$mbManufacturer = $board.Manufacturer.Trim()`, increment `$mbSuccess`
       - If `Test-SmbiosValue $board.Product` returns `$true`: set `$mbProduct = $board.Product.Trim()`, increment `$mbSuccess`
   - Second try/catch: query `$bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop`
     - If `$bios` is non-null:
       - If `Test-SmbiosValue $bios.SMBIOSBIOSVersion` returns `$true`: set `$biosVersion = $bios.SMBIOSBIOSVersion.Trim()`, increment `$mbSuccess`
       - If `$bios.ReleaseDate` is non-null: set `$biosDate = $bios.ReleaseDate.ToString('yyyy-MM-dd')`, increment `$mbSuccess`
   - After both try/catch blocks:
     - Set `$result.Motherboard.Manufacturer = $mbManufacturer`
     - Set `$result.Motherboard.Product = $mbProduct`
     - Set `$result.Motherboard.BIOSVersion = $biosVersion`
     - Set `$result.Motherboard.ReleaseDate = $biosDate`
     - Compute `_Status`: if `$mbSuccess -eq 0` set `'Failed'`, elseif `$mbSuccess -lt $mbFields` set `'Partial'`

The Motherboard/BIOS section must be inserted after the Disk section and before `return $result`. The `Test-SmbiosValue` function (added in task 2.1) must be available — it is defined before `Get-Specs` in the here-string.
</action>
<acceptance_criteria>
- `$result` initialization includes `Motherboard = @{ _Status = 'OK' }`
- Motherboard section queries `Win32_BaseBoard` with `-ErrorAction Stop`
- Motherboard section queries `Win32_BIOS` with `-ErrorAction Stop`
- Motherboard section uses `Test-SmbiosValue` to filter `$board.Manufacturer` and `$board.Product`
- Motherboard section uses `Test-SmbiosValue` to filter `$bios.SMBIOSBIOSVersion`
- Motherboard section uses `.Trim()` on string values after `Test-SmbiosValue` passes
- Motherboard section formats `$bios.ReleaseDate` as `.ToString('yyyy-MM-dd')`
- Motherboard section checks `$bios.ReleaseDate` for non-null before formatting
- Motherboard section uses `$mbFields = 4` (Manufacturer, Product, BIOSVersion, ReleaseDate)
- Motherboard section sets `$result.Motherboard.Manufacturer`, `.Product`, `.BIOSVersion`, `.ReleaseDate`
- Motherboard section computes `_Status` based on `$mbSuccess` vs `$mbFields`
- Motherboard catch blocks are empty (suppress and continue)
- Phase 1 CPU, RAM, Windows sections remain unchanged
- GPU group from task 2.1 remains unchanged
- Disk group from task 2.2 remains unchanged
- `Test-SmbiosValue` function from task 2.1 remains unchanged
</acceptance_criteria>
</task>

## Verification

### Manual Verification Steps

1. **App launches without errors**: Run `powershell -ExecutionPolicy Bypass -File Akari.ps1` and verify the app launches. The `$GetSpecsFunc` here-string is parsed at script load time — any syntax error in the new code will prevent launch.

2. **Existing tweaks still work**: Verify that row buttons, Set-Prio, Set-Svc all function identically. They use `Invoke-Code` without `-Result` and are unaffected by the `$GetSpecsFunc` extension.

3. **Get-Specs function syntax**: The extended `Get-Specs` function is syntactically valid if the app launches without errors. The here-string is parsed at script load time.

4. **Spec data structure**: Phase 3 will consume `$script:SpecData`. The structure is verified by the acceptance criteria — the hashtable has six groups with correct keys, field names, and fallback values.

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
# 4. Verify $script:SpecData is a hashtable with CPU, RAM, Windows, GPU, Disk, Motherboard keys
# 5. Verify each group has _Status and the expected fields
# 6. Verify GPU.Adapters is an array with Model, VRAM_GB, DriverVersion, Status per adapter
# 7. Verify Disk.Volumes is an array with Drive, Label, FileSystem, TotalGB, FreeGB per volume
# 8. Verify Motherboard has Manufacturer, Product, BIOSVersion, ReleaseDate
```

## Success Criteria

| Criterion | Verification |
|-----------|-------------|
| GPU group with Adapters array | Source assertion: `$result.GPU.Adapters` is an array of hashtables |
| GPU VRAM registry fallback for >4GB | Source assertion: checks `$vramBytes -eq 4294967295 -or $vramBytes -ge 4GB` and looks up `HardwareInformation.qwSize` |
| GPU lists all adapters | Source assertion: iterates all `Win32_VideoController` instances, no filtering |
| Disk group with Volumes array | Source assertion: `$result.Disk.Volumes` is an array of hashtables |
| Disk filters fixed drives only | Source assertion: `Where-Object { $_.DriveType -eq 3 }` |
| Disk per-volume free/total space | Source assertion: `$vol.TotalGB` and `$vol.FreeGB` computed from `Size` and `FreeSpace` |
| Motherboard manufacturer/product | Source assertion: `$result.Motherboard.Manufacturer` and `$result.Motherboard.Product` from `Win32_BaseBoard` |
| BIOS version and release date | Source assertion: `$result.Motherboard.BIOSVersion` from `SMBIOSBIOSVersion`, `$result.Motherboard.ReleaseDate` from `ReleaseDate` |
| SMBIOS filler string filtering | Source assertion: `Test-SmbiosValue` function defined and used for all Motherboard/BIOS string fields |
| Failed fields are "Not available" | Source assertion: local variables initialized to `"Not available"` before try/catch |
| _Status computed per group | Source assertion: `_Status` set to `'Failed'`, `'Partial'`, or `'OK'` based on success count |
| Phase 1 groups unchanged | Source assertion: CPU, RAM, Windows sections match Phase 1 acceptance criteria |
| No new files created | Filesystem assertion: only `Akari.ps1` is modified |

## Threat Model

### ASVS L1 Threats

| Threat | Severity | Mitigation |
|--------|----------|------------|
| **T1: Registry read failure for VRAM fallback** | Low | Registry read uses `-ErrorAction SilentlyContinue`. If the key is missing, `$regVram` is empty and VRAM stays `"Not available"`. GPU group `_Status` reflects the partial failure. |
| **T2: Registry subkey-to-WMI instance mismatch** | Low | Index-based matching (`0000` → instance 0) works on 99%+ of systems. If mismatched, VRAM may be incorrect but the field is still populated (not blank). Phase 3 can cross-check with `PNPDeviceID` if needed. |
| **T3: Win32_VideoController returns 0 instances** | Low | GPU section checks `$gpus.Count -eq 0` and sets `_Status = 'Failed'`. `Adapters` is an empty array. Phase 3 can hide the GPU card. |
| **T4: Win32_LogicalDisk returns 0 fixed drives** | Low | Disk section checks `$disks.Count -eq 0` and sets `_Status = 'Failed'`. `Volumes` is an empty array. Phase 3 can hide the disk card. |
| **T5: FreeSpace null on not-ready drives** | Low | Disk section checks `$null -ne $disk.FreeSpace -and $disk.FreeSpace -gt 0` before converting. Null `FreeSpace` stays `"Not available"`. |
| **T6: SMBIOS filler strings vary by OEM** | Low | The filler list covers the most common strings. Unknown fillers will pass through (acceptable risk — better than showing `"To Be Filled By O.E.M."`). |
| **T7: ReleaseDate null on some systems** | Low | Motherboard section checks `if ($bios.ReleaseDate)` before formatting. Null date stays `"Not available"`. |
| **T8: Test-SmbiosValue false positives** | Low | The filler list is specific enough that legitimate values (e.g., `"ASUSTeK COMPUTER INC."`, `"ROG STRIX Z690-A"`) won't match. The `"0"` filler only affects version fields where `"0"` is not a valid version. |
| **T9: GPU/Disk array structure differs from CPU/RAM/Windows** | Low | GPU and Disk use arrays of hashtables (one per item), while CPU/RAM/Windows/Motherboard use flat key-value pairs. Phase 3 must handle both structures. This is a design decision, not a security threat. |
| **T10: Thread safety of $script:SpecData** | Low | `$script:SpecData` is set on the UI thread (in DispatcherTimer tick) and read on the UI thread (in Show-Page). No cross-thread access. The `PSDataCollection` is synchronized by .NET. |

### Blocking Threats

None. All threats are Low severity. No High or Medium severity threats identified for this data-layer phase.

## Dependencies

- **Phase 2 depends on**: Phase 1 (Spec Query Engine) — requires `Invoke-Code -Result` parameter, `$script:SpecData` variable, and the `$GetSpecsFunc` here-string pattern
- **Phase 2 is consumed by**: Phase 3 (Home Shell & Live Refresh) reads `$script:SpecData` in `Show-Page` and renders GPU, Disk, and Motherboard cards

## Notes

- The `Get-Specs` function is NOT called during Phase 2 — it is only extended. Phase 3 will invoke it via `Invoke-Code` when the Home page is shown.
- The `$GetSpecsFunc` here-string grows from ~85 lines (Phase 1) to ~200+ lines (Phase 2). This is acceptable — it remains a single self-contained function.
- GPU and Disk groups use arrays of hashtables (`Adapters` and `Volumes`), while Motherboard uses flat key-value pairs. This structural difference is intentional: GPUs and disks are multi-instance, motherboard/BIOS is single-instance.
- The `Test-SmbiosValue` helper is defined inside `$GetSpecsFunc` (not in `$Helpers`) because it's specific to spec queries and not needed by tweak scripts.
- The registry VRAM fallback uses index-based matching for simplicity. A more robust approach (matching by `MatchingDeviceId`) can be added in a future phase if needed.
- All three tasks modify the same `$GetSpecsFunc` here-string and should be applied sequentially (task 2.1 → 2.2 → 2.3) to avoid merge conflicts.
