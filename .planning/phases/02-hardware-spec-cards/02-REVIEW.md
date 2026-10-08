---
phase: 02-hardware-spec-cards
reviewed: 2026-10-08T00:00:00Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - Akari.ps1
findings:
  critical: 1
  warning: 8
  info: 3
  total: 12
status: issues_found
---

# Phase 2: Code Review Report

**Reviewed:** 2026-10-08T00:00:00Z
**Depth:** standard
**Files Reviewed:** 1
**Status:** issues_found

## Summary

Scope: `git diff fe014fb..HEAD -- Akari.ps1`. That covers `Test-SmbiosValue`, the GPU/Disk/Motherboard groups in `$GetSpecsFunc`, and the `Invoke-Code -ResultVar` / DispatcherTimer tick fix.

The `BeginInvoke` overload fix works: it passes an empty completed input collection and reads `$j.ResultCollection`. The data layer still has accuracy defects that matter, because the project's core value is "accurate, live specs":

- The BIOS release date is converted to local time, so every user west of UTC sees the previous day. I reproduced the mechanism on the dev host: `ReleaseDate` comes back as `Kind=Local`, `02:00` in W. Europe, so the raw value is midnight UTC.
- A completely full disk reports `FreeGB = 'Not available'` instead of 0.
- The GPU registry fallback can silently attach the wrong adapter's VRAM through the index heuristic.
- The `_Status` logic produces `Partial` on healthy machines. Unlabeled volumes and virtual or basic display adapters both trigger it.
- The `-ResultVar` contract that Phase 3 depends on has an ignored parameter, silent drops, and side effects.

## Critical Issues

### CR-01: BIOS release date is off by one day for users west of UTC (and wrong calendar in non-Gregorian cultures)

**File:** `Akari.ps1:341`
**Issue:** `Get-CimInstance Win32_BIOS` turns the CIM datetime `ReleaseDate` (SMBIOS dates come through as `yyyyMMdd000000.000000+000`, midnight UTC) into a `DateTime` with `Kind = Local`. I checked this on the dev host: `ReleaseDate` = `18 Aug 2026 02:00:00`, `Kind = Local`, TZ `W. Europe Standard Time`. The code then formats that local value with `.ToString('yyyy-MM-dd')`.
- For any UTC-negative zone (all of the Americas, for example UTC-5), midnight UTC becomes 19:00 on the previous day. The card shows `2026-08-17` for a BIOS dated `2026-08-18`, which is wrong data on a page whose whole purpose is accuracy.
- `ToString(format)` with no provider uses `CurrentCulture`'s calendar. On th-TH (Buddhist calendar) the year prints as 2569, and on ar-SA (Um Al-Qura) it prints a Hijri date.

The SUMMARY's test passed only because the test host is east of UTC.
**Fix:**
```powershell
if ($bios.ReleaseDate) {
    $biosDate = $bios.ReleaseDate.ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $mbSuccess++
}
```

## Warnings

### WR-01: A full disk reports free space as "Not available" and is counted as a failed read

**File:** `Akari.ps1:311`
**Issue:** `if ($null -ne $disk.FreeSpace -and $disk.FreeSpace -gt 0)` excludes the valid value `0`. A volume at 100% capacity shows `FreeGB = 'Not available'` instead of `0` and pushes Disk `_Status` to `Partial`. That is exactly the case where the user most needs the real number. The `$null` guard alone is enough.
**Fix:**
```powershell
if ($null -ne $disk.FreeSpace) { $vol.FreeGB = [math]::Round($disk.FreeSpace / 1GB, 1); $diskSuccess++ }
```

### WR-02: Disk `_Status` is `Partial` on almost every machine because an empty volume label is treated as a failed field

**File:** `Akari.ps1:294, 308`
**Issue:** `Label` is one of the 5 counted fields, and a volume with no label (the default for `C:` on most installs) never increments `$diskSuccess`. A perfectly healthy read therefore reports `Partial`. The SUMMARY admits this and pushes the workaround to Phase 3. That leaves `_Status` semantically broken at the source, and every consumer has to special-case it. An empty label is a successful read of an empty value, not a query failure.
**Fix:** Stop counting Label as a fallible field:
```powershell
$diskFields = 4
...
$vol.Label = if ($disk.VolumeName) { $disk.VolumeName } else { '' }   # empty label is valid; not counted
```

### WR-03: The index-based VRAM fallback can silently report another (or a removed) adapter's VRAM as fact

**File:** `Akari.ps1:267-270`
**Issue:** When no `MatchingDeviceId` prefix matches, the code uses `'{0:D4}' -f $i`. Here `$i` is the WMI enumeration index, and that order has no defined relationship to the display-class subkey numbers (`0000`, `0001`, ...). The class key also keeps subkeys for **removed or ghost adapters**: after a GPU swap, `0000` often still holds the old card's `qwMemorySize`.

`MatchingDeviceId` is an INF hardware ID, and it is not always a prefix of the instance path. For example, `PCI\VEN_x&DEV_y&REV_z` skips `SUBSYS`, and compatible IDs like `PCI\CC_0300` are not prefixes either. So the fallback is reachable, and when it fires it returns a plausible but wrong number and counts it as a success (`$vramCapped = $false`, `$gpuSuccess++`). This contradicts the phase's own key decision: "capped with no registry value reports 'Not available' rather than a wrong 4 GB".
**Fix:** Drop the index fallback, or match on something deterministic. The adapter's driver key can be resolved exactly from the PnP device's `Driver` property (`{4d36e968-...}\NNNN`):
```powershell
$drvKey = (Get-PnpDeviceProperty -InstanceId $gpu.PNPDeviceID -KeyName 'DEVPKEY_Device_Driver' -ErrorAction SilentlyContinue).Data
if ($drvKey) { $sub = $drvKey.Split('\')[-1]; if ($regVram.ContainsKey($sub)) { $regBytes = $regVram[$sub] } }
# otherwise leave VRAM 'Not available'
```

### WR-04: The authoritative 64-bit VRAM value is ignored whenever AdapterRAM is not a known sentinel

**File:** `Akari.ps1:256-276`
**Issue:** The registry `qwMemorySize` is only consulted when `$vramCapped` is true. Any other `AdapterRAM` value is trusted as-is, including values that understate real VRAM: shared-memory figures on iGPUs, and drivers that wrap or truncate instead of saturating at `0xFFF00000` / `0xFFFFFFFF`. The registry value is already read for every adapter (lines 227-246), so there is no cost to preferring it. The current logic makes VRAM accuracy depend on each vendor choosing one of two particular sentinels.
**Fix:** Resolve `$regBytes` for every adapter (deterministically, see WR-03). Use it when present, and fall back to `AdapterRAM` only when it is absent and not capped.

### WR-05: Virtual and basic display adapters are listed as GPUs and force GPU `_Status` to `Partial`

**File:** `Akari.ps1:222, 249-283`
**Issue:** `Win32_VideoController` also returns indirect-display and virtual adapters: Parsec / Virtual Display Driver / Meta / Citrix IDD adapters, `Microsoft Basic Display Adapter`, and `Microsoft Remote Display Adapter` on RDP sessions. These usually have `AdapterRAM` = 0 or null and often no registry `qwMemorySize`. Each one adds 3 to `$gpuTotal` but at most 2 successes. A machine with a healthy dGPU and one virtual display adapter therefore reports `Partial` and shows a junk "GPU" card. This is common among the gaming/streaming users this tool targets.
**Fix:** Skip adapters whose `PNPDeviceID` does not start with `PCI\` (virtual IDD adapters are `ROOT\...` or `SWD\...`), or exclude `AdapterDACType -eq 'Internal'` / names matching `'Basic Display|Remote Display|Virtual'`. At minimum, do not count VRAM toward `$gpuTotal` for non-PCI adapters.

### WR-06: `-ResultVar` is accepted but ignored; results are always written to `$script:SpecData`

**File:** `Akari.ps1:476, 492, 508-512`
**Issue:** `Invoke-Code` takes a `[string]$ResultVar` and stores it in the job, but the tick only uses it as a boolean and hardcodes `$script:SpecData`. Any future caller passing `-ResultVar 'Foo'` silently overwrites the spec data, and `Foo` is never set. The parameter's name describes a contract the code does not honour.
**Fix:**
```powershell
$val = if ($result -and $result.Count -gt 0) { $result[$result.Count - 1] } else { $null }
Set-Variable -Scope Script -Name $j.ResultVar -Value $val
```
Or rename the parameter to a switch (`-Specs`) to make the hardcoding explicit.

### WR-07: Spec refreshes are silently dropped while busy, and finished result jobs run Show-Page and a synchronous CIM query on the UI thread

**File:** `Akari.ps1:477, 506-523`
**Issue:** Three problems on the path Phase 3 will depend on for "live refresh every time Home is shown":
1. `if ($script:Busy) { return }` silently discards a spec request whenever a tweak is running. There is no queueing and no signal to the caller, so Home keeps showing stale or `$null` data with no indication.
2. A finished `-ResultVar` job goes through the same tail as tweak jobs: `Read-Svc` (line 522) runs `Get-CimInstance Win32_ComputerSystem` synchronously on the UI thread, which breaks the project constraint "fast and off the UI thread". `Show-Page` (line 523) then rebuilds the page. If Phase 3 hooks the spec refresh into `Show-Page` for Home, every completion triggers a new refresh, which completes and calls `Show-Page` again. The result is an endless roughly 1.5 s refresh loop that also keeps toggling `Set-Busy` and disabling `$Page`.
3. Each refresh also writes the label plus `Done: ...` into the log drawer, which floods it.

**Fix:** For `ResultVar` jobs, skip `Read-Svc`/`Show-Page`/`Done:` logging and raise a dedicated callback, for example `Update-Home`. Either queue a pending spec refresh to run when the current job finishes, or return `$false` so the caller can show "refresh pending".

### WR-08: A `BeginInvoke` failure leaves the app permanently busy and leaks the runspace

**File:** `Akari.ps1:478-497`
**Issue:** `Set-Busy $true` runs, and the runspace opens, before `BeginInvoke` is called inside a hashtable literal with no guard. The bug fixed in commit 210bc5f showed that `BeginInvoke` can throw here. If it does, `$script:Job` is never assigned, so the tick never resets `Busy`. The runspace and the `PowerShell` object are never disposed. Only the dispatcher's unhandled-exception handler happens to reset Busy, and only when the call came from a UI event. A call from `Add_Loaded` or a timer path would lock the page forever. The fix addressed the symptom (the overload) but not the failure mode.
**Fix:**
```powershell
try { $handle = $ps.BeginInvoke($inputCollection, $resultCollection) }
catch { Add-Log "Error: $($_.Exception.Message)"; $ps.Dispose(); $rs.Dispose(); Set-Busy $false; return }
$script:Job = @{ Ps = $ps; Rs = $rs; Handle = $handle; ... }
```

## Info

### IN-01: Redundant and unreachable conditions in the capped-VRAM check

**File:** `Akari.ps1:258`
**Issue:** `AdapterRAM` is `uint32`, so `-ge 4GB` can never be true, and `-ge 4293918720` already covers `-eq 4294967295`. Only the last clause does anything, which misleads readers about which cases are handled.
**Fix:** `$vramCapped = ($vramBytes -ge 4293918720)  # 0xFFF00000 or 0xFFFFFFFF sentinels`

### IN-02: SMBIOS filler list is incomplete, and matching is case-insensitive despite documented intent

**File:** `Akari.ps1:108-128`
**Issue:** Common placeholders are missing: `O.E.M.`, `OEM`, `Default`, `Not Applicable`, `Type2 - Board Product Name1`, `Type2 - Board Vendor Name1`, `INVALID`, `Undefined`, `Base Board Serial Number`. These get displayed as real values. Also, `-contains` is case-insensitive while the plan says case-sensitive. That behaviour is arguably better, but it should be made explicit (`-icontains`) so it is not "fixed" later by mistake.
**Fix:** Extend the list and use `-icontains`.

### IN-03: `$script:SpecData` is not type-checked; any stray output object becomes the spec data

**File:** `Akari.ps1:512`
**Issue:** The tick takes the last object emitted by the job. If a future edit to `Get-Specs` or `$Helpers` emits anything after the hashtable (a stray `Write-Output`, or a cmdlet without `| Out-Null`), `SpecData` becomes a string or other object, and Phase 3 rendering will throw on `.CPU`.
**Fix:** `$last = $result | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1; $script:SpecData = $last`

---

_Reviewed: 2026-10-08T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
