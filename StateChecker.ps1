# State checker: turns a Tweak's declared targets plus machine readings into a Detect result.
# Pure logic only: no UI, no registry/service reads, no side effects. Dot-sourced by Akari.ps1 and by Tests\*.Tests.ps1.

# the closed set of Detect results (CONTEXT.md); 'Checking' is a display state, not a result
function Get-DetectResults {
    'Applied', 'Not applied', 'Partly applied', 'Unknown'
}
