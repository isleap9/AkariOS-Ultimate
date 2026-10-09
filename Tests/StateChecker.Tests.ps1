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
