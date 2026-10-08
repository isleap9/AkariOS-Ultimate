---
phase: 02-hardware-spec-cards
reviewed: 2026-10-08T00:00:00Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - Akari.ps1
findings:
  critical: 0
  warning: 7
  info: 4
  total: 11
status: issues_found
---

# Phase 2: Code Review Report (re-review after 02-02)

**Reviewed:** 2026-10-08T00:00:00Z
**Depth:** standard
**Files Reviewed:** 1
**Status:** issues_found

## Summary

This is an incremental re-review after gap-closure plan 02-02. The primary scope is `git diff 2e46c02..HEAD -- Akari.ps1`, which covers the Disk and Motherboard/BIOS sections of `Get-Specs` inside the `$GetSpecsFunc` here-string. I also re-read the rest of `Akari.ps1` to confirm which earlier findings are still open.

**The three 02-02 fixes are correct, and I found no regressions:**

- **CR-01 (fixed), `Akari.ps1:345`.** The line is now `$bios.ReleaseDate.ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)`.
  - On the dev host, `Get-CimInstance Win32_BIOS` returns `ReleaseDate` as `Kind=Local` (`08/18/2026 02:00:00`, i.e. midnight UTC), so `ToUniversalTime()` recovers the firmware's UTC instant.
  - I ran my own check, separate from the orchestrator's 14-zone matrix: midnight UTC → local → back to UTC, for every day from 1995 to 2030, in every zone `TimeZoneInfo.GetSystemTimeZones()` returns. I used the worst case: `Kind=Unspecified`, so the ambiguous-DST flag is lost and .NET assumes standard time. No zone ever lands on a different calendar date.
  - The reason: an ambiguous local time that is resolved the wrong way moves the result forward by the DST delta (for example to 01:00 UTC), never back past midnight.
  - The invariant culture pins the Gregorian calendar. `-` is a literal in the custom format, so no culture-specific separator can be substituted.
- **WR-01 (fixed), `Akari.ps1:314`.** The guard is now `$null -ne $disk.FreeSpace`. A `FreeSpace` of 0 gives `0` and counts as a success. A null `FreeSpace` still gives `'Not available'` and no increment. `TotalGB` keeps its `-gt 0` guard, as the plan intended.
- **WR-02 (fixed), `Akari.ps1:295, 305, 310`.** `$diskFields = 4` matches the four increment sites exactly (DeviceID, FileSystem, Size, FreeSpace). Label now starts as `''` and is overwritten only by a truthy `VolumeName`, with no increment. The zero-volume branch (`Failed`) is unaffected: `$diskTotal` stays 0, so neither tail branch on lines 323-324 fires.
  - The contract change (Label `''` instead of `'Not available'`) has no consumer yet, because `$GetSpecsFunc` is not invoked anywhere in `Akari.ps1`. It is recorded for Phase 3 in 02-02-SUMMARY.

**Still open.** Every other finding from the prior review is still present in the code. I carry them forward under their **original IDs** so 02-REVIEW-DISPOSITION.md rows stay stable:

- WR-03, WR-04, WR-05, IN-01 and IN-02 are deferred to the backlog.
- WR-06, WR-07, WR-08 and IN-03 are deferred to Phase 3 (REFR-01). They must be resolved before refresh-on-show is wired.

CR-01, WR-01 and WR-02 are not re-reported, and their IDs are not reused.

**New findings** in code outside the 02-02 diff (Phase 1 `Get-Specs` sections):

- **WR-09:** the Windows `_Status` count can report `OK` when Edition failed.
- **IN-04:** CPU "Cores" silently falls back to the logical-processor count.

## Warnings

### WR-03: The index-based VRAM fallback can silently report another (or a removed) adapter's VRAM as fact (carried forward, deferred)

**File:** `Akari.ps1:267-270`
**Issue:** This is unchanged since the prior review. When no `MatchingDeviceId` prefix matches, the code looks up `'{0:D4}' -f $i`, where `$i` is the WMI enumeration index. That index has no defined relationship to the display-class subkey numbers. The class key also keeps subkeys for removed or ghost adapters.

When the fallback fires, it returns a plausible but wrong number and counts it as a success. This contradicts the phase rule that a capped adapter with no registry value reports 'Not available' rather than a wrong number.
**Fix:** Resolve the driver key deterministically, or drop the index fallback:
```powershell
$drvKey = (Get-PnpDeviceProperty -InstanceId $gpu.PNPDeviceID -KeyName 'DEVPKEY_Device_Driver' -ErrorAction SilentlyContinue).Data
if ($drvKey) { $sub = $drvKey.Split('\')[-1]; if ($regVram.ContainsKey($sub)) { $regBytes = $regVram[$sub] } }
# otherwise leave VRAM 'Not available'
```

### WR-04: The authoritative 64-bit VRAM value is ignored whenever AdapterRAM is not a known sentinel (carried forward, deferred)

**File:** `Akari.ps1:256-276`
**Issue:** This is unchanged. Registry `qwMemorySize` is consulted only when `$vramCapped` is true. Any other `AdapterRAM` value is trusted as-is, including values that understate real VRAM: iGPU shared-memory figures, and drivers that wrap rather than saturate.
**Fix:** For every adapter, resolve `$regBytes` deterministically (see WR-03) and prefer it when present. Fall back to `AdapterRAM` only when the registry value is absent and `AdapterRAM` is not capped.

### WR-05: Virtual and basic display adapters are listed as GPUs and force GPU `_Status` to `Partial` (carried forward, deferred)

**File:** `Akari.ps1:222, 249-283`
**Issue:** This is unchanged. The following adapters each add 3 to `$gpuTotal` but rarely produce VRAM:
- indirect-display and virtual adapters (Parsec, IDD, Citrix)
- `Microsoft Basic Display Adapter`
- `Microsoft Remote Display Adapter`

A healthy machine with one of these therefore reports `Partial` and shows a junk GPU entry.
**Fix:** Skip adapters whose `PNPDeviceID` does not start with `PCI\`, or match names against `'Basic Display|Remote Display|Virtual'`. At minimum, do not count VRAM toward `$gpuTotal` for non-PCI adapters.

### WR-06: `-ResultVar` is accepted but ignored; results are always written to `$script:SpecData` (carried forward, deferred to Phase 3)

**File:** `Akari.ps1:480, 496, 512-516`
**Issue:** This is unchanged. `$j.ResultVar` is only tested for truthiness, and the result is always written to the hardcoded `$script:SpecData`. Any other caller silently overwrites the spec data.
**Fix:**
```powershell
$val = if ($result -and $result.Count -gt 0) { $result[$result.Count - 1] } else { $null }
Set-Variable -Scope Script -Name $j.ResultVar -Value $val
```
Alternatively, replace the parameter with a `-Specs` switch so the hardcoding is explicit.

### WR-07: Spec refreshes are silently dropped while busy, and finished result jobs run Show-Page and a synchronous CIM query on the UI thread (carried forward, deferred to Phase 3)

**File:** `Akari.ps1:481, 509-528`
**Issue:** This is unchanged, and there are three problems:
- `if ($script:Busy) { return }` silently drops spec requests.
- Result jobs share the tweak completion tail. `Read-Svc` (line 526) runs `Get-CimInstance Win32_ComputerSystem` synchronously on the UI thread, and `Show-Page` (line 527) rebuilds the page. If Phase 3 starts a refresh from `Show-Page` for Home, each completion triggers another refresh, which creates an endless loop.
- Each refresh also writes label and `Done:` lines to the log drawer.

Phase 3 (REFR-01) must resolve this before wiring refresh-on-show.
**Fix:**
- For `ResultVar` jobs, skip `Read-Svc`, `Show-Page` and the `Done:` log line, and raise a dedicated `Update-Home` callback.
- Queue a pending spec refresh to run when the current job finishes, or return `$false` to the caller.

### WR-08: A `BeginInvoke` failure leaves the app permanently busy and leaks the runspace (carried forward, deferred to Phase 3)

**File:** `Akari.ps1:482-501`
**Issue:** This is unchanged. `Set-Busy $true` runs and the runspace is opened before `BeginInvoke`, which is called unguarded inside the hashtable literal. If it throws:
- `$script:Job` is never assigned, so the timer tick never clears Busy.
- `$ps` and `$rs` are never disposed.
**Fix:**
```powershell
try { $handle = $ps.BeginInvoke($inputCollection, $resultCollection) }
catch { Add-Log "Error: $($_.Exception.Message)"; $ps.Dispose(); $rs.Dispose(); Set-Busy $false; return }
$script:Job = @{ Ps = $ps; Rs = $rs; Handle = $handle; Label = $label; Meta = $meta; ResultVar = $ResultVar; ResultCollection = $resultCollection }
```

### WR-09: Windows `_Status` can report `OK` when the Edition read failed, because Build is counted twice (new, pre-existing Phase 1 code)

**File:** `Akari.ps1:193-214`
**Issue:** `$winFields = 3` (Edition, Version, Build), but there are four increment sites:
- `Caption` (line 198)
- `BuildNumber` (line 199)
- `UBR` (line 205), a second increment for the same Build field
- `DisplayVersion`/`ReleaseId` (lines 206-207)

Suppose `Caption` is empty or the `Win32_OperatingSystem` read fails partway, while `BuildNumber`, `UBR` and `DisplayVersion` all succeed. Then `$winSuccess = 3`, which is not `-lt 3`, so `_Status` stays `OK` while `Edition` is `'Not available'`.

That is the exact "tell the user it worked when it did not" failure that SPEC/REFR-02 status semantics are meant to prevent. The same miscount also hides a missing Version whenever Edition, Build and UBR all succeed.

This is outside the 02-02 diff (introduced in 3b68df1), but it is the same field-counting defect class that 02-02 just fixed for Disk.
**Fix:** Count fields, not reads. Do not increment for UBR; it only refines Build:
```powershell
if ($reg.UBR -and $winBuild -ne "Not available") { $winBuild = "$($winBuild).$($reg.UBR)" }   # refines build; not a separate field
```

## Info

### IN-01: Redundant and unreachable conditions in the capped-VRAM check (carried forward, deferred)

**File:** `Akari.ps1:258`
**Issue:** `AdapterRAM` is a `uint32`, so `-ge 4GB` can never be true, and `-ge 4293918720` already covers `-eq 4294967295`.
**Fix:** `$vramCapped = ($vramBytes -ge 4293918720)  # 0xFFF00000 or 0xFFFFFFFF sentinels`

### IN-02: SMBIOS filler list is incomplete, and matching is case-insensitive despite documented intent (carried forward, deferred)

**File:** `Akari.ps1:108-128`
**Issue:** Several common placeholders are missing:
- `O.E.M.`, `OEM`, `Default`
- `Not Applicable`, `INVALID`, `Undefined`
- `Type2 - Board Product Name1`, `Type2 - Board Vendor Name1`
- `Base Board Serial Number`

Separately, `-contains` is implicitly case-insensitive.
**Fix:** Extend the list and use `-icontains` to make the case-insensitivity explicit.

### IN-03: `$script:SpecData` is not type-checked; any stray output object becomes the spec data (carried forward, deferred to Phase 3)

**File:** `Akari.ps1:516`
**Issue:** This is unchanged. The tick takes the last object the job emits. Any stray output after the hashtable replaces the spec data with a non-hashtable.
**Fix:** `$script:SpecData = $result | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1`

### IN-04: CPU "Cores" silently falls back to the logical-processor count (new, pre-existing Phase 1 code)

**File:** `Akari.ps1:153-154`
**Issue:** When `NumberOfCores` is 0 or null, `Cores` is set to `NumberOfLogicalProcessors` and counted as a successful read. On an SMT CPU this shows the thread count labelled as cores, and the Threads field shows the same number. This is invented data presented as fact, and it contradicts the "MUST NOT invent" stance applied to Disk in 02-02.
**Fix:** Drop the `elseif` fallback and leave `Cores = 'Not available'` so `_Status` becomes `Partial`. If a fallback is kept, do not count it as a success.

---

_Reviewed: 2026-10-08T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
