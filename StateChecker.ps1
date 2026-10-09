# State checker: turns a Tweak's declared targets plus machine readings into a Detect result.
# Pure logic only: no UI, no registry/service reads, no side effects. Dot-sourced by Akari.ps1 and by Tests\*.Tests.ps1.
#
# A target is a list of settings:  @{ Path = 'HKLM:\...'; Name = 'value'; Value = 0 }  or  @{ Path; Name; Absent = $true }
# A reading (keyed by Get-SettingKey) is:  @{ Present = $true; Value = ... }  |  @{ Present = $false }  |  @{ Error = 'reason' }

# the closed set of Detect results (CONTEXT.md); 'Checking' is a display state, not a result
function Get-DetectResults {
    'Applied', 'Not applied', 'Partly applied', 'Unknown'
}

# one key per registry value, whatever the case or root spelling (HKLM: / HKEY_LOCAL_MACHINE)
function Get-SettingKey([string]$Path, [string]$Name) {
    $p = $Path.Trim().TrimEnd('\')
    foreach ($r in @(
            @('HKEY_LOCAL_MACHINE', 'HKLM'), @('HKEY_CURRENT_USER', 'HKCU'),
            @('HKEY_CLASSES_ROOT', 'HKCR'), @('HKEY_USERS', 'HKU'))) {
        if ($p -match "^(Registry::)?($($r[0])|$($r[1]):?)(\\|$)") { $p = $r[1] + $p.Substring($Matches[0].TrimEnd('\').Length); break }
    }
    return ($p + '|' + $Name).ToLowerInvariant()
}

# numbers compare by value (a DWORD read back as a negative Int32 equals its unsigned form), arrays element by element, the rest as text
function Test-SettingValue($Expected, $Actual) {
    $isNum = { param($v) $v -is [int] -or $v -is [long] -or $v -is [uint32] -or $v -is [uint64] -or $v -is [int16] -or $v -is [byte] -or $v -is [double] }
    $unsigned = {
        param($v)
        if ($v -is [int] -and $v -lt 0) { return [decimal][BitConverter]::ToUInt32([BitConverter]::GetBytes($v), 0) }
        if ($v -is [long] -and $v -lt 0) { return [decimal][BitConverter]::ToUInt64([BitConverter]::GetBytes($v), 0) }
        return [decimal]$v
    }
    if ((& $isNum $Expected) -and (& $isNum $Actual)) { return ((& $unsigned $Expected) -eq (& $unsigned $Actual)) }
    if ($Expected -is [array] -or $Actual -is [array]) {
        $e = @($Expected); $a = @($Actual)
        if ($e.Count -ne $a.Count) { return $false }
        for ($i = 0; $i -lt $e.Count; $i++) { if (-not (Test-SettingValue $e[$i] $a[$i])) { return $false } }
        return $true
    }
    return ([string]$Expected -eq [string]$Actual)
}

# does one expectation (a target entry, or $null when the target does not mention the setting) hold for one reading
function Test-Expectation($Want, $Reading) {
    if ($Want.Absent) { return (-not $Reading.Present) }
    return ([bool]$Reading.Present -and (Test-SettingValue $Want.Value $Reading.Value))
}

function Test-SameExpectation($A, $B) {
    if ($null -eq $A -or $null -eq $B) { return $false }
    if ($A.Absent -or $B.Absent) { return ([bool]$A.Absent -eq [bool]$B.Absent) }
    return (Test-SettingValue $A.Value $B.Value)
}

# the compared settings: every setting either target mentions, minus those identical in both
function Get-CompareSettings([object[]]$ApplyTarget, [object[]]$RevertTarget) {
    $order = [System.Collections.Generic.List[string]]::new()
    $map = @{}
    foreach ($side in 'Apply', 'Revert') {
        $list = if ($side -eq 'Apply') { $ApplyTarget } else { $RevertTarget }
        foreach ($s in @($list)) {
            if ($null -eq $s) { continue }
            $k = Get-SettingKey $s.Path $s.Name
            if (-not $map.ContainsKey($k)) { $map[$k] = @{ Key = $k; Path = $s.Path; Name = $s.Name; Apply = $null; Revert = $null }; $order.Add($k) }
            $map[$k][$side] = $s
        }
    }
    foreach ($k in $order) {
        $c = $map[$k]
        if (-not (Test-SameExpectation $c.Apply $c.Revert)) { $c }
    }
}

# targets + readings -> @{ Result; Reason }. Unknown wins; Applied / Not applied need every compared setting to match that target.
function Get-DetectResult([object[]]$ApplyTarget, [object[]]$RevertTarget, [hashtable]$Readings) {
    $compare = @(Get-CompareSettings $ApplyTarget $RevertTarget)
    $unread = @()
    foreach ($c in $compare) {
        $r = if ($Readings) { $Readings[$c.Key] } else { $null }
        if ($null -eq $r) { $unread += "$($c.Path)\$($c.Name): not read" }
        elseif ($r.Error) { $unread += "$($c.Path)\$($c.Name): $($r.Error)" }
    }
    if ($unread.Count) { return @{ Result = 'Unknown'; Reason = ($unread -join '; ') } }
    $applied = $true; $reverted = $true
    foreach ($c in $compare) {
        $r = $Readings[$c.Key]
        if ($c.Apply -and -not (Test-Expectation $c.Apply $r)) { $applied = $false }
        if ($c.Revert -and -not (Test-Expectation $c.Revert $r)) { $reverted = $false }
    }
    if ($applied) { return @{ Result = 'Applied'; Reason = $null } }
    if ($reverted) { return @{ Result = 'Not applied'; Reason = $null } }
    return @{ Result = 'Partly applied'; Reason = $null }
}
