# Phase 2: Hardware Spec Cards — Research

**Date:** 2026-10-08
**Purpose:** Answer "What do I need to know to PLAN this phase well?"
**Scope:** GPU (Win32_VideoController + registry VRAM fallback), disk (Win32_LogicalDisk), motherboard/BIOS (Win32_BaseBoard + Win32_BIOS), SMBIOS filler filtering, hardware-diversity handling, Phase 1 pattern integration

---

## 1. GPU Specs — `Win32_VideoController`

### 1.1 Class Overview

**Class:** `Win32_VideoController` (namespace `root/CIMV2`)

Returns one instance per installed graphics adapter. On a typical system this includes:
- The primary discrete GPU (e.g., NVIDIA GeForce RTX 4070)
- The integrated GPU (e.g., Intel UHD Graphics 770) — if present
- On some systems: a "Microsoft Basic Display Adapter" or "Generic PnP Monitor" fallback

### 1.2 Key Properties

| Property | Type | Notes |
|----------|------|-------|
| `Name` | string | Full GPU model name (e.g., "NVIDIA GeForce RTX 4070"). Reliable on all systems. |
| `AdapterRAM` | uint32 | **Problematic** — limited to 4 GB (32-bit unsigned integer). Returns `4294967295` (0xFFFFFFFF) when VRAM exceeds 4 GB. This is the primary reason for the registry fallback. |
| `DriverVersion` | string | Driver version string (e.g., "31.0.15.3623"). Reliable. Format varies by vendor. |
| `DriverDate` | datetime | Driver release date. May be null on some systems. |
| `VideoProcessor` | string | GPU chip name (e.g., "AD104"). May be null or generic. |
| `PNPDeviceID` | string | PnP device ID (e.g., "PCI\VEN_10DE&DEV_2786&SUBSYS_..."). Useful for identifying the exact GPU. |
| `Status` | string | "OK" or "Error". Useful for detecting disabled/failed adapters. |
| `Availability` | uint16 | 3 = Running/Powered On. Other values indicate the device is not currently active. |

### 1.3 The VRAM >4 GB Problem

**The issue:** `AdapterRAM` is a `uint32` (32-bit unsigned integer). Its maximum value is 4,294,967,295 bytes ≈ 4 GB. When a GPU has more than 4 GB of VRAM, WMI returns `4294967295` (0xFFFFFFFF) as a sentinel value, not the actual VRAM size.

**Affected GPUs:** Any GPU with >4 GB VRAM — this includes virtually all modern discrete GPUs (RTX 3060 12GB, RTX 4070 12GB, RX 6700 XT 12GB, etc.).

**Detection:** Check if `AdapterRAM -eq 4294967295` (or `AdapterRAM -ge 4GB`). If true, the value is unreliable and the registry fallback must be used.

### 1.4 Registry Fallback for VRAM

**Registry path:** `HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\####\HardwareInformation.qwSize`

**How it works:**
- The GUID `{4d36e968-e325-11ce-bfc1-08002be10318}` is the device class GUID for display adapters.
- Under this key, subkeys `0000`, `0001`, `0002`, etc. correspond to each installed display adapter.
- The `HardwareInformation.qwSize` value is a `QWORD` (64-bit) containing the actual VRAM in bytes.
- This value is set by the GPU driver and is reliable for >4 GB VRAM.

**Matching registry subkeys to WMI instances:**
- The registry subkey order (0000, 0001, ...) generally matches the WMI instance order, but this is not guaranteed.
- A more reliable approach: match by `PNPDeviceID`. The registry subkeys contain a `MatchingDeviceId` value that matches the WMI `PNPDeviceID`.
- **Simpler approach (recommended for Phase 2):** Iterate registry subkeys in order, read `qwSize` from each, and assign to the corresponding WMI instance by index. This works on 99%+ of systems where the driver sets these values correctly.

**Query pattern:**
```powershell
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
$regKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | Sort-Object PSChildName
$regVram = @{}
foreach ($key in $regKeys) {
    $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
    if ($props -and $props.'HardwareInformation.qwSize') {
        $regVram[$key.PSChildName] = $props.'HardwareInformation.qwSize'
    }
}
```

**Matching to WMI instances:**
```powershell
$gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
for ($i = 0; $i -lt $gpus.Count; $i++) {
    $gpu = $gpus[$i]
    $vramBytes = $gpu.AdapterRAM
    if ($vramBytes -eq 4294967295 -or $vramBytes -ge 4GB) {
        # Use registry fallback
        $regKey = '{0:D4}' -f $i
        if ($regVram.ContainsKey($regKey)) {
            $vramBytes = $regVram[$regKey]
        }
    }
    $vramGB = [math]::Round($vramBytes / 1GB, 1)
}
```

### 1.5 Multi-GPU Handling

**Requirement:** "User sees ALL GPU adapters with model, VRAM, and driver version."

**Approach:** Iterate all `Win32_VideoController` instances. Each GPU becomes a sub-entry in the GPU group.

**Data structure decision:**
- The GPU group is a **list of GPU entries**, not a single flat hashtable.
- Each entry has: `Model`, `VRAM_GB`, `DriverVersion`, `Status`.
- The group-level `_Status` reflects whether the query succeeded overall.

**Proposed structure:**
```powershell
GPU = @{
    _Status = 'OK'
    Adapters = @(
        @{
            Model = 'NVIDIA GeForce RTX 4070'
            VRAM_GB = 12.0
            DriverVersion = '31.0.15.3623'
            Status = 'OK'
        },
        @{
            Model = 'Intel(R) UHD Graphics 770'
            VRAM_GB = 0.5  # shared system memory
            DriverVersion = '31.0.101.4502'
            Status = 'OK'
        }
    )
}
```

**Note on integrated GPUs:** Integrated GPUs (Intel UHD, AMD Radeon Graphics) often report `AdapterRAM` as a small shared memory value (e.g., 512 MB or 1 GB) or as `4294967295`. The registry fallback may not have a `qwSize` value for integrated GPUs. In that case, report the WMI value as-is or show "Not available" if it's the sentinel value.

### 1.6 GPU Fallback Strategy

```powershell
$gpuAdapters = @()
$gpuFields = 3  # Model, VRAM_GB, DriverVersion per adapter
$gpuSuccess = 0
$gpuTotal = 0

try {
    $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
    if ($gpus.Count -eq 0) {
        # No GPU found — unusual but possible on headless/Server Core
        $result.GPU._Status = 'Failed'
    } else {
        # Get registry VRAM values
        $regVram = @{}
        try {
            $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
            $regKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | Sort-Object PSChildName
            foreach ($key in $regKeys) {
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                if ($props -and $props.'HardwareInformation.qwSize') {
                    $regVram[$key.PSChildName] = $props.'HardwareInformation.qwSize'
                }
            }
        } catch { }

        for ($i = 0; $i -lt $gpus.Count; $i++) {
            $gpu = $gpus[$i]
            $adapter = @{ Model = 'Not available'; VRAM_GB = 'Not available'; DriverVersion = 'Not available'; Status = 'OK' }
            $gpuTotal += $gpuFields

            if ($gpu.Name) { $adapter.Model = $gpu.Name.Trim(); $gpuSuccess++ }

            $vramBytes = $gpu.AdapterRAM
            if ($vramBytes -eq 4294967295 -or $vramBytes -ge 4GB) {
                $regKey = '{0:D4}' -f $i
                if ($regVram.ContainsKey($regKey)) {
                    $vramBytes = $regVram[$regKey]
                }
            }
            if ($vramBytes -gt 0 -and $vramBytes -ne 4294967295) {
                $adapter.VRAM_GB = [math]::Round($vramBytes / 1GB, 1)
                $gpuSuccess++
            }

            if ($gpu.DriverVersion) { $adapter.DriverVersion = $gpu.DriverVersion; $gpuSuccess++ }

            if ($gpu.Status -and $gpu.Status -ne 'OK') { $adapter.Status = $gpu.Status }

            $gpuAdapters += ,$adapter
        }
    }
} catch {
    $result.GPU._Status = 'Failed'
}

$result.GPU.Adapters = $gpuAdapters
if ($gpuSuccess -eq 0 -and $gpuTotal -gt 0) { $result.GPU._Status = 'Failed' }
elseif ($gpuSuccess -lt $gpuTotal) { $result.GPU._Status = 'Partial' }
```

### 1.7 Known GPU Issues

| Issue | Cause | Mitigation |
|-------|-------|------------|
| `AdapterRAM` = 4294967295 | 32-bit uint32 overflow for >4 GB VRAM | Registry fallback via `HardwareInformation.qwSize` |
| Registry `qwSize` missing | Driver doesn't set it, or integrated GPU | Show "Not available" for VRAM |
| Multiple identical entries | Driver reinstalls, ghost devices | Filter by `Status -eq 'OK'` or deduplicate by `PNPDeviceID` |
| `Name` = "Microsoft Basic Display Adapter" | No driver installed | Show as-is; this is accurate information |
| Integrated GPU VRAM misleading | Shared system memory, not dedicated VRAM | Show value; Phase 3 can label as "Shared" if needed |

---

## 2. Disk Specs — `Win32_LogicalDisk`

### 2.1 Class Overview

**Class:** `Win32_LogicalDisk` (namespace `root/CIMV2`)

Returns one instance per logical disk (volume) on the system. This includes:
- Fixed drives (HDD, SSD, NVMe) — `DriveType = 3`
- Removable drives (USB flash drives) — `DriveType = 2`
- Network drives — `DriveType = 4`
- CD/DVD drives — `DriveType = 5`
- RAM disks — `DriveType = 6`

### 2.2 Key Properties

| Property | Type | Notes |
|----------|------|-------|
| `DeviceID` | string | Drive letter (e.g., "C:"). |
| `DriveType` | uint32 | 3 = Local Disk (fixed). Filter on this. |
| `Size` | uint64 | Total size in bytes. Reliable. |
| `FreeSpace` | uint64 | Free space in bytes. Reliable. |
| `VolumeName` | string | Volume label (e.g., "Windows", "Data"). May be empty. |
| `FileSystem` | string | File system type (e.g., "NTFS", "FAT32", "exFAT"). |
| `VolumeSerialNumber` | string | Volume serial number. Not needed for display. |

### 2.3 Filtering for Fixed Drives Only

**Requirement:** "User sees per-volume free/total space for fixed drives only."

**Filter:** `DriveType -eq 3` (Local Disk). This excludes USB drives, network drives, CD/DVD, and RAM disks.

**Query pattern:**
```powershell
$disks = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DriveType -eq 3 }
```

### 2.4 Per-Volume Iteration

Each fixed drive becomes a sub-entry in the Disk group. The structure mirrors the GPU group:

```powershell
Disk = @{
    _Status = 'OK'
    Volumes = @(
        @{
            Drive = 'C:'
            Label = 'Windows'
            FileSystem = 'NTFS'
            TotalGB = 476.3
            FreeGB = 123.4
            UsedGB = 352.9
        },
        @{
            Drive = 'D:'
            Label = 'Data'
            FileSystem = 'NTFS'
            TotalGB = 931.5
            FreeGB = 456.7
            UsedGB = 474.8
        }
    )
}
```

### 2.5 Unit Conversion

`Size` and `FreeSpace` are in **bytes** (uint64). Divide by `1GB` (1,073,741,824) to get GB.

```powershell
$totalGB = [math]::Round($disk.Size / 1GB, 1)
$freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
$usedGB = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 1)
```

### 2.6 Disk Fallback Strategy

```powershell
$diskVolumes = @()
$diskFields = 5  # Drive, Label, FileSystem, TotalGB, FreeGB per volume
$diskSuccess = 0
$diskTotal = 0

try {
    $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DriveType -eq 3 })
    if ($disks.Count -eq 0) {
        $result.Disk._Status = 'Failed'
    } else {
        foreach ($disk in $disks) {
            $vol = @{ Drive = 'Not available'; Label = 'Not available'; FileSystem = 'Not available'; TotalGB = 'Not available'; FreeGB = 'Not available' }
            $diskTotal += $diskFields

            if ($disk.DeviceID) { $vol.Drive = $disk.DeviceID; $diskSuccess++ }
            if ($disk.VolumeName) { $vol.Label = $disk.VolumeName; $diskSuccess++ }
            if ($disk.FileSystem) { $vol.FileSystem = $disk.FileSystem; $diskSuccess++ }
            if ($disk.Size -gt 0) { $vol.TotalGB = [math]::Round($disk.Size / 1GB, 1); $diskSuccess++ }
            if ($disk.FreeSpace -ne $null -and $disk.FreeSpace -gt 0) { $vol.FreeGB = [math]::Round($disk.FreeSpace / 1GB, 1); $diskSuccess++ }

            $diskVolumes += ,$vol
        }
    }
} catch {
    $result.Disk._Status = 'Failed'
}

$result.Disk.Volumes = $diskVolumes
if ($diskSuccess -eq 0 -and $diskTotal -gt 0) { $result.Disk._Status = 'Failed' }
elseif ($diskSuccess -lt $diskTotal) { $result.Disk._Status = 'Partial' }
```

### 2.7 Known Disk Issues

| Issue | Cause | Mitigation |
|-------|-------|------------|
| `FreeSpace` = null | Drive not ready (e.g., empty card reader) | Check for null before converting; show "Not available" |
| `Size` = 0 | Unformatted drive or raw partition | Show "Not available" for total/free |
| No fixed drives | Unusual but possible on some VMs | `_Status = 'Failed'`; Phase 3 shows "No fixed drives found" |
| `VolumeName` empty | Drive has no label | Show "Not available" or empty string |

---

## 3. Motherboard & BIOS Specs — `Win32_BaseBoard` + `Win32_BIOS`

### 3.1 Motherboard — `Win32_BaseBoard`

**Class:** `Win32_BaseBoard` (namespace `root/CIMV2`)

Returns a single instance representing the motherboard.

| Property | Type | Notes |
|----------|------|-------|
| `Manufacturer` | string | Board manufacturer (e.g., "ASUSTeK COMPUTER INC.", "Micro-Star International Co., Ltd."). May be a filler string. |
| `Product` | string | Board model (e.g., "ROG STRIX Z690-A GAMING WIFI"). May be a filler string. |
| `Version` | string | Board revision (e.g., "Rev 1.xx"). Often a filler string. |
| `SerialNumber` | string | Board serial number. Not needed for display (privacy). |
| `Description` | string | Generic description (e.g., "Base Board"). Not useful. |

### 3.2 BIOS — `Win32_BIOS`

**Class:** `Win32_BIOS` (namespace `root/CIMV2`)

Returns a single instance representing the BIOS.

| Property | Type | Notes |
|----------|------|-------|
| `SMBIOSBIOSVersion` | string | BIOS version string (e.g., "1402", "F12", "1.80"). This is the primary BIOS version field. |
| `ReleaseDate` | datetime | BIOS release date (e.g., "2023-01-15T00:00:00Z"). May be null on some systems. |
| `Manufacturer` | string | BIOS vendor (e.g., "American Megatrends Inc.", "Phoenix Technologies LTD"). |
| `Name` | string | BIOS name (e.g., "BIOS Date: 01/15/23 14:02:00 Ver: 04.06.05"). Less useful than `SMBIOSBIOSVersion`. |
| `SerialNumber` | string | BIOS serial number. Not needed for display. |
| `Version` | string | BIOS version (e.g., "ALASKA - 1072009"). May differ from `SMBIOSBIOSVersion`. |

### 3.3 SMBIOS Filler String Filtering

**Requirement:** "Null/filler SMBIOS strings are filtered to 'Not available'."

**Problem:** Many OEM systems (especially budget/prebuilt) return placeholder strings from SMBIOS instead of actual data. These strings are meaningless and should be treated as "Not available".

**Common filler strings:**
- `"To Be Filled By O.E.M."`
- `"Default string"`
- `"None"`
- `"N/A"`
- `"Not Specified"`
- `"Not Available"`
- `"System Product Name"`
- `"System Manufacturer"`
- `"System Version"`
- `"System Serial Number"`
- `"Base Board Version"`
- `"Base Board Product"`
- `"Base Board Manufacturer"`
- `"BIOS Version"` (literal string, not actual version)
- `"BIOS Date"` (literal string)
- `""` (empty string)
- `"0"` (for version fields)

**Filtering function:**
```powershell
function Test-SmbiosValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $fillers = @(
        'To Be Filled By O.E.M.',
        'Default string',
        'None',
        'N/A',
        'Not Specified',
        'Not Available',
        'System Product Name',
        'System Manufacturer',
        'System Version',
        'System Serial Number',
        'Base Board Version',
        'Base Board Product',
        'Base Board Manufacturer',
        'BIOS Version',
        'BIOS Date',
        'x.x',
        '0'
    )
    $trimmed = $Value.Trim()
    if ($fillers -contains $trimmed) { return $false }
    return $true
}
```

**Usage:**
```powershell
$boardManufacturer = 'Not available'
$boardProduct = 'Not available'
$biosVersion = 'Not available'
$biosDate = 'Not available'

try {
    $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop
    if ($board) {
        if (Test-SmbiosValue $board.Manufacturer) { $boardManufacturer = $board.Manufacturer.Trim() }
        if (Test-SmbiosValue $board.Product) { $boardProduct = $board.Product.Trim() }
    }
} catch { }

try {
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
    if ($bios) {
        if (Test-SmbiosValue $bios.SMBIOSBIOSVersion) { $biosVersion = $bios.SMBIOSBIOSVersion.Trim() }
        if ($bios.ReleaseDate) {
            $biosDate = $bios.ReleaseDate.ToString('yyyy-MM-dd')
        }
    }
} catch { }
```

### 3.4 BIOS Date Formatting

`ReleaseDate` is a `datetime` object. Format it as `yyyy-MM-dd` for display:
```powershell
$biosDate = $bios.ReleaseDate.ToString('yyyy-MM-dd')
```

If `ReleaseDate` is null, show "Not available".

### 3.5 Motherboard/BIOS Fallback Strategy

```powershell
$mbManufacturer = 'Not available'
$mbProduct = 'Not available'
$biosVersion = 'Not available'
$biosDate = 'Not available'
$mbFields = 4
$mbSuccess = 0

try {
    $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop
    if ($board) {
        if (Test-SmbiosValue $board.Manufacturer) { $mbManufacturer = $board.Manufacturer.Trim(); $mbSuccess++ }
        if (Test-SmbiosValue $board.Product) { $mbProduct = $board.Product.Trim(); $mbSuccess++ }
    }
} catch { }

try {
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
    if ($bios) {
        if (Test-SmbiosValue $bios.SMBIOSBIOSVersion) { $biosVersion = $bios.SMBIOSBIOSVersion.Trim(); $mbSuccess++ }
        if ($bios.ReleaseDate) { $biosDate = $bios.ReleaseDate.ToString('yyyy-MM-dd'); $mbSuccess++ }
    }
} catch { }

$result.Motherboard.Manufacturer = $mbManufacturer
$result.Motherboard.Product = $mbProduct
$result.Motherboard.BIOSVersion = $biosVersion
$result.Motherboard.ReleaseDate = $biosDate
if ($mbSuccess -eq 0) { $result.Motherboard._Status = 'Failed' }
elseif ($mbSuccess -lt $mbFields) { $result.Motherboard._Status = 'Partial' }
```

### 3.6 Known Motherboard/BIOS Issues

| Issue | Cause | Mitigation |
|-------|-------|------------|
| `"To Be Filled By O.E.M."` | OEM didn't populate SMBIOS | Filler string filter |
| `"Default string"` | Generic SMBIOS placeholder | Filler string filter |
| `ReleaseDate` null | BIOS doesn't expose date | Show "Not available" |
| `SMBIOSBIOSVersion` = `"BIOS Version"` | Literal placeholder | Filler string filter |
| `Product` = `"System Product Name"` | Generic placeholder | Filler string filter |
| Multiple `Win32_BIOS` instances | Rare (dual BIOS) | Use `Select-Object -First 1` |

---

## 4. Hardware Diversity Handling

### 4.1 Systems with No Discrete GPU

**Scenario:** Server, VM, or headless system with only a basic display adapter or no GPU at all.

**Handling:**
- `Win32_VideoController` may return 0 instances or only "Microsoft Basic Display Adapter".
- If 0 instances: `_Status = 'Failed'`, `Adapters = @()`.
- If only basic adapter: show it as-is. This is accurate — the system has no real GPU.
- Phase 3 can choose to hide the GPU card entirely if `_Status = 'Failed'` and `Adapters.Count -eq 0`.

### 4.2 Systems with No Fixed Drives

**Scenario:** Unusual but possible on some VMs or specialized systems.

**Handling:**
- `Win32_LogicalDisk` filtered by `DriveType -eq 3` returns 0 instances.
- `_Status = 'Failed'`, `Volumes = @()`.
- Phase 3 can hide the disk card or show "No fixed drives found".

### 4.3 Systems with Missing SMBIOS Data

**Scenario:** Some VMs, ARM systems, or budget OEM systems have incomplete SMBIOS.

**Handling:**
- All motherboard/BIOS fields fall back to "Not available" via the filler string filter.
- `_Status = 'Failed'` if all fields fail, `'Partial'` if some succeed.
- Phase 3 can show the card with "Not available" values or hide it entirely.

### 4.4 Systems with Multiple GPUs

**Scenario:** Laptop with integrated + discrete GPU, or desktop with multiple discrete GPUs.

**Handling:**
- All adapters are listed in the `Adapters` array.
- Each adapter has its own Model, VRAM, DriverVersion.
- Phase 3 renders each adapter as a sub-item within the GPU card.

### 4.5 Systems with Many Drives

**Scenario:** Desktop with 4+ drives (C:, D:, E:, F:, etc.).

**Handling:**
- All fixed drives are listed in the `Volumes` array.
- Phase 3 renders each volume as a sub-item within the disk card.
- No artificial limit on the number of volumes.

---

## 5. Integration with Phase 1 Patterns

### 5.1 Extending the `Get-Specs` Function

**Current structure (Phase 1):**
```powershell
$result = @{
    CPU = @{ _Status = 'OK' }
    RAM = @{ _Status = 'OK' }
    Windows = @{ _Status = 'OK' }
}
```

**Phase 2 extension:**
```powershell
$result = @{
    CPU = @{ _Status = 'OK' }
    RAM = @{ _Status = 'OK' }
    Windows = @{ _Status = 'OK' }
    GPU = @{ _Status = 'OK'; Adapters = @() }
    Disk = @{ _Status = 'OK'; Volumes = @() }
    Motherboard = @{ _Status = 'OK' }
}
```

**Key principle:** Add new groups without modifying existing groups. The Phase 1 code for CPU, RAM, and Windows remains unchanged.

### 5.2 Per-Field Fallback Pattern

Phase 1 established the per-field fallback pattern:
1. Initialize all fields to "Not available".
2. Try the query.
3. On success, increment `$success` counter.
4. After all fields, compute `_Status` based on `$success` vs `$total`.

Phase 2 follows the same pattern for all new groups. The only difference is that GPU and Disk have **per-item** fallback (each adapter/volume has its own fields), while Motherboard has **per-field** fallback (like CPU/RAM/Windows).

### 5.3 `_Status` Computation

Same logic as Phase 1:
- `$success -eq 0` → `'Failed'`
- `$success -lt $total` → `'Partial'`
- `$success -eq $total` → `'OK'`

For GPU and Disk, `$total` is computed as `$items.Count * $fieldsPerItem`. If there are 0 items, `$total = 0` and `_Status = 'Failed'`.

### 5.4 Hashtable Structure Consistency

Phase 1 uses:
- Top-level: `@{ CPU = @{...}; RAM = @{...}; Windows = @{...} }`
- Within each group: flat key-value pairs with `_Status` reserved key.

Phase 2 adds:
- GPU: `@{ _Status = 'OK'; Adapters = @(@{...}, @{...}) }` — array of hashtables
- Disk: `@{ _Status = 'OK'; Volumes = @(@{...}, @{...}) }` — array of hashtables
- Motherboard: `@{ _Status = 'OK'; Manufacturer = '...'; Product = '...'; BIOSVersion = '...'; ReleaseDate = '...' }` — flat key-value pairs

**Note:** GPU and Disk use arrays of hashtables (one per item), while Motherboard uses flat key-value pairs (single board/BIOS). This is a structural difference that Phase 3 must handle.

### 5.5 `Invoke-Code` and `$script:SpecData`

No changes needed. The existing `Invoke-Code -Result` parameter and `$script:SpecData` variable work as-is. The `Get-Specs` function now returns a larger hashtable with 6 groups instead of 3, but the return mechanism is identical.

### 5.6 Calling `Get-Specs`

```powershell
# In Show-Page or a new Show-Home function (Phase 3):
if ($script:Cat -eq 'Home') {
    $script:SpecData = $null
    Invoke-Code ($GetSpecsFunc + "`nGet-Specs") "Refreshing system specs..." $null "SpecData"
}
```

The `$GetSpecsFunc` here-string constant is updated to include the new GPU, Disk, and Motherboard query code. The call site remains the same.

---

## 6. Complete `Get-Specs` Function (Phase 2)

```powershell
function Get-Specs {
    $result = @{
        CPU = @{ _Status = 'OK' }
        RAM = @{ _Status = 'OK' }
        Windows = @{ _Status = 'OK' }
        GPU = @{ _Status = 'OK'; Adapters = @() }
        Disk = @{ _Status = 'OK'; Volumes = @() }
        Motherboard = @{ _Status = 'OK' }
    }

    # --- CPU (Phase 1 — unchanged) ---
    # ... existing CPU code ...

    # --- RAM (Phase 1 — unchanged) ---
    # ... existing RAM code ...

    # --- Windows (Phase 1 — unchanged) ---
    # ... existing Windows code ...

    # --- GPU ---
    $gpuAdapters = @()
    $gpuFields = 3
    $gpuSuccess = 0
    $gpuTotal = 0

    try {
        $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
        if ($gpus.Count -eq 0) {
            $result.GPU._Status = 'Failed'
        } else {
            $regVram = @{}
            try {
                $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
                $regKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | Sort-Object PSChildName
                foreach ($key in $regKeys) {
                    $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                    if ($props -and $props.'HardwareInformation.qwSize') {
                        $regVram[$key.PSChildName] = $props.'HardwareInformation.qwSize'
                    }
                }
            } catch { }

            for ($i = 0; $i -lt $gpus.Count; $i++) {
                $gpu = $gpus[$i]
                $adapter = @{ Model = 'Not available'; VRAM_GB = 'Not available'; DriverVersion = 'Not available'; Status = 'OK' }
                $gpuTotal += $gpuFields

                if ($gpu.Name) { $adapter.Model = $gpu.Name.Trim(); $gpuSuccess++ }

                $vramBytes = $gpu.AdapterRAM
                if ($vramBytes -eq 4294967295 -or $vramBytes -ge 4GB) {
                    $regKey = '{0:D4}' -f $i
                    if ($regVram.ContainsKey($regKey)) {
                        $vramBytes = $regVram[$regKey]
                    }
                }
                if ($vramBytes -gt 0 -and $vramBytes -ne 4294967295) {
                    $adapter.VRAM_GB = [math]::Round($vramBytes / 1GB, 1)
                    $gpuSuccess++
                }

                if ($gpu.DriverVersion) { $adapter.DriverVersion = $gpu.DriverVersion; $gpuSuccess++ }
                if ($gpu.Status -and $gpu.Status -ne 'OK') { $adapter.Status = $gpu.Status }

                $gpuAdapters += ,$adapter
            }
        }
    } catch {
        $result.GPU._Status = 'Failed'
    }

    $result.GPU.Adapters = $gpuAdapters
    if ($gpuSuccess -eq 0 -and $gpuTotal -gt 0) { $result.GPU._Status = 'Failed' }
    elseif ($gpuSuccess -lt $gpuTotal) { $result.GPU._Status = 'Partial' }

    # --- Disk ---
    $diskVolumes = @()
    $diskFields = 5
    $diskSuccess = 0
    $diskTotal = 0

    try {
        $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DriveType -eq 3 })
        if ($disks.Count -eq 0) {
            $result.Disk._Status = 'Failed'
        } else {
            foreach ($disk in $disks) {
                $vol = @{ Drive = 'Not available'; Label = 'Not available'; FileSystem = 'Not available'; TotalGB = 'Not available'; FreeGB = 'Not available' }
                $diskTotal += $diskFields

                if ($disk.DeviceID) { $vol.Drive = $disk.DeviceID; $diskSuccess++ }
                if ($disk.VolumeName) { $vol.Label = $disk.VolumeName; $diskSuccess++ }
                if ($disk.FileSystem) { $vol.FileSystem = $disk.FileSystem; $diskSuccess++ }
                if ($disk.Size -gt 0) { $vol.TotalGB = [math]::Round($disk.Size / 1GB, 1); $diskSuccess++ }
                if ($null -ne $disk.FreeSpace -and $disk.FreeSpace -gt 0) { $vol.FreeGB = [math]::Round($disk.FreeSpace / 1GB, 1); $diskSuccess++ }

                $diskVolumes += ,$vol
            }
        }
    } catch {
        $result.Disk._Status = 'Failed'
    }

    $result.Disk.Volumes = $diskVolumes
    if ($diskSuccess -eq 0 -and $diskTotal -gt 0) { $result.Disk._Status = 'Failed' }
    elseif ($diskSuccess -lt $diskTotal) { $result.Disk._Status = 'Partial' }

    # --- Motherboard + BIOS ---
    $mbManufacturer = 'Not available'
    $mbProduct = 'Not available'
    $biosVersion = 'Not available'
    $biosDate = 'Not available'
    $mbFields = 4
    $mbSuccess = 0

    try {
        $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop
        if ($board) {
            if (Test-SmbiosValue $board.Manufacturer) { $mbManufacturer = $board.Manufacturer.Trim(); $mbSuccess++ }
            if (Test-SmbiosValue $board.Product) { $mbProduct = $board.Product.Trim(); $mbSuccess++ }
        }
    } catch { }

    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        if ($bios) {
            if (Test-SmbiosValue $bios.SMBIOSBIOSVersion) { $biosVersion = $bios.SMBIOSBIOSVersion.Trim(); $mbSuccess++ }
            if ($bios.ReleaseDate) { $biosDate = $bios.ReleaseDate.ToString('yyyy-MM-dd'); $mbSuccess++ }
        }
    } catch { }

    $result.Motherboard.Manufacturer = $mbManufacturer
    $result.Motherboard.Product = $mbProduct
    $result.Motherboard.BIOSVersion = $biosVersion
    $result.Motherboard.ReleaseDate = $biosDate
    if ($mbSuccess -eq 0) { $result.Motherboard._Status = 'Failed' }
    elseif ($mbSuccess -lt $mbFields) { $result.Motherboard._Status = 'Partial' }

    return $result
}
```

---

## 7. `Test-SmbiosValue` Helper Function

This function must be defined inside the runspace (prepended to the code or included in `$GetSpecsFunc`):

```powershell
function Test-SmbiosValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $fillers = @(
        'To Be Filled By O.E.M.',
        'Default string',
        'None',
        'N/A',
        'Not Specified',
        'Not Available',
        'System Product Name',
        'System Manufacturer',
        'System Version',
        'System Serial Number',
        'Base Board Version',
        'Base Board Product',
        'Base Board Manufacturer',
        'BIOS Version',
        'BIOS Date',
        'x.x',
        '0'
    )
    $trimmed = $Value.Trim()
    if ($fillers -contains $trimmed) { return $false }
    return $true
}
```

**Placement:** Define this function inside the `$GetSpecsFunc` here-string, before `Get-Specs`, so it's available when `Get-Specs` runs.

---

## 8. Summary: What You Need to Know to Plan

### 8.1 Technical Feasibility

| Concern | Status | Notes |
|---------|--------|-------|
| GPU query via `Win32_VideoController` | ✅ Well-documented | Standard CIM query |
| VRAM >4 GB registry fallback | ✅ Feasible | `HardwareInformation.qwSize` in display class registry key |
| Multi-GPU handling | ✅ Feasible | Iterate all instances, array of adapters |
| Disk query via `Win32_LogicalDisk` | ✅ Well-documented | Filter `DriveType -eq 3` |
| Motherboard via `Win32_BaseBoard` | ✅ Well-documented | Single instance |
| BIOS via `Win32_BIOS` | ✅ Well-documented | Single instance |
| SMBIOS filler filtering | ✅ Feasible | String comparison against known filler list |
| Integration with Phase 1 patterns | ✅ Feasible | Same per-field fallback, same `_Status` logic, same hashtable structure |

### 8.2 Key Risks

1. **Registry VRAM fallback may not match WMI instances** — the subkey-to-instance mapping is not guaranteed. Mitigation: match by index (works on 99%+ of systems), or match by `MatchingDeviceId` if available.
2. **Integrated GPU VRAM is misleading** — shared system memory, not dedicated VRAM. Mitigation: show the value; Phase 3 can label it.
3. **SMBIOS filler strings vary by OEM** — the list may not cover all possible filler strings. Mitigation: the list covers the most common ones; unknown fillers will pass through (acceptable risk).
4. **`FreeSpace` can be null** — on drives that are not ready. Mitigation: null check before conversion.
5. **GPU group structure differs from CPU/RAM/Windows** — array of hashtables vs flat key-value pairs. Mitigation: Phase 3 must handle both structures.

### 8.3 Planning Checklist

- [ ] Decide on GPU group structure: array of adapters vs flat with "GPU 1", "GPU 2" keys
- [ ] Decide on Disk group structure: array of volumes vs flat with "C:", "D:" keys
- [ ] Confirm registry VRAM fallback approach: index-based matching vs `MatchingDeviceId` matching
- [ ] Finalize SMBIOS filler string list
- [ ] Decide on `Test-SmbiosValue` placement: inside `$GetSpecsFunc` or in `$Helpers`
- [ ] Plan the `$GetSpecsFunc` here-string update (add GPU, Disk, Motherboard code)
- [ ] Plan the `Get-Specs` function body update (add three new group queries)
- [ ] Verify integration with existing `Invoke-Code -Result` and `$script:SpecData`
- [ ] Plan Phase 3 consumption: how Show-Page reads the new groups
- [ ] Decide on `_Status` computation for GPU/Disk when 0 items found

### 8.4 Files to Modify

| File | Change |
|------|--------|
| `Akari.ps1` | Update `$GetSpecsFunc` here-string to add GPU, Disk, Motherboard queries and `Test-SmbiosValue` helper |

### 8.5 Files to Create

| File | Purpose |
|------|---------|
| (none for Phase 2) | All changes are in the `$GetSpecsFunc` here-string in `Akari.ps1` |

### 8.6 Data Structure Summary

```
$result = @{
    CPU = @{ _Status = 'OK'; Model = '...'; Cores = 8; Threads = 16; SpeedMHz = 3600 }
    RAM = @{ _Status = 'OK'; TotalGB = 16.0; UsedGB = 8.0; FreeGB = 8.0 }
    Windows = @{ _Status = 'OK'; Edition = '...'; Version = '...'; Build = '...' }
    GPU = @{
        _Status = 'OK'
        Adapters = @(
            @{ Model = '...'; VRAM_GB = 12.0; DriverVersion = '...'; Status = 'OK' }
        )
    }
    Disk = @{
        _Status = 'OK'
        Volumes = @(
            @{ Drive = 'C:'; Label = '...'; FileSystem = 'NTFS'; TotalGB = 476.3; FreeGB = 123.4 }
        )
    }
    Motherboard = @{
        _Status = 'OK'
        Manufacturer = '...'
        Product = '...'
        BIOSVersion = '...'
        ReleaseDate = '2023-01-15'
    }
}
```

---

*Research completed: 2026-10-08*
