. "$PSScriptRoot\..\StateChecker.ps1"

# service startup types, scheduled-task state and optional-feature state as declared targets
$Gone = @{ Present = $false }
function New-Reading($v) { @{ Present = $true; Value = $v } }
function Get-Result($ApplyTarget, $RevertTarget, [hashtable]$Readings) {
    (Get-DetectResult $ApplyTarget $RevertTarget $Readings).Result
}

Describe 'Service startup types' {
    $a = @(@{ Service = 'DiagTrack'; StartType = 'Disabled' })
    $r = @(@{ Service = 'DiagTrack'; StartType = 'Automatic' })
    $k = Get-EntryKey @{ Service = 'DiagTrack' }

    It 'is Applied / Not applied by start type' {
        Get-Result $a $r @{ $k = (New-Reading 'Disabled') } | Should Be 'Applied'
        Get-Result $a $r @{ $k = (New-Reading 'Automatic') } | Should Be 'Not applied'
        Get-Result $a $r @{ $k = (New-Reading 'Manual') } | Should Be 'Partly applied'
    }

    It 'accepts Auto for Automatic and ignores case' {
        Get-Result @(@{ Service = 'DiagTrack'; StartType = 'Auto' }) $a @{ $k = (New-Reading 'automatic') } | Should Be 'Applied'
    }

    It 'is Unknown with a reason when the service does not exist and no target removes it' {
        $d = Get-DetectResult $a $r @{ $k = $Gone }
        $d.Result | Should Be 'Unknown'
        $d.Reason | Should Match 'DiagTrack'
        $d.Reason | Should Match 'not found'
    }

    It 'is Unknown when the service could not be read' {
        Get-Result $a $r @{ $k = @{ Error = 'Access denied' } } | Should Be 'Unknown'
    }

    It 'treats a missing service as Not applied when Revert removes it' {
        $ap = @(@{ Service = 'Set Timer Resolution Service'; StartType = 'Automatic' })
        $rv = @(@{ Service = 'Set Timer Resolution Service'; Absent = $true })
        $ks = Get-EntryKey @{ Service = 'set timer resolution service' }
        Get-Result $ap $rv @{ $ks = $Gone } | Should Be 'Not applied'
        Get-Result $ap $rv @{ $ks = (New-Reading 'Automatic') } | Should Be 'Applied'
        Get-Result $ap $rv @{ $ks = (New-Reading 'Manual') } | Should Be 'Partly applied'
    }

    It 'names the service in its key, apart from registry values' {
        $k | Should Not Be (Get-SettingKey 'HKLM:\DiagTrack' '')
    }
}

Describe 'Scheduled tasks' {
    $t = '\Microsoft\Windows\Defrag\ScheduledDefrag'
    $a = @(@{ Task = $t; Enabled = $false })
    $r = @(@{ Task = $t; Enabled = $true })
    $k = Get-EntryKey @{ Task = $t }

    It 'is Applied / Not applied by enabled state' {
        Get-Result $a $r @{ $k = (New-Reading $false) } | Should Be 'Applied'
        Get-Result $a $r @{ $k = (New-Reading $true) } | Should Be 'Not applied'
    }

    It 'is Unknown when the task does not exist and no target removes it' {
        $d = Get-DetectResult $a $r @{ $k = $Gone }
        $d.Result | Should Be 'Unknown'
        $d.Reason | Should Match 'ScheduledDefrag'
    }

    It 'treats a missing task as matching a target that removes it' {
        Get-Result @(@{ Task = $t; Absent = $true }) $r @{ $k = $Gone } | Should Be 'Applied'
    }

    It 'is Unknown when the task could not be read' {
        Get-Result $a $r @{ $k = @{ Error = 'denied' } } | Should Be 'Unknown'
    }

    It 'matches the task whatever the case' {
        $k | Should Be (Get-EntryKey @{ Task = $t.ToUpperInvariant() })
    }
}

Describe 'Optional features' {
    $a = @(@{ Feature = 'SMB1Protocol'; State = 'Disabled' })
    $r = @(@{ Feature = 'SMB1Protocol'; State = 'Enabled' })
    $k = Get-EntryKey @{ Feature = 'SMB1Protocol' }

    It 'is Applied / Not applied by state' {
        Get-Result $a $r @{ $k = (New-Reading 'Disabled') } | Should Be 'Applied'
        Get-Result $a $r @{ $k = (New-Reading 'Enabled') } | Should Be 'Not applied'
    }

    It 'counts a removed payload as disabled' {
        Get-Result $a $r @{ $k = (New-Reading 'DisabledWithPayloadRemoved') } | Should Be 'Applied'
    }

    It 'counts a change waiting for restart as made' {
        Get-Result $a $r @{ $k = (New-Reading 'DisablePending') } | Should Be 'Applied'
        Get-Result $a $r @{ $k = (New-Reading 'EnablePending') } | Should Be 'Not applied'
    }

    It 'is Unknown when the feature does not exist on this edition' {
        $d = Get-DetectResult $a $r @{ $k = $Gone }
        $d.Result | Should Be 'Unknown'
        $d.Reason | Should Match 'SMB1Protocol'
    }

    It 'is Unknown when the feature could not be read' {
        Get-Result $a $r @{ $k = @{ Error = 'DISM failed' } } | Should Be 'Unknown'
    }
}

Describe 'Mixed kinds in one target' {
    $a = @(
        @{ Service = 'Svc'; StartType = 'Automatic' }
        @{ Path = 'HKLM:\SYSTEM\Test'; Name = 'V'; Value = 1 }
    )
    $r = @(
        @{ Service = 'Svc'; Absent = $true }
        @{ Path = 'HKLM:\SYSTEM\Test'; Name = 'V'; Absent = $true }
    )
    $ks = Get-EntryKey @{ Service = 'Svc' }
    $kv = Get-EntryKey @{ Path = 'HKLM:\SYSTEM\Test'; Name = 'V' }

    It 'needs every kind to match' {
        Get-Result $a $r @{ $ks = (New-Reading 'Automatic'); $kv = (New-Reading 1) } | Should Be 'Applied'
        Get-Result $a $r @{ $ks = $Gone; $kv = $Gone } | Should Be 'Not applied'
        Get-Result $a $r @{ $ks = (New-Reading 'Automatic'); $kv = $Gone } | Should Be 'Partly applied'
    }

    It 'tells the reader what kind each setting is' {
        $c = @(Get-CompareSettings $a $r)
        ($c | Where-Object { $_.Key -eq $ks }).Kind | Should Be 'Service'
        ($c | Where-Object { $_.Key -eq $ks }).Target | Should Be 'Svc'
        ($c | Where-Object { $_.Key -eq $kv }).Kind | Should Be 'Registry'
    }

    It 'gives a registry entry the same key as Get-SettingKey' {
        $kv | Should Be (Get-SettingKey 'HKLM:\SYSTEM\Test' 'V')
    }
}
