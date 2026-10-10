# shared by Tests\*.Tests.ps1: the state checker plus fake machine readings
. "$PSScriptRoot\..\StateChecker.ps1"

$Gone = @{ Present = $false }
function New-Reading($v) { @{ Present = $true; Value = $v } }
function Get-Result($ApplyTarget, $RevertTarget, [hashtable]$Readings) {
    (Get-DetectResult $ApplyTarget $RevertTarget $Readings).Result
}
