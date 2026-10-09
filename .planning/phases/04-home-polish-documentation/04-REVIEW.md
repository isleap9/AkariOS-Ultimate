---
phase: 04-home-polish-documentation
reviewed: 2026-10-09T12:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - Akari.ps1
  - UI/MainWindow.xaml
  - README.md
findings:
  critical: 0
  warning: 3
  info: 7
  total: 10
status: issues_found
---

# Phase 4: Code Review Report

**Reviewed:** 2026-10-09T12:00:00Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Scope: `git diff b4abbad -- Akari.ps1 UI/MainWindow.xaml README.md`. That covers the Copy specs button, the shared card model (`Get-HomeModel` / `Get-HostLine` / `Get-SpecText`), clipboard handling, the Disk/RAM health colours, the spec-read watchdog (per-call `-OperationTimeoutSec`, `Deadline`, `BeginStop`, `$script:SpecStale` disposal), the removal of `Invoke-Code -ResultVar`, multi-socket CPU totals, and the README rewrite.

I checked these on this host with real `powershell.exe`:
- `$arr += @{...}` keeps a hashtable as one element.
- `Measure-Object -Sum` over null properties returns 0 and writes no error record.
- `BeginStop` ends a running `Get-CimInstance` pipeline in about 65 ms, and the handle reaches `Stopped`.
- `-OperationTimeoutSec 3` on a slow CIM query throws a catchable "Timed out" after about 3 s.
- `Win32_OperatingSystem.FreePhysicalMemory` follows "Available" memory (free plus standby), so RAM "Used" does not count the file cache. The 80/90% thresholds therefore do not raise false alarms.
- I extracted `Get-HomeModel` and `Get-SpecText` through the AST and ran them against a failed composite and a mocked two-socket read. Both gave the expected sheet, the Sockets row, and the `Bad` keys at 9% disk free and 94% RAM used.

`-ResultVar` / `ResultCollection` are gone from `Invoke-Code` and the tweak completion block. The only remaining `ResultCollection` use is the spec read's own channel, which is intended. README matches the code: the button label `Copy specs`, the thresholds (Disk below 15%/10% free, RAM above 80%/90% used, strict comparisons), and the Default-greyed-out behaviour.

No blockers. The main problems:
- The watchdog's time budget does not fit its per-call bounds, so the whole read can still be lost.
- Copy specs exports old or failed data without saying so.
- The copied sheet starts with the machine's host name, and the README tells users to paste it in public forums.

## Warnings

### WR-01: Per-call CIM timeouts do not fit inside the 20 s read deadline, so two slow classes still discard the whole read

**File:** `Akari.ps1:43`, `Akari.ps1:159,187,210,236,314,348,355,379`
**Issue:** The read makes eight CIM calls in sequence. `Win32_OperatingSystem` is queried twice, at lines 187 and 210. Each call may take up to `-OperationTimeoutSec 10`, so the worst case is about 80 s. The whole-read deadline is `$script:SpecTimeoutSec = 20`. The stated goal ("each CIM call is bounded at 10 seconds so one hung class fails only its own group", 04-03 key-decisions) only holds when exactly one class is slow. If two classes stall, the deadline is reached during the second one. This happens when WinMgmt is restarting, when a cold provider loads after boot, or when the VideoController plus BaseBoard/BIOS SMBIOS providers are slow together. The tick then takes the `$late` branch, and every group that was already read successfully is thrown away. The user gets "timed out" and either old values or six "Not available" cards. The per-call bound never gets the chance to make a partial result.
**Fix:** Derive the deadline from the per-call bound, and stop querying `Win32_OperatingSystem` twice:
```powershell
$script:CimTimeoutSec = 5
# 7 cim calls (os queried once) plus registry work and margin
$script:SpecTimeoutSec = $script:CimTimeoutSec * 7 + 5
```
Pass `-OperationTimeoutSec $CimTimeoutSec` into the runspace (or insert it into `$SpecReadCode`). In `Get-Specs`, query `Win32_OperatingSystem` once and reuse `$os` for both the RAM and the Windows group.

### WR-02: Copy specs exports old or failed values with no marker

**File:** `Akari.ps1:759`, `Akari.ps1:823-833`, `Akari.ps1:897-899`
**Issue:** `Update-Home` enables `CopySpecs` whenever `$script:SpecData` is non-null (line 759). There are three cases where the copied sheet is not the live reading the project's Core Value promises ("if the specs are wrong or stale, the page fails its purpose"):
1. While a refresh is in flight. The cards are dimmed to 0.6, but Copy still copies the previous read, including volatile RAM Used/Free and Disk Free.
2. After a failed or timed-out read with `$had = $true`. The log says "Showing last known values", but the clipboard text looks exactly like a fresh read.
3. After a failed first load. `$script:SpecData` becomes the `New-FailedSpecs` composite (line 897), so Copy is enabled and copies a sheet of "Not available" lines. Pasted into a support chat, it reads as if the machine reported no hardware.

**Fix:** Disable Copy while a read is pending, and mark old or failed data in the text:
```powershell
# Update-Home
if ($CopySpecs) { $CopySpecs.IsEnabled = ($null -ne $script:SpecData -and $null -eq $script:SpecJob -and -not $script:SpecPending) }
# tick: on success  $script:SpecFresh = $true ; on failure  $script:SpecFresh = $false
# Get-SpecText, after the header lines
if (-not $script:SpecFresh) { $lines.Add('(last read failed - values may be out of date)') }
```
Alternatively, keep Copy disabled when the only data is the failed composite (`-not $had` path).

### WR-03: Copied sheet starts with the computer name, and the README tells users to paste it into public forums

**File:** `Akari.ps1:801`, `README.md:6`
**Issue:** `Get-SpecText` always writes `$env:COMPUTERNAME` as its first line. README line 6 presents the feature as "ready to paste into a forum post or a support chat". Host names often contain the owner's real name or an organisation and asset tag (for example `JSMITH-LAPTOP` or `ACME-FIN-0231`). Copying a hardware summary should not quietly export that. The header showing the name locally is fine. Sending it to the clipboard for public posting is a privacy leak the user does not expect.
**Fix:** Leave the host name out of the copied text (start at the maker/model line), or replace it with a neutral title:
```powershell
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('System specs')
```
If the name is meant to stay, say so in README line 6 ("includes your computer name").

## Info

### IN-01: A read that finishes right at the deadline is reported as timed out and its result thrown away

**File:** `Akari.ps1:871-880`
**Issue:** `$late` is computed when `IsCompleted` is false. If the pipeline completes between that evaluation and the `if ($late)` branch, the code still takes the timeout path: it calls `BeginStop` on a finished pipeline, parks it in `SpecStale`, and discards a valid `ResultCollection`. The window is tiny, but the outcome is a false "timed out" log line and lost data.
**Fix:** Inside the `$late` branch, check again: `if ($sj.Handle.IsCompleted) { $late = $false }` before choosing the path. Or evaluate `IsCompleted` once into a local and use that local in both places.

### IN-02: No cap or back-off on abandoned reads

**File:** `Akari.ps1:837-849`, `Akari.ps1:898`, `Akari.ps1:904-910`
**Issue:** After a timeout, the log tells the user to "Switch to another page and back to Home to try again". Each retry starts a new runspace even when earlier abandoned reads are still alive in `$script:SpecStale`. `BeginStop` stopped a CIM call promptly in testing. But a pipeline stuck in something that ignores stop requests (for example a registry read on a wedged hive, or a provider that never honours cancel) never completes. That pipeline stays in the list forever, and one runspace thread leaks per Home visit.
**Fix:** In `Start-SpecRead`, if `$script:SpecStale.Count -ge 2`, skip the new read and log once ("Specs: previous reads still stuck, skipping refresh"). Or add a cooldown timestamp after a timeout.

### IN-03: Copy failure is silent, and data errors look like clipboard contention

**File:** `Akari.ps1:825-831`
**Issue:** The `catch` covers both `Get-SpecText` (a model or formatting exception) and `Clipboard.SetText`. Both cases show "Copy failed" for 2 s and nothing goes to the log drawer, so a real code bug is indistinguishable from "another program holds the clipboard".
**Fix:** Build the text outside the try block, or log the message in the catch: `Add-Log "Copy specs: $($_.Exception.Message)"`.

### IN-04: The 'Copy specs' label is hard-coded in two places

**File:** `Akari.ps1:867`, `UI/MainWindow.xaml:212`
**Issue:** The tick restores the literal `'Copy specs'`, and the XAML has the same literal. README line 6 is a third copy. If the label changes in one place, the button reverts to stale text after every copy.
**Fix:** Store the original content once at startup (`$script:CopyLabel = $CopySpecs.Content`) and restore from it.

### IN-05: Win32_LogicalDisk is filtered on the client side

**File:** `Akari.ps1:314`
**Issue:** `Get-CimInstance Win32_LogicalDisk ... | Where-Object { $_.DriveType -eq 3 }` makes the provider enumerate every logical disk first: optical, card reader, removable, and network drives. A slow empty optical drive or a stalled network mapping uses up the 10 s per-call budget and fails the whole Disk group, even though only fixed disks are wanted.
**Fix:** `Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 10 -ErrorAction Stop`

### IN-06: Health state is shown by colour alone

**File:** `Akari.ps1:688-689`, `Akari.ps1:703-704`, `Akari.ps1:811,815`
**Issue:** Low disk space and high RAM use are shown only as an amber or red foreground (WCAG 1.4.1, Use of Color). The copied text does not include the state at all, so the warning disappears in a support chat.
**Fix:** Add a short text cue when the key is not `Tx` (for example `9.0 GB (low)`), and use the same string in the copy text.

### IN-07: README tweak count does not match the registry

**File:** `README.md:2`
**Issue:** "about 127 tweaks". The `Tweaks/*.ps1` files contain 126 `Add-Tweak` registrations (Installers has 29, not 30). "About" softens this, but the number is out of date (AGENTS.md has the same drift).
**Fix:** Say "about 125" or "over 120", or update the number to 126.

---

_Reviewed: 2026-10-09T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
