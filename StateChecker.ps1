# State checker: turns a Tweak's declared targets plus machine readings into a Detect result.
# Pure logic only: no UI, no registry/service reads, no side effects. Dot-sourced by Akari.ps1 and by Tests\*.Tests.ps1.
#
# A target is either .reg text, or a list of settings applied in order:
#   @{ Path = 'HKLM:\...'; Name = 'value'; Value = 0 }  |  @{ Path; Name; Absent = $true }  |  @{ Path; KeyAbsent = $true } (key deleted)
#   @{ Service = 'Name'; StartType = 'Disabled' }  |  @{ Task = '\Folder\Name'; Enabled = $false }  |  @{ Feature = 'Name'; State = 'Disabled' }
#   (a service or task can also be @{ ...; Absent = $true }; StartType is Automatic, AutomaticDelayed, Manual, Disabled, Boot or System)
# A reading (keyed by Get-SettingKey) is:  @{ Present = $true; Value = ... }  |  @{ Present = $false }  |  @{ Error = 'reason' }

# the closed set of Detect results (CONTEXT.md); 'Checking' is a display state, not a result
function Get-DetectResults {
    'Applied', 'Not applied', 'Partly applied', 'Unknown'
}

# one spelling per registry key, whatever the case or root spelling (HKLM: / HKEY_LOCAL_MACHINE)
function Get-KeyPath([string]$Path) {
    $p = $Path.Trim().TrimEnd('\')
    foreach ($r in @(
            @('HKEY_LOCAL_MACHINE', 'HKLM'), @('HKEY_CURRENT_USER', 'HKCU'),
            @('HKEY_CLASSES_ROOT', 'HKCR'), @('HKEY_USERS', 'HKU'))) {
        if ($p -match "^(Registry::)?($($r[0])|$($r[1]):?)(\\|$)") { $p = $r[1] + $p.Substring($Matches[0].TrimEnd('\').Length); break }
    }
    return $p.ToLowerInvariant()
}

# one key per registry value
function Get-SettingKey([string]$Path, [string]$Name) {
    return ((Get-KeyPath $Path) + '|' + $Name.ToLowerInvariant())
}

# .reg text -> a target (list of settings in file order). -DollarToken turns every ? into $ first: the catalogue's
# here-strings write ? where the imported file needs $. Throws on any line it does not understand.
function ConvertFrom-RegText([string]$Text, [switch]$DollarToken) {
    if ($DollarToken) { $Text = $Text.Replace('?', '$') }
    $out = [System.Collections.Generic.List[object]]::new()
    $lines = $Text -split '\r?\n'
    $key = $null
    $underDeleted = $false
    # regedit unescapes only \\ and \" inside quoted names and strings
    $unescape = { param($s) $s -replace '\\([\\"])', '$1' }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $n = $i + 1
        $line = $lines[$i].Trim()
        # hex data continues on the next line after a trailing backslash
        while ($line.EndsWith('\') -and $line -match '=\s*hex' -and $i + 1 -lt $lines.Count) { $i++; $line = $line.Substring(0, $line.Length - 1) + $lines[$i].Trim() }
        if (-not $line -or $line.StartsWith(';') -or $line -eq 'Windows Registry Editor Version 5.00' -or $line -eq 'REGEDIT4') { continue }
        if ($line -match '^\[(-?)([^\]]+)\]$') {
            $key = $Matches[2].Trim()
            $underDeleted = [bool]$Matches[1]
            if ($underDeleted) { $out.Add(@{ Path = $key; KeyAbsent = $true }) }
            continue
        }
        if ($line -notmatch '^(@|"((?:[^"\\]|\\.)*)")\s*=\s*(.*)$') { throw ".reg line ${n} not understood: $line" }
        if (-not $key) { throw ".reg line ${n}: value before any key: $line" }
        # regedit ignores values listed under a key it has just deleted
        if ($underDeleted) { continue }
        $name = if ($Matches[1] -eq '@') { '' } else { & $unescape $Matches[2] }
        $data = $Matches[3].Trim()
        if ($data -eq '-') { $out.Add(@{ Path = $key; Name = $name; Absent = $true }); continue }
        if ($data -match '^"((?:[^"\\]|\\.)*)"$') { $out.Add(@{ Path = $key; Name = $name; Value = (& $unescape $Matches[1]) }); continue }
        if ($data -match '^dword:([0-9a-fA-F]{1,8})$') { $out.Add(@{ Path = $key; Name = $name; Value = [long][Convert]::ToUInt32($Matches[1], 16) }); continue }
        if ($data -match '^hex(\(([0-9a-fA-F]+)\))?:((?:\s*[0-9a-fA-F]{1,2}\s*,?)*)$') {
            $type = if ($Matches[2]) { [Convert]::ToInt32($Matches[2], 16) } else { 3 }
            $bytes = [byte[]]@($Matches[3] -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) })
            $value = switch ($type) {
                # expandable string / multi-string: UTF-16LE, null-terminated
                2 { [Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0) }
                7 {
                    $ms = [Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0)
                    if ($ms) { , [string[]]$ms.Split([char]0) } else { , [string[]]@() }
                }
                4 { if ($bytes.Count -ne 4) { throw ".reg line ${n}: hex(4) needs 4 bytes: $line" }; [long][BitConverter]::ToUInt32($bytes, 0) }
                11 { if ($bytes.Count -ne 8) { throw ".reg line ${n}: hex(b) needs 8 bytes: $line" }; [BitConverter]::ToUInt64($bytes, 0) }
                default { , $bytes }
            }
            $out.Add(@{ Path = $key; Name = $name; Value = $value }); continue
        }
        throw ".reg line ${n} not understood: $line"
    }
    return , $out.ToArray()
}

function Test-UnderKey([string]$KeyPath, [string]$Parent) {
    return ($KeyPath -eq $Parent -or $KeyPath.StartsWith($Parent + '\'))
}

# an optional feature waiting for a restart already has its change made; a removed payload is still disabled
function ConvertTo-FeatureState([string]$State) {
    switch ($State) {
        'DisabledWithPayloadRemoved' { 'Disabled' }
        'DisablePending' { 'Disabled' }
        'EnablePending' { 'Enabled' }
        default { $State }
    }
}

# one target entry -> what kind of setting it is, its key, a label for the log, and what it expects
#   registry: @{ Path; Name; Value | Absent }   service: @{ Service; StartType | Absent }
#   task: @{ Task = '\Path\Name'; Enabled | Absent }   feature: @{ Feature; State }
function Get-EntryInfo($s) {
    $absent = [bool]$s.Absent
    if ($s.Service) {
        $v = if ($s.StartType -eq 'Auto') { 'Automatic' } else { $s.StartType }
        return @{ Kind = 'Service'; Target = $s.Service; Key = 'service|' + $s.Service.ToLowerInvariant(); Label = "service $($s.Service)"; Value = $v; Absent = $absent }
    }
    if ($s.Task) {
        return @{ Kind = 'Task'; Target = $s.Task; Key = 'task|' + $s.Task.ToLowerInvariant(); Label = "task $($s.Task)"; Value = [bool]$s.Enabled; Absent = $absent }
    }
    if ($s.Feature) {
        return @{ Kind = 'Feature'; Target = $s.Feature; Key = 'feature|' + $s.Feature.ToLowerInvariant(); Label = "feature $($s.Feature)"; Value = (ConvertTo-FeatureState $s.State); Absent = $absent }
    }
    return @{ Kind = 'Registry'; Key = (Get-SettingKey $s.Path $s.Name); KeyPath = (Get-KeyPath $s.Path); Path = $s.Path; Name = $s.Name
        Label = "$($s.Path)\$($s.Name)"; Value = $s.Value; Absent = $absent }
}

# the key a reading for this entry is stored under
function Get-EntryKey($Entry) { (Get-EntryInfo $Entry).Key }

# a target in order -> what it leaves behind: the last word on each setting, plus the registry keys it deletes
function Resolve-Target($Target) {
    $list = if ($Target -is [string]) { ConvertFrom-RegText $Target } else { @($Target) }
    $values = [ordered]@{}
    $deleted = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $list) {
        if ($null -eq $s) { continue }
        if ($s.KeyAbsent) {
            # deleting a key drops every value under it that this target set earlier
            $kp = Get-KeyPath $s.Path
            foreach ($k in @($values.Keys)) { if ($values[$k].KeyPath -and (Test-UnderKey $values[$k].KeyPath $kp)) { $values.Remove($k) } }
            $deleted.Add($kp)
            continue
        }
        $info = Get-EntryInfo $s
        if ($values.Contains($info.Key)) { $values.Remove($info.Key) }
        $values[$info.Key] = $info
    }
    return @{ Values = $values; Deleted = $deleted }
}

# what a resolved target expects of one setting: its entry, absent when a deleted key covers it, or $null when it does not say
function Get-Expectation($Resolved, $Info) {
    if ($Resolved.Values.Contains($Info.Key)) { return $Resolved.Values[$Info.Key] }
    if ($Info.KeyPath) { foreach ($d in $Resolved.Deleted) { if (Test-UnderKey $Info.KeyPath $d) { return @{ Absent = $true } } } }
    return $null
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

# the compared settings: every value either target sets or deletes, minus those identical in both
# (a deleted key counts for the values the other target sets under it)
function Get-CompareSettings($ApplyTarget, $RevertTarget) {
    $a = Resolve-Target $ApplyTarget
    $r = Resolve-Target $RevertTarget
    $seen = @{}
    foreach ($side in $a, $r) {
        foreach ($k in @($side.Values.Keys)) {
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = $true
            $v = $side.Values[$k]
            # what the machine reader needs: Kind plus Path/Name (registry) or Target (service, task, feature)
            $c = @{ Key = $k; Kind = $v.Kind; Target = $v.Target; Path = $v.Path; Name = $v.Name; Label = $v.Label
                Apply = (Get-Expectation $a $v); Revert = (Get-Expectation $r $v) }
            if (-not (Test-SameExpectation $c.Apply $c.Revert)) { $c }
        }
    }
}

# targets + readings -> @{ Result; Reason }. Unknown wins; Applied / Not applied need every compared setting to match that target.
function Get-DetectResult($ApplyTarget, $RevertTarget, [hashtable]$Readings) {
    $compare = @(Get-CompareSettings $ApplyTarget $RevertTarget)
    $unread = @()
    foreach ($c in $compare) {
        $r = if ($Readings) { $Readings[$c.Key] } else { $null }
        if ($null -eq $r) { $unread += "$($c.Label): not read" }
        elseif ($r.Error) { $unread += "$($c.Label): $($r.Error)" }
        # a missing service, task or feature is unreadable, unless a target is the one that removes it
        elseif ($c.Kind -ne 'Registry' -and -not $r.Present -and -not ($c.Apply.Absent -or $c.Revert.Absent)) { $unread += "$($c.Label): not found" }
    }
    if ($unread.Count) { return @{ Result = 'Unknown'; Reason = ($unread -join '; ') } }
    $applied = $true; $reverted = $true
    foreach ($c in $compare) {
        $r = $Readings[$c.Key]
        if ($c.Kind -eq 'Feature' -and $r.Present) { $r = @{ Present = $true; Value = (ConvertTo-FeatureState $r.Value) } }
        if ($c.Apply -and -not (Test-Expectation $c.Apply $r)) { $applied = $false }
        if ($c.Revert -and -not (Test-Expectation $c.Revert $r)) { $reverted = $false }
    }
    if ($applied) { return @{ Result = 'Applied'; Reason = $null } }
    if ($reverted) { return @{ Result = 'Not applied'; Reason = $null } }
    return @{ Result = 'Partly applied'; Reason = $null }
}
