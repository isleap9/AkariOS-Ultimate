. "$PSScriptRoot\..\StateChecker.ps1"

# .reg text as a declared target: parsed by the state checker, judged through Get-DetectResult
$RK = 'HKEY_CURRENT_USER\Software\AkariTest'
$Gone = @{ Present = $false }
function New-Reading($v) { @{ Present = $true; Value = $v } }
function New-RegText([string]$Body) { "Windows Registry Editor Version 5.00`r`n`r`n; test`r`n[$RK]`r`n$Body`r`n" }
function Get-RegResult($ApplyTarget, $RevertTarget, [hashtable]$Readings) {
    (Get-DetectResult $ApplyTarget $RevertTarget $Readings).Result
}

Describe '.reg text targets: value types' {
    It 'reads dword values' {
        $k = Get-SettingKey $RK 'V'
        $a = New-RegText '"V"=dword:00000002'; $r = New-RegText '"V"=dword:00000000'
        Get-RegResult $a $r @{ $k = (New-Reading 2) } | Should Be 'Applied'
        Get-RegResult $a $r @{ $k = (New-Reading 0) } | Should Be 'Not applied'
    }

    It 'reads a high dword as unsigned (the registry hands it back as a negative Int32)' {
        $k = Get-SettingKey $RK 'V'
        Get-RegResult (New-RegText '"V"=dword:ff191919') (New-RegText '"V"=dword:00000000') @{ $k = (New-Reading ([int]-15132391)) } | Should Be 'Applied'
    }

    It 'reads strings with escaped backslashes and quotes' {
        $k = Get-SettingKey $RK 'S'
        $a = New-RegText '"S"="%SystemRoot%\\System32\\a \"b\".exe"'; $r = New-RegText '"S"=-'
        Get-RegResult $a $r @{ $k = (New-Reading '%SystemRoot%\System32\a "b".exe') } | Should Be 'Applied'
    }

    It 'reads the default value (@) as the unnamed value' {
        $k = Get-SettingKey $RK ''
        Get-RegResult (New-RegText '@="URL:x"') (New-RegText '@=-') @{ $k = (New-Reading 'URL:x') } | Should Be 'Applied'
    }

    It 'keeps a value literally named (Default) apart from the default value' {
        $keys = @(Get-CompareSettings (New-RegText '"(Default)"="x"') (New-RegText '"(Default)"=-') | ForEach-Object { $_.Key })
        $keys | Should Be (Get-SettingKey $RK '(Default)')
        (Get-SettingKey $RK '(Default)') | Should Not Be (Get-SettingKey $RK '')
    }

    It 'reads binary values, including ones split over several lines' {
        $k = Get-SettingKey $RK 'B'
        $a = New-RegText "`"B`"=hex:64,64,64,00,\`r`n  6b,6b,\`r`n  00"
        $r = New-RegText '"B"=hex:00'
        Get-RegResult $a $r @{ $k = (New-Reading ([byte[]](0x64, 0x64, 0x64, 0, 0x6b, 0x6b, 0))) } | Should Be 'Applied'
        Get-RegResult $a $r @{ $k = (New-Reading ([byte[]](0x64, 0x64))) } | Should Be 'Partly applied'
    }

    It 'reads qword values' {
        $k = Get-SettingKey $RK 'Q'
        Get-RegResult (New-RegText '"Q"=hex(b):00,01,00,00,00,00,00,00') (New-RegText '"Q"=-') @{ $k = (New-Reading ([long]256)) } | Should Be 'Applied'
    }

    It 'reads dword values written as hex(4)' {
        $k = Get-SettingKey $RK 'D'
        Get-RegResult (New-RegText '"D"=hex(4):02,01,00,00') (New-RegText '"D"=-') @{ $k = (New-Reading 258) } | Should Be 'Applied'
    }

    It 'reads expandable strings' {
        $k = Get-SettingKey $RK 'E'
        # "%A%" in UTF-16LE plus the terminating null
        Get-RegResult (New-RegText '"E"=hex(2):25,00,41,00,25,00,00,00') (New-RegText '"E"=-') @{ $k = (New-Reading '%A%') } | Should Be 'Applied'
    }

    It 'reads multi-string values' {
        $k = Get-SettingKey $RK 'M'
        # "a", "b" in UTF-16LE, each null-terminated, plus the closing null
        $a = New-RegText "`"M`"=hex(7):61,00,00,00,62,00,\`r`n  00,00,00,00"
        Get-RegResult $a (New-RegText '"M"=-') @{ $k = (New-Reading ([string[]]('a', 'b'))) } | Should Be 'Applied'
    }

    It 'reads empty strings' {
        $k = Get-SettingKey $RK 'URL Protocol'
        Get-RegResult (New-RegText '"URL Protocol"=""') (New-RegText '"URL Protocol"=-') @{ $k = (New-Reading '') } | Should Be 'Applied'
    }
}

Describe '.reg text targets: deletions' {
    It 'treats a value deletion as absent' {
        $k = Get-SettingKey $RK 'V'
        $a = New-RegText '"V"=dword:00000001'; $r = New-RegText '"V"=-'
        Get-RegResult $a $r @{ $k = $Gone } | Should Be 'Not applied'
        Get-RegResult $a $r @{ $k = (New-Reading 1) } | Should Be 'Applied'
    }

    It 'treats a key deletion as absent for every value under that key and its subkeys' {
        $a = "Windows Registry Editor Version 5.00`r`n[$RK]`r`n`"V`"=dword:00000000`r`n[$RK\Sub]`r`n`"W`"=dword:00000000"
        $r = "Windows Registry Editor Version 5.00`r`n[-$RK]"
        $kv = Get-SettingKey $RK 'V'; $kw = Get-SettingKey "$RK\Sub" 'W'
        Get-RegResult $a $r @{ $kv = $Gone; $kw = $Gone } | Should Be 'Not applied'
        Get-RegResult $a $r @{ $kv = $Gone; $kw = (New-Reading 0) } | Should Be 'Partly applied'
    }

    It 'does not treat a sibling key with a longer name as deleted' {
        $a = "Windows Registry Editor Version 5.00`r`n[${RK}2]`r`n`"V`"=dword:00000000"
        $r = "Windows Registry Editor Version 5.00`r`n[-$RK]"
        $c = @(Get-CompareSettings $a $r)
        $c.Count | Should Be 1
        $c[0].Revert | Should BeNullOrEmpty
    }

    It 'lets values written after a key deletion recreate the key' {
        $a = "Windows Registry Editor Version 5.00`r`n[$RK]`r`n`"P`"=`"`"`r`n`"N`"=`"`""
        $r = "Windows Registry Editor Version 5.00`r`n[-$RK]`r`n[$RK]`r`n`"P`"=`"`""
        # P is identical in both (ignored); N is gone after Revert
        $keys = @(Get-CompareSettings $a $r | ForEach-Object { $_.Key })
        $keys | Should Be (Get-SettingKey $RK 'N')
        Get-RegResult $a $r @{ (Get-SettingKey $RK 'N') = $Gone } | Should Be 'Not applied'
    }

    It 'lets a key deletion remove values the same text set before it' {
        $r = "Windows Registry Editor Version 5.00`r`n[$RK]`r`n`"V`"=dword:00000001`r`n[-$RK]"
        Get-RegResult (New-RegText '"V"=dword:00000000') $r @{ (Get-SettingKey $RK 'V') = $Gone } | Should Be 'Not applied'
    }
}

Describe '.reg text targets: parsing' {
    It 'mixes with a hand-written target on the other side' {
        $k = Get-SettingKey $RK 'V'
        Get-RegResult (New-RegText '"V"=dword:00000001') @(@{ Path = 'HKCU:\Software\AkariTest'; Name = 'V'; Absent = $true }) @{ $k = $Gone } | Should Be 'Not applied'
    }

    It 'turns ? into $ when asked (the token the catalogue uses for $ inside its here-strings)' {
        $t = "Windows Registry Editor Version 5.00`r`n[$RK\a?b]`r`n`"V`"=`"x?y`""
        $s = @(ConvertFrom-RegText $t -DollarToken)
        $k = Get-SettingKey "$RK\a`$b" 'V'
        Get-RegResult $s @() @{ $k = (New-Reading 'x$y') } | Should Be 'Applied'
    }

    It 'leaves ? alone when not asked' {
        $t = "Windows Registry Editor Version 5.00`r`n[$RK\a?b]`r`n`"V`"=dword:00000001"
        @(Get-CompareSettings (ConvertFrom-RegText $t) @())[0].Key | Should Be (Get-SettingKey "$RK\a?b" 'V')
    }

    It 'fails on a line it does not understand, naming the line' {
        { ConvertFrom-RegText (New-RegText '"V"=qword:1') } | Should Throw 'line 5'
        { ConvertFrom-RegText "Windows Registry Editor Version 5.00`r`n`"V`"=dword:00000001" } | Should Throw 'before any key'
        { ConvertFrom-RegText (New-RegText 'junk') } | Should Throw 'junk'
    }
}

Describe 'every .reg payload in the catalogue' {
    # every here-string in Tweaks\*.ps1 that is a .reg file, as written in the source
    $payloads = foreach ($f in Get-ChildItem "$PSScriptRoot\..\Tweaks" -Filter *.ps1) {
        $ast = [Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
        $ast.FindAll({
                param($n)
                ($n -is [Management.Automation.Language.StringConstantExpressionAst] -or $n -is [Management.Automation.Language.ExpandableStringExpressionAst]) -and
                "$($n.StringConstantType)" -match 'HereString' -and $n.Value.TrimStart() -like 'Windows Registry Editor Version 5.00*'
            }, $true) | ForEach-Object { @{ Where = "$($f.Name):$($_.Extent.StartLineNumber)"; Text = $_.Value } }
    }

    It 'finds the payloads' {
        @($payloads).Count | Should BeGreaterThan 15
    }

    foreach ($p in $payloads) {
        It "parses $($p.Where)" {
            { ConvertFrom-RegText $p.Text -DollarToken } | Should Not Throw
        }
    }
}
