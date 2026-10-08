# Testing Patterns

**Analysis Date:** 2026-10-08

> There is no test infrastructure in this repo. 114 `.ps1` files, 0 test files, no Pester, no PSScriptAnalyzer config, no CI workflows (no `.github/` directory). Verification is manual on a real Windows machine/VM. This document records that current state precisely and prescribes the manual procedure plus the exact pattern to follow if automated tests are ever added.

## Test Framework

**Runner:**
- None. Not detected — no `*.Tests.ps1`, no `*.Pester.ps1`, no Pester `Describe/Context/It` strings anywhere under the repo root (verified by content search).
- Config: no test config file of any kind (`jest.config.*`, `vitest.config.*`, `pytest.ini`, `PesterConfiguration`, `PSScriptAnalyzerSettings.psd1` — all absent).

**Assertion Library:**
- None. `should`-style assertions do not exist in the codebase.

**Run Commands:**
```powershell
# No automated suite exists, so there is nothing to run.
# Closest equivalents available today:
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\Akari.ps1   # launch the UI (needs Windows + admin)
Invoke-ScriptAnalyzer -Path .\Akari.ps1, .\Tweaks, .\IWR.ps1           # static lint only, requires PSScriptAnalyzer module (not pinned)
```

## Test File Organization

**Location:**
- Not applicable — no tests. Do NOT co-locate speculative test files next to tweaks today.
- If tests are introduced, place them in a new top-level `tests/` directory (it does not exist yet) so production `Tweaks/` dot-sourcing (`Akari.ps1` line 56: `Get-ChildItem "$Root\Tweaks" -Filter *.ps1`) and the `Unblock-File` sweep never pick them up.

**Naming:**
- Prescribed (not yet observed): `<Subject>.Tests.ps1` — e.g. `tests/AddTweak.Registration.Tests.ps1`, `tests/Detect.Idempotency.Tests.ps1`. This matches the Pester v5 discovery convention and keeps them out of the `Tweaks/*.ps1` glob.

**Structure:**
```
# Proposed only — none of this exists yet:
tests/
├── AddTweak.Registration.Tests.ps1  # every Tweaks/*.ps1 dot-sources and registers unique Ids
├── Detect.Idempotency.Tests.ps1     # Detect blocks return [bool] or $null, never throw
└── fixtures/
    └── FakeTweaks.ps1               # minimal Add-Tweak calls exercising each -Kind
```

## Test Structure

**Suite Organization:**
- No suites exist. The prescribed pattern for the first suite (registration smoke test — catches duplicate `-Id`, bad `-Category`, missing `-Apply`) is:
```powershell
# tests/AddTweak.Registration.Tests.ps1 (PROPOSED — does not run today)
BeforeAll {
    $registered = [System.Collections.Generic.List[object]]::new()
    function Add-Tweak { param($Id, $Category, $Name, $Description, $Risk = 'Safe', $Kind = 'Toggle', $Button = 'Run', $Actions, $Confirm, $Script, $Apply, $Revert, $Detect, $Check)
        $registered.Add([pscustomobject]@{ Id = $Id; Category = $Category; Kind = $Kind; Apply = $Apply; Revert = $Revert; Detect = $Detect })
    }
    foreach ($f in Get-ChildItem "$PSScriptRoot\..\Tweaks" -Filter *.ps1 | Sort-Object Name) { . $f.FullName }
}
Describe 'Tweak registration' {
    It 'registers at least one tweak' { $registered.Count | Should -BeGreaterThan 0 }
    It 'has unique Ids' {
        $ids = $registered.Id
        $ids.Count | Should -Be ($ids | Select-Object -Unique).Count
    }
    It 'uses only known categories' {
        $known = 'Check','Refresh','Setup','Installers','Graphics','Windows','Hardware','Advanced'
        foreach ($t in $registered) { $t.Category | Should -BeIn $known }
    }
    It 'every entry has an Apply block' {
        foreach ($t in $registered) { $t.Apply | Should -Not -BeNullOrEmpty }
    }
}
```

**Patterns:**
- Setup pattern: stub `Add-Tweak` (and `Write-Log`/`Write-Host` shims) in `BeforeAll`, then dot-source the real `Tweaks/*.ps1` — never execute `Apply`/`Revert` bodies in tests (they mutate HKLM/services/packages).
- Teardown pattern: none needed if bodies are never invoked; if a test must invoke a `Detect` block, run it with `-ErrorAction Stop` wrapped in `try/catch` and assert it returns `[bool]` or `$null`.
- Assertion pattern: Pester `Should -Be / -BeIn / -Not -BeNullOrEmpty` (proposed; no in-repo example to copy).

## Mocking

**Framework:** None in use. Pester `Mock` would be the fit if adopted.

**Patterns:**
- Nothing to copy — no mocks exist. The seam points designed for future mocking are:
```powershell
# Seam 1: registry reads inside -Detect blocks (Tweaks/Windows.ps1 'widgets' example)
-Detect {
    (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -ErrorAction SilentlyContinue).AllowNewsAndInterests -eq 0
}
# Test by Mocking Get-ItemProperty to return controlled objects.

# Seam 2: connectivity guard at the top of network-dependent blocks (Tweaks/Check.ps1 pattern)
if (-not (Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet -ErrorAction SilentlyContinue)) { Write-Log 'Internet connection required'; return }
# Test by Mocking Test-Connection to $true/$false and asserting early return vs. download attempt.

# Seam 3: destructive cmdlets — Mock Stop-Process, Remove-AppxPackage, Start-Process to assert call shape without side effects.
```

**What to Mock:**
- `Get-ItemProperty` / `Test-Path` (registry/file state reads in `Detect`/`Check`).
- `Test-Connection` (internet gate — never hit the network in tests).
- `Stop-Process`, `Start-Process`, `Remove-AppxPackage`, `Disable-WindowsOptionalFeature`, `cmd`, `regedit.exe` invocations (any mutating or process-spawning call).
- `Get-CimInstance Win32_ComputerSystem` (used by `Get-RamKB` in `Akari.ps1`).

**What NOT to Mock:**
- `Add-Tweak` itself beyond the registration stub — the DSL shape is the contract under test.
- XAML parsing (`[Windows.Markup.XamlReader]::Parse`) or the WPF dispatcher — UI behavior is verified manually (see Test Types).
- Actual registry writes, service changes, AppX removal, `bcdedit`, `shutdown -r` — these are never executed by tests, only by manual VM runs.

## Fixtures and Factories

**Test Data:**
- None exist. Proposed minimal fixture exercising every `-Kind` the host renders (`Akari.ps1` `New-Row` branches on `Toggle`/`Action`/`Group`/`Console`):
```powershell
# tests/fixtures/FakeTweaks.ps1 (PROPOSED)
Add-Tweak -Id 'fixture-toggle' -Category 'Check' -Name 'Fixture toggle' -Risk Safe `
    -Description 'Toggle fixture' -Apply { Write-Host 'on' } -Revert { Write-Host 'off' } `
    -Detect { $true }
Add-Tweak -Id 'fixture-action' -Category 'Check' -Kind Action -Button 'Open' -Name 'Fixture action' -Risk Safe `
    -Description 'Action fixture' -Apply { Write-Host 'ran' }
Add-Tweak -Id 'fixture-group' -Category 'Check' -Kind Group -Button 'Run all' -Name 'Fixture group' -Risk Caution `
    -Description 'Group fixture' -Apply { Write-Host 'all' } `
    -Actions @( @{ Name = 'Piece'; Description = 'One piece'; Button = 'Run'; Block = { Write-Host 'piece' } } )
```

**Location:**
- Proposed: `tests/fixtures/` (does not exist yet). Keep fixtures out of `Tweaks/` and the numbered folders so the UI never lists them.

## Coverage

**Requirements:** None enforced. Effective automated coverage is 0% (no suite, no gate, no badge).

**View Coverage:**
```powershell
# No coverage tooling configured. If Pester tests are added, the prescribed command is:
Invoke-Pester -Path .\tests -Output Detailed -CodeCoverage .\Tweaks\*.ps1, .\Akari.ps1
```

## Test Types

**Unit Tests:**
- Not used. Candidate first units (all currently unverified): `Get-State`/`Update-Row` null-vs-bool handling (`Akari.ps1` lines 175–192), `Update-Tuner`/`Set-Chips` bit math for `Win32PrioritySeparation` (lines 308–324), `Get-SvcTarget` threshold mapping (lines 349–352), `Confirm-Run` null-text passthrough (lines 258–261).

**Integration Tests:**
- Not used (automated). The de-facto integration test is launching `Akari.ps1` elevated on a disposable Windows 10/11 VM and exercising the UI: sidebar categories render, search filters (`Show-Page` in `Akari.ps1`), Optimize/Default/Check buttons enqueue `Invoke-Code` runspace jobs, log drawer streams output, `state.json` round-trips Toggle dots.

**E2E Tests:**
- Not used; no framework (no Playwright/Selenium/Appium). Manual E2E is the only gate before sharing a build: snapshot VM → run `IWR.ps1` one-liner path → apply one tweak per risk tier (Safe, Caution, Advanced) → reboot → verify effect + `Detect` dot state → run Default/Revert → reboot → verify restoration.

## Common Patterns

**Async Testing:**
```powershell
# No async tests exist. The only async machinery is the runspace + DispatcherTimer
# poll loop in Akari.ps1 (Invoke-Code lines 223-235, timer lines 237-256).
# If ever tested: BeginInvoke → poll $script:Job.Handle.IsCompleted with a bounded
# timeout → EndInvoke → assert LogQueue drained and Set-Busy $false.
# Never add real sleeps longer than the existing 150ms tick granularity.
```

**Error Testing:**
- Current codebase convention (manual): trigger the internet gate by disconnecting the VM network and confirm the tweak logs `'Internet connection required'` and returns without changes (pattern in `Tweaks/Check.ps1`, `Tweaks/Windows.ps1` bloatware block, `Tweaks/Advanced.ps1` ReBar blocks).
- Host error paths verified by inspection, not tests: `trap` → message box + `akari.log` (`Akari.ps1` line 28), `Dispatcher.UnhandledException` → log drawer (`Akari.ps1` lines 382–388), `EndInvoke` catch → `"Error: …"` log line (line 244). Any new error path must at minimum be exercised once manually and leave a timestamped line in the log drawer.

## Manual Verification Checklist (the actual QA process)

Because there is no automation, follow this exact sequence when changing tweak code — it is the substitute for a test suite:
1. Snapshot a disposable Windows 10/11 VM (Home + Pro images if the tweak touches edition-gated keys).
2. Copy the repo (or run the `IWR.ps1` download path) and launch `powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\Akari.ps1` elevated.
3. Exercise the changed entry: Optimize/Apply → watch the log drawer for the expected `Write-Host` narrative and `Done:` line → reboot → confirm the effect and (for Toggles) the state dot.
4. Exercise Default/Revert → reboot → confirm restoration; entries with no safe revert must omit `-Revert` so the UI disables the Default button (see `New-Row` `$defOff` logic, `Akari.ps1` line 136).
5. For `-Confirm` tweaks (e.g. `bloatware` in `Tweaks/Windows.ps1`, Defender flows in `Tweaks/Advanced.ps1`), verify both Yes and No paths.
6. For `-Detect` tweaks, verify all three render states: on (filled dot), off (hollow), unknown/error (dimmed) — see `Update-Row` (`Akari.ps1` lines 183–192).
7. Cross-check the numbered-folder original and its `Tweaks/*.ps1` mirror stay in sync (GENERATED headers); test the standalone `.ps1` by double-click after `AllowScripts.cmd` option 1 as well as from the UI.

---

*Testing analysis: 2026-10-08*
