#requires -Version 5.1
# Run every test.  powershell -NoProfile -ExecutionPolicy Bypass -File Tests\Run.ps1
# Uses the Pester 3.4 that ships with Windows (Pester 4 also works); Pester 5 is not supported because its syntax differs.
Import-Module Pester -MaximumVersion 4.99 -ErrorAction Stop
$r = Invoke-Pester -Path $PSScriptRoot -PassThru
exit $r.FailedCount
