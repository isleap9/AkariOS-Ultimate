. "$PSScriptRoot\TestHelpers.ps1"

# .reg text as a declared target: parsed by the state checker, judged through Get-DetectResult
$RK = 'HKEY_CURRENT_USER\Software\AkariTest'
function New-RegText([string]$Body) { "Windows Registry Editor Version 5.00`r`n`r`n; test`r`n[$RK]`r`n$Body`r`n" }

Describe '.reg text targets: value types' {
    It 'reads dword values' {
        $k = Get-SettingKey $RK 'V'
        $a = New-RegText '"V"=dword:00000002'; $r = New-RegText '"V"=dword:00000000'
        Get-Result $a $r @{ $k = (New-Reading 2) } | Should Be 'Applied'
        Get-Result $a $r @{ $k = (New-Reading 0) } | Should Be 'Not applied'
    }

    It 'reads a high dword as unsigned (the registry hands it back as a negative Int32)' {
        $k = Get-SettingKey $RK 'V'
        Get-Result (New-RegText '"V"=dword:ff191919') (New-RegText '"V"=dword:00000000') @{ $k = (New-Reading ([int]-15132391)) } | Should Be 'Applied'
    }

    It 'reads strings with escaped backslashes and quotes' {
        $k = Get-SettingKey $RK 'S'
        $a = New-RegText '"S"="%SystemRoot%\\System32\\a \"b\".exe"'; $r = New-RegText '"S"=-'
        Get-Result $a $r @{ $k = (New-Reading '%SystemRoot%\System32\a "b".exe') } | Should Be 'Applied'
    }

    It 'reads the default value (@) as the unnamed value' {
        $k = Get-SettingKey $RK ''
        Get-Result (New-RegText '@="URL:x"') (New-RegText '@=-') @{ $k = (New-Reading 'URL:x') } | Should Be 'Applied'
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
        Get-Result $a $r @{ $k = (New-Reading ([byte[]](0x64, 0x64, 0x64, 0, 0x6b, 0x6b, 0))) } | Should Be 'Applied'
        Get-Result $a $r @{ $k = (New-Reading ([byte[]](0x64, 0x64))) } | Should Be 'Partly applied'
    }

    It 'reads qword values' {
        $k = Get-SettingKey $RK 'Q'
        Get-Result (New-RegText '"Q"=hex(b):00,01,00,00,00,00,00,00') (New-RegText '"Q"=-') @{ $k = (New-Reading ([long]256)) } | Should Be 'Applied'
    }

    It 'reads dword values written as hex(4)' {
        $k = Get-SettingKey $RK 'D'
        Get-Result (New-RegText '"D"=hex(4):02,01,00,00') (New-RegText '"D"=-') @{ $k = (New-Reading 258) } | Should Be 'Applied'
    }

    It 'reads expandable strings' {
        $k = Get-SettingKey $RK 'E'
        # "%A%" in UTF-16LE plus the terminating null
        Get-Result (New-RegText '"E"=hex(2):25,00,41,00,25,00,00,00') (New-RegText '"E"=-') @{ $k = (New-Reading '%A%') } | Should Be 'Applied'
    }

    It 'reads multi-string values' {
        $k = Get-SettingKey $RK 'M'
        # "a", "b" in UTF-16LE, each null-terminated, plus the closing null
        $a = New-RegText "`"M`"=hex(7):61,00,00,00,62,00,\`r`n  00,00,00,00"
        Get-Result $a (New-RegText '"M"=-') @{ $k = (New-Reading ([string[]]('a', 'b'))) } | Should Be 'Applied'
    }

    It 'reads an empty multi-string as no strings' {
        $k = Get-SettingKey $RK 'M'
        Get-Result (New-RegText '"M"=hex(7):00,00') (New-RegText '"M"=-') @{ $k = (New-Reading ([string[]]@())) } | Should Be 'Applied'
    }

    It 'unescapes only backslash and quote, as regedit does' {
        $k = Get-SettingKey $RK 'S'
        Get-Result (New-RegText '"S"="a\nb"') (New-RegText '"S"=-') @{ $k = (New-Reading 'a\nb') } | Should Be 'Applied'
    }

    It 'reads empty strings' {
        $k = Get-SettingKey $RK 'URL Protocol'
        Get-Result (New-RegText '"URL Protocol"=""') (New-RegText '"URL Protocol"=-') @{ $k = (New-Reading '') } | Should Be 'Applied'
    }
}

Describe '.reg text targets: deletions' {
    It 'treats a value deletion as absent' {
        $k = Get-SettingKey $RK 'V'
        $a = New-RegText '"V"=dword:00000001'; $r = New-RegText '"V"=-'
        Get-Result $a $r @{ $k = $Gone } | Should Be 'Not applied'
        Get-Result $a $r @{ $k = (New-Reading 1) } | Should Be 'Applied'
    }

    It 'treats a key deletion as absent for every value under that key and its subkeys' {
        $a = "Windows Registry Editor Version 5.00`r`n[$RK]`r`n`"V`"=dword:00000000`r`n[$RK\Sub]`r`n`"W`"=dword:00000000"
        $r = "Windows Registry Editor Version 5.00`r`n[-$RK]"
        $kv = Get-SettingKey $RK 'V'; $kw = Get-SettingKey "$RK\Sub" 'W'
        Get-Result $a $r @{ $kv = $Gone; $kw = $Gone } | Should Be 'Not applied'
        Get-Result $a $r @{ $kv = $Gone; $kw = (New-Reading 0) } | Should Be 'Partly applied'
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
        Get-Result $a $r @{ (Get-SettingKey $RK 'N') = $Gone } | Should Be 'Not applied'
    }

    It 'ignores value lines under a deleted key, as regedit does' {
        $r = "Windows Registry Editor Version 5.00`r`n[-$RK]`r`n`"V`"=dword:00000001"
        Get-Result (New-RegText '"V"=dword:00000000') $r @{ (Get-SettingKey $RK 'V') = $Gone } | Should Be 'Not applied'
    }

    It 'lets a key deletion remove values the same text set before it' {
        $r = "Windows Registry Editor Version 5.00`r`n[$RK]`r`n`"V`"=dword:00000001`r`n[-$RK]"
        Get-Result (New-RegText '"V"=dword:00000000') $r @{ (Get-SettingKey $RK 'V') = $Gone } | Should Be 'Not applied'
    }
}

Describe '.reg text targets: parsing' {
    It 'mixes with a hand-written target on the other side' {
        $k = Get-SettingKey $RK 'V'
        Get-Result (New-RegText '"V"=dword:00000001') @(@{ Path = 'HKCU:\Software\AkariTest'; Name = 'V'; Absent = $true }) @{ $k = $Gone } | Should Be 'Not applied'
    }

    It 'turns ? into $ when asked (the token the catalogue uses for $ inside its here-strings)' {
        $t = "Windows Registry Editor Version 5.00`r`n[$RK\a?b]`r`n`"V`"=`"x?y`""
        $s = @(ConvertFrom-RegText $t -DollarToken)
        $k = Get-SettingKey "$RK\a`$b" 'V'
        Get-Result $s @() @{ $k = (New-Reading 'x$y') } | Should Be 'Applied'
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
    # every .reg file written out by a here-string in Tweaks\*.ps1, as written in the source. Some sit inside an outer
    # here-string (a script written to disk for safe boot), so each payload runs from its header to the first here-string end.
    # loudness-eq builds its .reg text in a loop at run time and has no payload in the source.
    $payloads = @()
    $headers = 0
    foreach ($f in Get-ChildItem "$PSScriptRoot\..\Tweaks" -Filter *.ps1) {
        $headers += @(Get-Content $f.FullName | Where-Object { $_ -ceq 'Windows Registry Editor Version 5.00' }).Count
        $ast = [Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
        $strings = $ast.FindAll({
                param($n)
                ($n -is [Management.Automation.Language.StringConstantExpressionAst] -or $n -is [Management.Automation.Language.ExpandableStringExpressionAst]) -and
                "$($n.StringConstantType)" -match 'HereString'
            }, $true)
        foreach ($s in $strings) {
            foreach ($m in [regex]::Matches($s.Value, '(?ms)^Windows Registry Editor Version 5\.00\r?$.*?(?=^`?[''"]@|\z)')) {
                $line = $s.Extent.StartLineNumber + 1 + ($s.Value.Substring(0, $m.Index) -split "`n").Count - 1
                $payloads += @{ Where = "$($f.Name):$line"; Text = $m.Value }
            }
        }
    }

    It 'finds every payload in the source' {
        $headers | Should BeGreaterThan 15
        @($payloads).Count | Should Be $headers
    }

    foreach ($p in $payloads) {
        It "parses $($p.Where)" {
            { ConvertFrom-RegText $p.Text -DollarToken } | Should Not Throw
        }
    }
}
