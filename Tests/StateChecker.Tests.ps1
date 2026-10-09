. "$PSScriptRoot\..\StateChecker.ps1"

Describe 'Get-DetectResults' {
    It 'returns exactly the four Detect results' {
        $r = @(Get-DetectResults)
        $r.Count | Should Be 4
        foreach ($want in 'Applied', 'Not applied', 'Partly applied', 'Unknown') { ($r -contains $want) | Should Be $true }
    }

    It 'does not count Checking as a result' {
        (@(Get-DetectResults) -contains 'Checking') | Should Be $false
    }
}

# a widgets-like Tweak: one value flips 0 <-> 1, one is set by Apply and deleted by Revert
$K1 = 'HKLM:\SOFTWARE\Test\One'
$K2 = 'HKLM:\SOFTWARE\Test\Two'
$Apply = @(
    @{ Path = $K1; Name = 'value'; Value = 0 }
    @{ Path = $K2; Name = 'Allow'; Value = 0 }
)
$Revert = @(
    @{ Path = $K1; Name = 'value'; Value = 1 }
    @{ Path = $K2; Name = 'Allow'; Absent = $true }
)
function Read-Of($one, $two) {
    @{ (Get-SettingKey $K1 'value') = $one; (Get-SettingKey $K2 'Allow') = $two }
}
function Found($v) { @{ Present = $true; Value = $v } }
$Gone = @{ Present = $false }

Describe 'Get-DetectResult' {
    It 'is Applied when every compared setting matches Apply' {
        (Get-DetectResult $Apply $Revert (Read-Of (Found 0) (Found 0))).Result | Should Be 'Applied'
    }

    It 'is Not applied when every compared setting matches Revert' {
        (Get-DetectResult $Apply $Revert (Read-Of (Found 1) $Gone)).Result | Should Be 'Not applied'
    }

    It 'is Partly applied when some settings match Apply and others Revert' {
        (Get-DetectResult $Apply $Revert (Read-Of (Found 0) $Gone)).Result | Should Be 'Partly applied'
    }

    It 'is Partly applied when a value matches neither target' {
        (Get-DetectResult $Apply $Revert (Read-Of (Found 7) (Found 0))).Result | Should Be 'Partly applied'
    }

    It 'is Unknown with the reason when a setting could not be read' {
        $r = Get-DetectResult $Apply $Revert (Read-Of (Found 0) @{ Error = 'Access denied' })
        $r.Result | Should Be 'Unknown'
        $r.Reason | Should Match 'Access denied'
        $r.Reason | Should Match 'Allow'
    }

    It 'lets Unknown win over a result the other settings would give' {
        (Get-DetectResult $Apply $Revert (Read-Of (Found 0) @{ Error = 'x' })).Result | Should Be 'Unknown'
        (Get-DetectResult $Apply $Revert (Read-Of (Found 1) @{ Error = 'x' })).Result | Should Be 'Unknown'
    }

    It 'is Unknown when a compared setting has no reading at all' {
        $r = Get-DetectResult $Apply $Revert @{ (Get-SettingKey $K1 'value') = (Found 0) }
        $r.Result | Should Be 'Unknown'
        $r.Reason | Should Match 'Allow'
    }

    It 'has no reason when the result is not Unknown' {
        (Get-DetectResult $Apply $Revert (Read-Of (Found 0) (Found 0))).Reason | Should BeNullOrEmpty
    }
}

Describe 'Absent values' {
    It 'matches an absent target when the value is missing' {
        (Get-DetectResult $Apply $Revert (Read-Of (Found 1) $Gone)).Result | Should Be 'Not applied'
    }

    It 'does not match an absent target when the value is present' {
        (Get-DetectResult $Apply $Revert (Read-Of (Found 1) (Found 0))).Result | Should Be 'Partly applied'
    }

    It 'does not match a value target when the value is missing' {
        (Get-DetectResult $Apply $Revert (Read-Of (Found 0) $Gone)).Result | Should Be 'Partly applied'
    }

    It 'can be the Apply side (Apply deletes, Revert sets)' {
        $a = @(@{ Path = $K1; Name = 'x'; Absent = $true })
        $v = @(@{ Path = $K1; Name = 'x'; Value = 1 })
        $k = Get-SettingKey $K1 'x'
        (Get-DetectResult $a $v @{ $k = $Gone }).Result | Should Be 'Applied'
        (Get-DetectResult $a $v @{ $k = (Found 1) }).Result | Should Be 'Not applied'
    }
}

Describe 'Settings identical in both targets' {
    $same = @{ Path = 'HKCU:\Test\Same'; Name = 'Both'; Value = 0 }
    $a = $Apply + $same
    $r = $Revert + $same

    It 'are left out of the settings to read' {
        $keys = @(Get-CompareSettings $a $r | ForEach-Object { $_.Key })
        $keys -contains (Get-SettingKey 'HKCU:\Test\Same' 'Both') | Should Be $false
        $keys.Count | Should Be 2
    }

    It 'do not stop Not applied when the machine differs from them' {
        $read = Read-Of (Found 1) $Gone
        $read[(Get-SettingKey 'HKCU:\Test\Same' 'Both')] = (Found 5)
        (Get-DetectResult $a $r $read).Result | Should Be 'Not applied'
    }

    It 'do not make the result Unknown when they cannot be read' {
        $read = Read-Of (Found 0) (Found 0)
        $read[(Get-SettingKey 'HKCU:\Test\Same' 'Both')] = @{ Error = 'denied' }
        (Get-DetectResult $a $r $read).Result | Should Be 'Applied'
    }

    It 'treat two absent expectations as identical' {
        $x = @{ Path = $K1; Name = 'gone'; Absent = $true }
        @(Get-CompareSettings ($Apply + $x) ($Revert + $x)).Count | Should Be 2
    }
}

Describe 'Setting keys and values' {
    It 'matches a reading whatever the case or root spelling of the path' {
        (Get-SettingKey 'HKLM:\SOFTWARE\Test\One' 'Value') | Should Be (Get-SettingKey 'HKEY_LOCAL_MACHINE\software\test\one\' 'value')
        (Get-SettingKey 'HKCU:\X' 'n') | Should Be (Get-SettingKey 'HKEY_CURRENT_USER\X' 'n')
    }

    It 'keeps different values on the same key apart' {
        (Get-SettingKey $K1 'a') | Should Not Be (Get-SettingKey $K1 'b')
    }

    It 'compares a DWORD read back as a negative Int32 with its unsigned value' {
        $a = @(@{ Path = $K1; Name = 'v'; Value = 4294967295 })
        $v = @(@{ Path = $K1; Name = 'v'; Value = 0 })
        (Get-DetectResult $a $v @{ (Get-SettingKey $K1 'v') = (Found ([int]-1)) }).Result | Should Be 'Applied'
    }

    It 'compares strings' {
        $a = @(@{ Path = $K1; Name = 's'; Value = '%SystemRoot%\System32\systray.exe' })
        $v = @(@{ Path = $K1; Name = 's'; Absent = $true })
        (Get-DetectResult $a $v @{ (Get-SettingKey $K1 's') = (Found '%SystemRoot%\System32\systray.exe') }).Result | Should Be 'Applied'
        (Get-DetectResult $a $v @{ (Get-SettingKey $K1 's') = (Found 'other.exe') }).Result | Should Be 'Partly applied'
    }

    It 'does not treat a number and a different string as equal' {
        (Test-SettingValue 0 '') | Should Be $false
        (Test-SettingValue 1 '1') | Should Be $true
    }

    It 'compares binary and multi-string values element by element' {
        (Test-SettingValue ([byte[]](1, 2, 3)) ([byte[]](1, 2, 3))) | Should Be $true
        (Test-SettingValue ([byte[]](1, 2, 3)) ([byte[]](1, 2))) | Should Be $false
        (Test-SettingValue @('a', 'b') ([string[]]('a', 'b'))) | Should Be $true
    }
}
