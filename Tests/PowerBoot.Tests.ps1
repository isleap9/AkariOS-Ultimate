. "$PSScriptRoot\TestHelpers.ps1"

# power plans, power setting values and boot (BCD) settings as declared targets
$NotHere = @{ NotOnMachine = $true }

$Akari = '99999999-9999-9999-9999-999999999999'
$Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
$Proc = '54533251-82be-4824-96c1-47b60b740d00'
$MinState = '893dee8e-2bef-41e0-89c6-b55d0929964c'
$Gfx = '44f3beca-a7c0-460e-9df2-bb8b99e0cba6'
$GfxPlan = '3619c3f2-afb2-4afc-b0e9-e7fef372de36'

Describe 'Active power plan' {
    $a = @(@{ ActivePowerScheme = $Akari })
    $r = @(@{ ActivePowerScheme = $Balanced })
    $k = Get-EntryKey @{ ActivePowerScheme = $Akari }

    It 'is Applied / Not applied / Partly applied by the active plan' {
        Get-Result $a $r @{ $k = (New-Reading $Akari) } | Should Be 'Applied'
        Get-Result $a $r @{ $k = (New-Reading $Balanced.ToUpperInvariant()) } | Should Be 'Not applied'
        Get-Result $a $r @{ $k = (New-Reading '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') } | Should Be 'Partly applied'
    }

    It 'is Unknown when the active plan could not be read' {
        Get-Result $a $r @{ $k = @{ Error = 'powercfg failed' } } | Should Be 'Unknown'
    }
}

Describe 'Power setting values' {
    $a = @(
        @{ ActivePowerScheme = $Akari }
        @{ PowerScheme = $Akari; Subgroup = $Proc; Setting = $MinState; AC = 100; DC = 100 }
    )
    # revert deletes the plan, and with it every value in it
    $r = @(
        @{ ActivePowerScheme = $Balanced }
        @{ PowerScheme = $Akari; Absent = $true }
    )
    $ka = Get-EntryKey @{ ActivePowerScheme = $Akari }
    $kac = Get-EntryKey @{ PowerScheme = $Akari; Subgroup = $Proc; Setting = $MinState; Source = 'AC' }
    $kdc = Get-EntryKey @{ PowerScheme = $Akari; Subgroup = $Proc; Setting = $MinState; Source = 'DC' }

    It 'compares the plugged-in (AC) and battery (DC) values separately' {
        $kac | Should Not Be $kdc
        @(Get-CompareSettings $a $r).Count | Should Be 3
    }

    It 'is Applied when the plan is active and both values match' {
        Get-Result $a $r @{ $ka = (New-Reading $Akari); $kac = (New-Reading 100); $kdc = (New-Reading 100) } | Should Be 'Applied'
    }

    It 'is Partly applied when one value was changed by hand' {
        Get-Result $a $r @{ $ka = (New-Reading $Akari); $kac = (New-Reading 100); $kdc = (New-Reading 5) } | Should Be 'Partly applied'
    }

    It 'is Not applied when the plan was deleted and another is active' {
        Get-Result $a $r @{ $ka = (New-Reading $Balanced); $kac = $Gone; $kdc = $Gone } | Should Be 'Not applied'
    }

    It 'is Unknown when a value could not be read' {
        Get-Result $a $r @{ $ka = (New-Reading $Akari); $kac = @{ Error = 'x' }; $kdc = (New-Reading 100) } | Should Be 'Unknown'
    }

    It 'skips a value this PC does not have (no battery, no Intel graphics)' {
        $a2 = $a + @{ PowerScheme = $Akari; Subgroup = $Gfx; Setting = $GfxPlan; AC = 2; DC = 2 }
        $kg = Get-EntryKey @{ PowerScheme = $Akari; Subgroup = $Gfx; Setting = $GfxPlan; Source = 'AC' }
        $kgd = Get-EntryKey @{ PowerScheme = $Akari; Subgroup = $Gfx; Setting = $GfxPlan; Source = 'DC' }
        $read = @{ $ka = (New-Reading $Akari); $kac = (New-Reading 100); $kdc = (New-Reading 100); $kg = $NotHere; $kgd = $NotHere }
        Get-Result $a2 $r $read | Should Be 'Applied'
    }

    It 'matches plan and value ids whatever the case' {
        $kac | Should Be (Get-EntryKey @{ PowerScheme = $Akari.ToUpperInvariant(); Subgroup = $Proc.ToUpperInvariant(); Setting = $MinState; Source = 'ac' })
    }

    It 'can declare one source only' {
        @(Get-CompareSettings @(@{ PowerScheme = $Akari; Subgroup = $Proc; Setting = $MinState; AC = 100 }) @()).Count | Should Be 1
    }
}

Describe 'Boot (BCD) settings' {
    $a = @(@{ Boot = 'nx'; Value = 'AlwaysOff' })
    $r = @(@{ Boot = 'nx'; Absent = $true })
    $k = Get-EntryKey @{ Boot = 'nx' }

    It 'is Applied / Not applied by the boot setting' {
        Get-Result $a $r @{ $k = (New-Reading 'AlwaysOff') } | Should Be 'Applied'
        Get-Result $a $r @{ $k = $Gone } | Should Be 'Not applied'
        Get-Result $a $r @{ $k = (New-Reading 'OptIn') } | Should Be 'Partly applied'
    }

    It 'ignores case in the value' {
        Get-Result $a $r @{ $k = (New-Reading 'alwaysoff') } | Should Be 'Applied'
    }

    It 'is Unknown when the boot settings could not be read' {
        $d = Get-DetectResult $a $r @{ $k = @{ Error = 'Access is denied' } }
        $d.Result | Should Be 'Unknown'
        $d.Reason | Should Match 'nx'
    }

    It 'reads the current boot entry unless another is named' {
        $k | Should Be (Get-EntryKey @{ Boot = 'NX'; BootEntry = '{current}' })
        $k | Should Not Be (Get-EntryKey @{ Boot = 'nx'; BootEntry = '{default}' })
    }

    It 'tells the reader which entry and element to read' {
        $c = @(Get-CompareSettings $a $r)[0]
        $c.Kind | Should Be 'Boot'
        $c.Target | Should Be 'nx'
        $c.BootEntry | Should Be '{current}'
    }
}
