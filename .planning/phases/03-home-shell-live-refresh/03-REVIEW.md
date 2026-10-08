---
phase: 03-home-shell-live-refresh
reviewed: 2026-10-08T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - Akari.ps1
  - UI/MainWindow.xaml
findings:
  critical: 0
  warning: 3
  info: 7
  total: 10
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-10-08
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Scope: `git diff 2394fc1 -- Akari.ps1 UI/MainWindow.xaml`. That covers the Home default category, the sidebar Home item and divider, the `HomePanel` XAML, `$HostIdentityFunc`/`$SpecReadCode`, `Start-SpecRead`/`Set-HomeDim`, the spec harvest in the 150 ms tick, and the card renderer (`Update-Home` and its helpers). The system-drive-only Disk card (ac5bff8) was requested by the user, so it is not reported as a defect.

The second-runspace design holds up. The one-flight guard, the deferral while busy, the harvest order ahead of the tweak block, object-built cards with no XAML string interpolation of spec values, and invariant-culture number formatting all trace correctly. I found no blocker.

The main risk is robustness of the live read. It has no timeout and no way to recover, so one stuck CIM query silently freezes Home for the rest of the session. There is also a dormant pre-Phase-3 harvest path that would overwrite `$script:SpecData` with the old shape. The rest are smaller edge cases and dead code.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: A stuck spec read freezes Home for the whole session (no timeout, no recovery)

**File:** `Akari.ps1:739`, `Akari.ps1:751`, `Akari.ps1:770` (CIM calls at `Akari.ps1:152,175,198,224,302,336,343,367`)
**Issue:** `Start-SpecRead` returns early whenever `$script:SpecJob` is non-null (line 739). The tick only clears `$script:SpecJob` once `$sj.Handle.IsCompleted` becomes true (line 770). None of the eight `Get-CimInstance` calls in `$SpecReadCode` set `-OperationTimeoutSec`. Nothing stops the pipeline or gives up on it.

When a WMI provider hangs, the read never finishes. Typical causes are a hung display driver behind `Win32_VideoController`, a corrupt WMI repository, or a stalled `winmgmt` service. Once that happens:
- The cards and `HostSub` stay dimmed at 0.6 forever (line 628 keeps `$dim` true).
- Every later Home show is ignored by the one-flight guard, so the page never refreshes again this session.
- The user sees no log line, because the failure path at line 790 only runs after completion.

This breaks the core value ("accurate, live system specs") with no message to the user.
**Fix:** Bound each query and add a watchdog that abandons the job:
```powershell
# in $GetSpecsFunc / $HostIdentityFunc
Get-CimInstance -ClassName Win32_Processor -OperationTimeoutSec 10 -ErrorAction Stop

# in Start-SpecRead
$script:SpecJob = @{ ...; Started = [DateTime]::UtcNow }

# in the tick, before the IsCompleted check
if ($sj -and -not $sj.Handle.IsCompleted -and ([DateTime]::UtcNow - $sj.Started).TotalSeconds -gt 30) {
    try { $sj.Ps.BeginStop($null, $null) | Out-Null } catch { }
    $script:SpecJob = $null
    Add-Log 'Specs: Read timed out. Showing last known values.'
    Update-Home
}
```
(Dispose the abandoned runspace after the stop completes, so the UI thread never blocks on it.)

### WR-02: Dormant `-ResultVar` harvest overwrites `$script:SpecData` with the old shape

**File:** `Akari.ps1:797-801` (with `Akari.ps1:508-524`)
**Issue:** Phase 3 changed `$script:SpecData` into the composite `@{ Specs; Host }`, and everything in `Update-Home` (lines 643, 716-722) and `Set-HomeDim` depends on that shape. The tweak-completion block still has the Phase 2 path. Whenever any `Invoke-Code ... -ResultVar` finishes, that path writes the raw last output into `$script:SpecData`, or `$null` when there is no output. It also ignores the `$ResultVar` name it was given.

There is no caller today. But the first call (for example a Phase 4 "copy specs" helper reusing `Invoke-Code -ResultVar`) would either:
- reset Home to the first-load placeholder (`$null`), or
- store a bare `Get-Specs` hashtable, so `$script:SpecData.Specs` is `$null`. Every card then shows empty or `Not available` values, and the header falls back for no reason.

Nothing errors, so the corruption is silent.
**Fix:** Delete the `ResultVar` branch from `Invoke-Code` and the tick, since the spec read now has its own channel. If it has to stay, write to a variable named by the parameter instead of hard-coding `SpecData`:
```powershell
if ($j.ResultVar) {
    [void]$j.Ps.EndInvoke($j.Handle)
    $r = $j.ResultCollection
    Set-Variable -Scope Script -Name $j.ResultVar -Value $(if ($r.Count) { $r[$r.Count - 1] } else { $null })
}
```

### WR-03: CPU card under-reports cores and threads on multi-socket machines

**File:** `Akari.ps1:152-158` (rendered at `Akari.ps1:649-652`)
**Issue:** `Get-Specs` keeps only the first `Win32_Processor` instance (`Select-Object -First 1`). On a dual-socket workstation or server, both supported targets, the new CPU card shows half the real core and thread count, and nothing hints that a second package exists. The code comes from Phase 2, but this phase is the first to show it to the user as the machine's totals, and wrong specs defeat the page's purpose.
**Fix:** Add up across all sockets and show the socket count when it is greater than 1:
```powershell
$cpus = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
$cpu  = $cpus[0]
$cores   = ($cpus | Measure-Object NumberOfCores -Sum).Sum
$threads = ($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum
$result.CPU.Sockets = $cpus.Count
```

## Info

### IN-01: Showing Home while a read is in flight does not start a fresh read

**File:** `Akari.ps1:739`
**Issue:** Suppose the user leaves Home and comes back while the earlier read is still running. The second show reuses that older read and starts nothing new, so the values were captured before the user's latest visit. This is harmless for fast reads, but it bends "refreshed every time Home is shown".
**Fix:** If a read is in flight, set `$script:SpecPending = $true`, and start one more read in the harvest block when `SpecPending` is set and `$script:Cat -eq 'Home'`.

### IN-02: A leftover `SpecPending` starts a read after the user has left Home

**File:** `Akari.ps1:741`, `Akari.ps1:814`
**Issue:** Here is the sequence:
1. The user opens Home during a tweak, which sets `SpecPending`.
2. The user moves to another category. Nothing clears the flag.
3. The tweak finishes, and line 814 starts a full CIM read anyway.
4. Line 792 then rebuilds the hidden card grid.

The read is wasted work, and it races with whatever the user does next.
**Fix:** `if ($script:SpecPending -and $script:Cat -eq 'Home' -and -not $Search.Text) { Start-SpecRead } else { $script:SpecPending = $false }`.

### IN-03: "Showing last known values" can refer to the failed skeleton

**File:** `Akari.ps1:771`, `Akari.ps1:788-789`
**Issue:** If the first read fails, `New-FailedSpecs` is stored, so `$had` is true on the next attempt. If that attempt also fails, the log says "Showing last known values" while every card shows `Not available`, and the "switch page to retry" hint is gone.
**Fix:** Track a real success flag, for example `$script:SpecOk`, and base `$tail` on it instead of on `$null -ne $script:SpecData`.

### IN-04: Disk card loop and divider are now dead code

**File:** `Akari.ps1:683-695`
**Issue:** After ac5bff8 the filter matches at most one volume, because `DeviceID` is unique. So `if ($i -gt 0) { Add-Divider $card }` and the multi-block loop never run beyond the first pass. The comment "zero volumes: headline only, no rows and no dividers" is also outdated.
**Fix:** Replace the loop with `$v = $list | Select-Object -First 1` and drop the divider branch and the stale comment.

### IN-05: System drive on removable media shows "Not available"

**File:** `Akari.ps1:302`, `Akari.ps1:683`
**Issue:** `Get-Specs` keeps only `DriveType -eq 3`. When Windows boots from a USB or removable-class disk (Windows To Go, some portable installs), `$env:SystemDrive` has DriveType 2. The Disk card then headlines `Not available` even though the drive is readable.
**Fix:** Select the system drive by DeviceID whatever its DriveType: `Where-Object { $_.DriveType -eq 3 -or $_.DeviceID -eq $env:SystemDrive }`.

### IN-06: Spec runspace is not cleaned up on error or on window close

**File:** `Akari.ps1:742-751`, `Akari.ps1:960`
**Issue:** If `BeginInvoke` throws after `$rs.Open()`, the runspace and PowerShell objects leak, because `$script:SpecJob` is never assigned. On close, `Add_Closing` stops only the timer, so an in-flight spec read (or tweak) is never stopped or disposed.
**Fix:** Wrap the setup in try/catch that disposes `$ps`/`$rs` on failure. In `Add_Closing`, call `$script:SpecJob.Ps.Stop()` and dispose it when it is non-null.

### IN-07: Header host name is the 15-character NetBIOS name

**File:** `Akari.ps1:625`
**Issue:** `$env:COMPUTERNAME` is the upper-cased NetBIOS name, cut to 15 characters. Machines with longer DNS host names see a truncated, re-cased name that does not match Settings > System > About.
**Fix:** Use `[System.Net.Dns]::GetHostName()`, or read `Win32_ComputerSystem.DNSHostName` inside the background read and keep `$env:COMPUTERNAME` as the instant placeholder.

---

_Reviewed: 2026-10-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
