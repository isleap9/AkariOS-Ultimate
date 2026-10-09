---
phase: 04-home-polish-documentation
verified: 2026-10-09T09:56:41Z
status: human_needed
score: 41/44 must-haves verified
covered_files:
  - .planning/phases/04-home-polish-documentation/04-01-PLAN.md
  - .planning/phases/04-home-polish-documentation/04-01-SUMMARY.md
  - .planning/phases/04-home-polish-documentation/04-02-PLAN.md
  - .planning/phases/04-home-polish-documentation/04-02-SUMMARY.md
  - .planning/phases/04-home-polish-documentation/04-03-PLAN.md
  - .planning/phases/04-home-polish-documentation/04-03-SUMMARY.md
  - Akari.ps1
  - README.md
  - UI/MainWindow.xaml
covered_digest: "v3:sha256:0e4726df2d21ba3291a73d1361a84328c6c93815fc0bca7be3bcdb1b04376f82"
behavior_unverified: 3
overrides_applied: 0
behavior_unverified_items:
  - truth: "FLAGGED ASSUMPTION (clipboard contention): when another program holds the clipboard, the button reads Copy failed for about 2 seconds instead of Copied, nothing is logged, and the app keeps working"
    test: "Hold the clipboard open from another program (or a clipboard manager that locks it) and click Copy specs"
    expected: "The button reads 'Copy failed' for about 2 seconds, then 'Copy specs' again; nothing appears in the log; the app keeps working"
    why_human: "The catch branch in Copy-Specs (Akari.ps1:828-831) is present, but no harness forces Clipboard.SetText to throw"
  - truth: "Every CIM call in the spec read carries -OperationTimeoutSec 10, so one hung WMI class fails only its own group while the rest of the read completes"
    test: "Needs a WMI class that hangs (not reproducible on demand)"
    expected: "Only the card for the hung class shows Not available after about 10 s; the other cards fill in and the read finishes before the 20 s deadline"
    why_human: "The 04-03 harness proves all 8 calls carry the timeout (presence). The reviewer saw a slow CIM query throw a catchable timeout in about 3 s, and each group's try/catch is in place. No test runs a real hung class through Get-Specs."
  - truth: "FLAGGED ASSUMPTION: tweak runs behave exactly as before (same Done line, error lines, saved toggle state, busy guard release and deferred Home read)"
    test: "Run a couple of tweaks from other pages"
    expected: "Each shows its messages and a 'Done' line; toggle dots and buttons behave as before; coming back to Home refreshes the cards"
    why_human: "The tweak-completion block (Akari.ps1:911-924) only lost the ResultVar harvest, and the 04-03 AST check confirms that. No harness runs a real tweak through the tick."
human_verification:
  - test: "Open the app. On Home, find the 'Copy specs' button on the right, level with your computer's name. Click it, then paste into Notepad."
    expected: "The button says 'Copied' for about 2 seconds, then 'Copy specs' again. The pasted text shows your computer name, your PC maker and model, an empty line, then lines starting with CPU, GPU, RAM, Disk, Board and Windows that match the cards. Nothing new appears in the messages at the bottom. Go to another page and back, and click Copy specs while the cards are still faded: it still copies."
    why_human: "Real button click and real paste in the running app (harvested from 04-01 Task 1)"
  - test: "Look at the RAM and Disk cards. Then open many apps or browser tabs until memory use is above 80%, go to another page and come back to Home."
    expected: "With plenty of free memory and disk space every value is white and nothing is green. Above 80% memory use the RAM 'Used' number turns amber, and above 90% it turns red. No other number, title or card border changes colour."
    why_human: "Real colour under real memory pressure (harvested from 04-01 Task 2)"
  - test: "Open README.md on GitHub or in a Markdown preview."
    expected: "It fits on about one screen with no pictures, explains Akari and the Home page (Copy specs, amber/red colours), lists the 8 categories one line each, explains Optimize/Default and the risk labels, shows the same install line as before, explains running from a zip, and ends with the same Credits line."
    why_human: "Readability and on-screen fit (harvested from 04-02 Task 1)"
  - test: "Click between Home and other pages a few times."
    expected: "Each time you come back to Home the cards fade briefly, then show fresh values within a couple of seconds. They never stay faded, and no new message appears at the bottom."
    why_human: "Live refresh feel in the running app (harvested from 04-03 Task 1)"
  - test: "Look at the CPU card, then run a couple of tweaks from other pages."
    expected: "The CPU card shows the same model, cores, threads and speed as before, with no 'Sockets' line on this single-processor PC. Each tweak still shows its messages and a 'Done' line, and the buttons work as before."
    why_human: "Tweak-run behaviour and the single-socket CPU card in the real app (harvested from 04-03 Task 2; also covers behavior-unverified truth 44)"
  - test: "(Optional) With another program holding the clipboard, click Copy specs."
    expected: "The button reads 'Copy failed' for about 2 seconds and the app keeps working."
    why_human: "Error path not exercised by any harness (behavior-unverified truth 18). Hard to set up; accepting it with an override is reasonable."
  - test: "Confirm the judgment-tier prohibitions listed in the report (no network/file output from Copy specs, no hidden identifiers in the copied text, README unchanged install source and no invented features)."
    expected: "You agree with the verifier's non-authoritative verdicts in the Prohibitions table"
    why_human: "Prohibitions with no enforcing test are flagged for human review, never passed silently"
---

# Phase 4: Home Polish & Documentation Verification Report

**Phase Goal:** Copy-to-clipboard, health indicators, and project documentation
**Verified:** 2026-10-09T09:56:41Z
**Status:** human_needed
**Re-verification:** No (initial verification)

> **MVP-mode note:** ROADMAP marks Phase 4 `Mode: mvp`, but its goal line is not a user story: `user-story.validate` returns `valid: false`. The three PLANs each state a user story for their slice. Combined, they validate (`valid: true`): «As a user, I want to copy my full spec sheet from Home, see when my disk or memory is running low, and read a README that explains the project, so that I can share accurate specs, spot trouble at a glance and get started without guessing.» The User Flow Coverage table below uses that wording. This matches how Phase 3 handled it. Run `/gsd-mvp-phase 4` to make ROADMAP.md consistent. The verdict does not change.

## User Flow Coverage

| Step | Expected | Evidence in codebase | Status |
| ---- | -------- | -------------------- | ------ |
| User opens Home and sees a Copy specs button | Button on the right of the header, Btn style, disabled until the first read | `UI/MainWindow.xaml:212-213`; enabled from `Update-Home` (`Akari.ps1:759`); harness 04-01 v1 checks parent, dock, style, label and the enable/disable states | VERIFIED |
| User clicks Copy specs | Full plain spec sheet on the clipboard, "Copied" for about 2 s | `$CopySpecs.Add_Click({ Copy-Specs })` (`Akari.ps1:988`), `Copy-Specs` and `Get-SpecText` (`Akari.ps1:799-833`), tick revert (`Akari.ps1:867`). Harness 04-01 v1 compares the clipboard to a 24-line expected sheet (CRLF) in a real STA clipboard | VERIFIED |
| User reads RAM/Disk at a glance | Disk Free amber <15% / red <10%; RAM Used amber >80% / red >90% | `Get-DiskHealth`/`Get-RamHealth` (`Akari.ps1:629-646`), keys on the two model rows (`:688-689`, `:703-704`), applied in `Add-Row` (`:601`). Harness 04-01 v5 runs 24 boundary cases plus the rendered brushes | VERIFIED |
| User reads README to get started | Project, Home page, categories, apply/revert, install, safety, Credits | `README.md` is 50 lines. Harness 04-02 v1 passes. Diffed against b4abbad: the IWR line and Credits are byte-identical | VERIFIED |
| Outcome: user shares accurate specs and spots trouble | Copied values equal card values; colours follow live values | The cards and the copy text both come from `Get-HomeModel` (`Akari.ps1:773`, `:806`), so they cannot disagree | VERIFIED (real-app feel: human) |

## Goal Achievement

### Observable Truths

Roadmap success criteria (contract):

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 1 | SC1: User can copy the full spec text to the clipboard from Home | ✓ VERIFIED | Click wired at `Akari.ps1:988` to `Copy-Specs`, which calls `[Windows.Clipboard]::SetText((Get-SpecText))`. I re-ran 04-01 v1 (STA, real clipboard, real functions extracted from Akari.ps1 through the AST): PASS |
| 2 | SC2: User sees health indicators (disk-free % / RAM pressure threshold colouring) | ✓ VERIFIED | `Get-DiskHealth`/`Get-RamHealth` use strict thresholds and only colour two model rows. I re-ran 04-01 v5 (24 threshold cases plus rendered Foreground brushes): PASS |
| 3 | SC3: README documents AkariOS-Ultimate including the Home page | ✓ VERIFIED | `README.md` has a `# Home page` section covering live specs, Copy specs and health colours, plus 8 categories, apply/revert, requirements, IWR, zip route, safety and Credits. I re-ran 04-02 v1: PASS |

Plan 04-01 (SPEC-07, SPEC-08):

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 4 | Copy specs button on the right of the header, Btn style (D-01) | ✓ VERIFIED | XAML lines 212-213. 04-01 v1 asserts parent HomeHeader, Dock=Right, Style=Btn, and that the fill child is still last |
| 5 | Copied sheet format: name, maker line, blank, Group/indented rows, RAM inline (D-02) | ✓ VERIFIED | `Get-SpecText` at `:799-820`. 04-01 v1 checks for an exact match (`-cne`) against the approved sheet |
| 6 | Copied values are the same text as the cards (one model) (D-02, D-07) | ✓ VERIFIED | `Update-Home` (`:773`) and `Get-SpecText` (`:806`) both iterate `Get-HomeModel`. Values are cast to `[string]` once |
| 7 | Copied Disk section lists only the system drive (D-03) | ✓ VERIFIED | `:695` filters on `$env:SystemDrive`. 04-01 v2 asserts that a non-system volume is not shown |
| 8 | "Copied" for about 2 s, then "Copy specs"; no log line (D-04) | ✓ VERIFIED | `:827`, `:832`, tick `:867`. 04-01 v1 runs the real tick before and after the deadline and asserts the log text is unchanged |
| 9 | Enabled during an in-flight refresh; disabled only until the first read (D-05) | ✓ VERIFIED | `:759`. 04-01 v1 asserts disabled with no data, enabled after data, and a copy during an in-flight SpecJob |
| 10 | First line is the computer name (D-06) | ✓ VERIFIED | `:801`. Covered by the exact-match fixture |
| 11 | Built on the UI thread from data in hand; no query, job or tweak runner (D-07) | ✓ VERIFIED | 04-01 v1 AST check: Copy-Specs, Get-SpecText, Get-HomeModel and Get-HostLine contain no Invoke-Code, Get-CimInstance, Start-SpecRead or Add-Log |
| 12 | Disk Free amber <15%, red <10% (D-08) | ✓ VERIFIED | `:629-636`. 04-01 v5 |
| 13 | RAM Used amber >80%, red >90% (D-09) | ✓ VERIFIED | `:639-646`. 04-01 v5 |
| 14 | Only those two value texts change colour; no percentage text, headline or border changes (D-10) | ✓ VERIFIED | Only the `Used` row (`:689`) and the `Free` row (`:704`) carry `Key`. `Add-Headline` and `New-Card` are untouched |
| 15 | Healthy stays Tx; no green; no new brush or style (D-11) | ✓ VERIFIED | The functions return only Tx, Warn or Bad. The XAML still has 15 `x:Key` entries (asserted by 04-01 v5) |
| 16 | Not available or a failed read is never coloured (D-12) | ✓ VERIFIED | String, null and zero-total guards, plus the failed-group guard (`:688`, `:703`). `Add-Row` forces Mu for the sentinel (`:601`) |
| 17 | FLAGGED: strict boundaries (15% and 80% neutral, 10% and 90% amber) | ✓ VERIFIED | Exact boundary cases in 04-01 v5 |
| 18 | FLAGGED: clipboard contention shows "Copy failed", nothing logged | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | The catch branch at `:828-831` is present and wired. No harness makes SetText throw. See Human Verification |
| 19 | FLAGGED: multi-GPU copies one block per adapter; empty GPU/Disk copies the headline only | ✓ VERIFIED | The 04-01 v1 fixture has 2 adapters (one with a Status row) and asserts the zero-adapter case |
| 20 | FLAGGED: a failed first read copies name, blank line, Not available values, no maker line | ✓ VERIFIED | 04-01 v1 failed-read assertion |
| 21 | FLAGGED: CRLF line breaks, no trailing break | ✓ VERIFIED | `:819` joins with `` `r`n ``. The exact-match fixture is joined the same way |
| 22 | The Home grid renders exactly as Phase 3 left it | ✓ VERIFIED | Phase 3 regression harnesses 04-01 v2, v3, v4, v6 and v7 all PASS on the merged tree |

Plan 04-02 (DOC-01):

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 23 | Concise rewrite (80 lines or fewer) in the D-13 section order | ✓ VERIFIED | 50 lines. Sections run AkariOS Ultimate, Home page, Categories, Apply and revert, Requirements, Install (IWR), Run from a downloaded zip, Safety, Credits |
| 24 | Home section: live refresh, Copy specs, thresholds | ✓ VERIFIED | README lines 5-7 |
| 25 | 8 categories, one line each, drawn from real tweak names | ✓ VERIFIED | README lines 10-17. Spot-checked against the tuners in `Akari.ps1` |
| 26 | Apply/revert: risk labels, Optimize/Default, state dot, one-shot/Options, one at a time with the log | ✓ VERIFIED | README lines 20-23 |
| 27 | Run-from-zip names AllowScripts.cmd option 1, then Akari.ps1 (admin) | ✓ VERIFIED | README lines 39-41 |
| 28 | Safety note: admin, reboot, read the risk label | ✓ VERIFIED | README lines 44-47 |
| 29 | No images | ✓ VERIFIED | No `![` or `<img`. 04-02 v1 |
| 30 | Credits verbatim as the last section | ✓ VERIFIED | Identical to `git show b4abbad:README.md` lines 16-17 |
| 31 | IWR line byte-identical | ✓ VERIFIED | Identical to b4abbad line 13 |
| 32 | FLAGGED: level-1 `#` headings | ✓ VERIFIED | Every heading is `# ` |
| 33 | FLAGGED: README label and thresholds match 04-01 | ✓ VERIFIED | "Copy specs" matches XAML `Content`. 15/10 and 80/90 match `Get-DiskHealth` and `Get-RamHealth` |

Plan 04-03 (Phase 3 review fixes, SPEC-07/SPEC-08 robustness):

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 34 | A read still running at 20 s is abandoned: slot freed, BeginStop only, Home undimmed, one log line (D-16) | ✓ VERIFIED | Tick `:871-901`. I re-ran 04-03 v1 (an uninterruptible 6 s sleep through the real tick, which also asserts the UI-thread block time): PASS |
| 35 | All 8 CIM calls carry `-OperationTimeoutSec 10`, so one hung class fails only its own group | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Presence is proven: 8/8 calls, asserted by 04-03 v1. Every call sits inside its group's try/catch (for example `:157-170`). No test runs a real hung class. See also review WR-01 (the budget only fits one slow class) |
| 36 | Abandoned reads are disposed on a later tick; the UI never waits (D-16) | ✓ VERIFIED | `:904-910`. 04-03 v1 asserts SpecStale goes 1 then 0 and the runspace ends Closed, for both the first and second abandoned reads |
| 37 | After a timeout the next Home starts a fresh read; a normal read finishes inside the deadline | ✓ VERIFIED | 04-03 v1 checks the fresh read has a deadline about 20 s away and that a live read completes |
| 38 | Invoke-Code takes only code, label and meta; SpecData has a single writer (D-17) | ✓ VERIFIED | `:520`. Tweak completion is at `:913`. 04-03 v5 AST check: PASS. SpecData is assigned only at `:38`, `:887` and `:897` |
| 39 | Cores and threads summed across sockets; Sockets row only when >1 (D-18) | ✓ VERIFIED | `:159-164` and `:664`. 04-03 v5 runs a mocked two-socket Xeon through the real Get-Specs, Update-Home and Get-SpecText: PASS |
| 40 | Six groups unchanged; Sockets is descriptive and Not available on failure (D-18) | ✓ VERIFIED | `$cpuFields = 4` excludes Sockets. `New-FailedSpecs` sets `Sockets = $na` (`:619`). 04-03 v5 and v8 check six groups live |
| 41 | FLAGGED: 20 s is about 10x a normal read | ✓ VERIFIED | `$script:SpecTimeoutSec = 20` (`:43`). A live read completes inside it (04-03 v1). Advisory WR-01 still applies to multi-class stalls |
| 42 | FLAGGED: an uninterruptible pipeline stays in SpecStale rather than blocking the UI | ✓ VERIFIED | The tick only polls `IsCompleted` and never calls blocking Stop, EndInvoke or Dispose on a running job. 04-03 v1 uses an uninterruptible sleep |
| 43 | FLAGGED: late output from an abandoned read never replaces SpecData | ✓ VERIFIED | The late branch never reads ResultCollection, and the stale-disposal loop has no SpecData write. The AST single-writer check is in 04-03 v5 |
| 44 | FLAGGED: tweak runs behave exactly as before | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | The completion block is unchanged apart from the EndInvoke harvest removal (`:911-924`). No harness drives a real tweak through the tick. See Human Verification |

Rows 1-3 are the roadmap contract. Plan truths that add detail beyond an SC are listed as their own rows. Score: **41/44 verified (3 present, behavior-unverified: rows 18, 35, 44).**

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `Akari.ps1` | Get-HomeModel, Get-HostLine, Get-SpecText, Copy-Specs, Get-DiskHealth, Get-RamHealth, CopiedUntil, CopySpecs | ✓ VERIFIED | All present and substantive (`:41`, `:396`, `:629-833`). Wired: the click at `:988`, the renderer at `:773`, the tick at `:867` |
| `Akari.ps1` | SpecTimeoutSec, SpecStale, Deadline, BeginStop, OperationTimeoutSec, Sockets, Measure-Object | ✓ VERIFIED | `:43-44`, `:849`, `:871-910`, 8 CIM calls, `:159-176`, `:664` |
| `UI/MainWindow.xaml` | `x:Name="CopySpecs"`, `DockPanel.Dock="Right"`, `Content="Copy specs"` | ✓ VERIFIED | Lines 212-213, inside `HomeHeader`. Bound through the Set-Variable list (`Akari.ps1:396`) |
| `README.md` | `# Home page`, `Copy specs`, `AllowScripts.cmd`, `# Credits`, `-useb \| iex` | ✓ VERIFIED | All present. 50 lines |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| MainWindow.xaml CopySpecs | Akari.ps1 Copy-Specs | Set-Variable shortcut and Add_Click | WIRED | `:396` binds it, `:988` handles the click (AST-asserted by 04-01 v1) |
| Update-Home / Get-SpecText | Get-HomeModel | shared model | WIRED | `:773`, `:806` |
| Get-DiskHealth / Get-RamHealth | Add-Row brush | model `Key` passed to `Add-Row` | WIRED | `:688-689`, `:703-704` lead to `:780` and then `:601` |
| Tick | CopiedUntil | label revert | WIRED | `:867` |
| Start-SpecRead Deadline | Tick watchdog | `$late` reuses the failure branch | WIRED | `:849`, then `:871-899` |
| SpecStale | Tick disposal | Handle.IsCompleted | WIRED | `:880`, then `:904-910` |
| Get-Specs CPU.Sockets | Get-HomeModel Sockets row, then card and copy text | model | WIRED | `:176`, `:664` |
| README IWR line | IWR.ps1 | `raw/refs/heads/main/IWR.ps1` | WIRED | README line 34 |
| README zip route | AllowScripts.cmd | option 1 | WIRED | README line 40 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| Copy specs text | `Get-SpecText` output | `$script:SpecData`, filled by the background `Get-Specs` CIM read (`:887`) | Yes. 04-01 v4 and v8 run a live read, which returns six groups | ✓ FLOWING |
| Disk Free / RAM Used brush | model `Key` | `Get-DiskHealth`/`Get-RamHealth` on live `FreeGB/TotalGB`, `UsedGB/TotalGB` | Yes | ✓ FLOWING |
| CPU Sockets row | `CPU.Sockets` | `@(Win32_Processor).Count` | Yes (on this host it is 1, so the row is hidden by design) | ✓ FLOWING |

### Behavioral Spot-Checks

I re-ran all 17 `<automated>` commands from the three PLANs from the repo root with real `powershell.exe`:

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Copy specs end to end (STA clipboard, label flash, no log) | 04-01 v1 / 04-03 v6 | PASS | ✓ PASS |
| Six-card content map | 04-01 v2 / 04-03 v7 | PASS | ✓ PASS |
| Header identity fallback | 04-01 v3 | PASS | ✓ PASS |
| Live default landing plus tick-driven read | 04-01 v4 / 04-03 v3 | PASS | ✓ PASS |
| Health thresholds plus rendered brushes | 04-01 v5 | PASS | ✓ PASS |
| Loading, dimmed, partial and failed states | 04-01 v6 | PASS | ✓ PASS |
| Failure path, one log line | 04-01 v7 / 04-03 v2 | PASS | ✓ PASS |
| Live six-group read | 04-01 v8 / 04-03 v8 | PASS | ✓ PASS |
| README content contract | 04-02 v1 | PASS | ✓ PASS |
| Hung-read watchdog plus deferred disposal | 04-03 v1 | PASS | ✓ PASS |
| Static guards (busy guard, no Show-Page, composite, HOME) | 04-03 v4 | PASS | ✓ PASS |
| Single SpecData writer plus multi-socket sums | 04-03 v5 | PASS | ✓ PASS |

### Probe Execution

Step 7c: not applicable. The phase declares no `scripts/*/tests/probe-*.sh` probes. The plans' embedded `<automated>` harnesses were run above instead.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| SPEC-07 | 04-01, 04-03 | User can copy the full spec text to the clipboard from Home | ✓ SATISFIED | Truths 1, 4-11 and 19-21. 04-03 makes the copied CPU line correct on multi-socket machines |
| SPEC-08 | 04-01, 04-03 | Disk-free % / RAM pressure threshold colouring | ✓ SATISFIED | Truths 2 and 12-17 |
| DOC-01 | 04-02 | README revamped to document the project including the Home page | ✓ SATISFIED | Truths 3 and 23-33. **Bookkeeping:** `.planning/REQUIREMENTS.md` still shows DOC-01 as `[ ]` and "Pending" in the traceability table. Mark it Complete when the phase closes |

Orphaned requirements: none. REQUIREMENTS.md maps exactly SPEC-07, SPEC-08 and DOC-01 to Phase 4, and every one is claimed by a plan.

### Prohibitions

No prohibition declares a `verification:` tier, so all are treated as judgment-tier. Verdicts below are **non-authoritative LLM judgments**. Items with no enforcing test are flagged `unverified-prohibition — human review recommended` (Human Verification item 7).

| Plan | Prohibition | Judgment | Enforcement evidence | Flag |
| ---- | ----------- | -------- | -------------------- | ---- |
| 04-01 | Copy specs sends text only to the local clipboard (no network, file or telemetry) | Holds | Code read: `Copy-Specs` only calls `Clipboard.SetText` | unverified-prohibition — human review recommended |
| 04-01 | Copied text has nothing the Home page doesn't show (no serials, UUIDs, keys, MAC/IP, user names) | Holds | Code read: `Get-SpecText` uses only `$env:COMPUTERNAME` (shown in the header), `Get-HostLine` and model values. The only `Serial` string in Akari.ps1 is the filler-filter list (`:124`). See advisory WR-03 on the host name | unverified-prohibition — human review recommended |
| 04-01 | Copying doesn't start a read, change SpecData or touch the busy guard | Holds | AST check in 04-01 v1 (no Start-SpecRead or Invoke-Code). `Copy-Specs` writes only `CopiedUntil` and the label | test-backed |
| 04-01 | Health colours use only Warn, Bad, Tx or Mu; never colour an unread value | Holds | 04-01 v5 (brushes, guards, 15 keys) | test-backed |
| 04-02 | README keeps the install URL, owner and Credits; no other download source | Holds | Diff against b4abbad (IWR and Credits identical). The only URLs are the IWR raw link and the FR33THY credit | unverified-prohibition — human review recommended |
| 04-02 | README describes no features the app lacks | Holds | Read in full: no temperatures, network cards, scheduled refresh or PS7. "about 127 tweaks" is slightly high (126 registrations, review IN-07) | unverified-prohibition — human review recommended |
| 04-03 | No blocking Stop, EndInvoke or Dispose on a running pipeline from the UI thread | Holds | 04-03 v1 measures UI block time on an uninterruptible hang | test-backed |
| 04-03 | No second timer | Holds | One `DispatcherTimer` in Akari.ps1 (`:861`) | test-backed (grep) |
| 04-03 | Tweak runs look the same to the user | Likely holds | Code read only (truth 44) | unverified-prohibition — human review recommended |
| 04-03 | No seventh spec group; no renamed field | Holds | 04-03 v5 and v8 (six groups) | test-backed |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| Akari.ps1, UI/MainWindow.xaml, README.md | none | TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER | none | No debt markers |
| Akari.ps1 | 43, 187/210 | Review WR-01 (open): 8 sequential 10 s CIM bounds against a 20 s whole-read deadline, with Win32_OperatingSystem queried twice. Two slow classes discard the whole read | ⚠️ Warning | Robustness gap in the 04-03 watchdog design. Does not break any must-have as written (truth 35 covers a single hung class) |
| Akari.ps1 | 759, 897 | Review WR-02 (open): Copy exports old values or the failed composite with no marker | ⚠️ Warning | Conflicts in spirit with the Core Value ("wrong or stale specs fail the page"). However, D-05 and the 04-01 failed-read FLAGGED truth explicitly chose this behaviour. It is a user decision, not a gap |
| Akari.ps1 / README.md | 801 / 6 | Review WR-03 (open): copied sheet starts with the computer name; README suggests pasting into forums | ⚠️ Warning | Privacy concern. D-06 explicitly requires the name. Consider a README note |
| Akari.ps1 | 871-880, 837, 825-831, 867, 314, 688/703 | Review IN-01..IN-06 (open) | ℹ️ Info | Advisory polish |
| README.md | 2 | "about 127 tweaks" vs 126 `Add-Tweak` registrations (IN-07) | ℹ️ Info | Hedged with "about" |
| .planning/phases/02-hardware-spec-cards/02-02-PLAN.md | harness | Phase 2 checks 1, 3 and 4 mock `Get-CimInstance{[CmdletBinding()]param([string]$ClassName)}`, which rejects the new `-OperationTimeoutSec`. They now print FAIL on the current tree | ⚠️ Warning | Stale test harness, not a product regression (the orchestrator confirmed PASS with the mock extended, and PASS on b4abbad). Update the mock signature, or future regression runs will report false failures |

### Human Verification Required

### 1. Copy specs in the real app
**Test:** Open the app. On Home, click "Copy specs" (right side, level with your computer's name), then paste into Notepad.
**Expected:** The button says "Copied" for about 2 seconds, then "Copy specs". The paste shows your computer name, maker and model, a blank line, then CPU, GPU, RAM, Disk, Board and Windows lines matching the cards. No new message at the bottom. It still copies while the cards are faded after switching pages.
**Why human:** Real click and paste.

### 2. Health colours
**Test:** Look at the RAM and Disk cards. Push memory use above 80% (many tabs or apps), switch page and come back.
**Expected:** Normally everything is white and nothing is green. RAM "Used" turns amber above 80% and red above 90%. Nothing else changes colour.
**Why human:** Real colour under real load.

### 3. README read-through
**Test:** Open README.md on GitHub.
**Expected:** About one screen, no pictures, covers Akari, the Home page (Copy specs, colours), 8 categories, Optimize/Default and risk labels, the same install line, the zip route, and the same Credits line.
**Why human:** Readability and fit.

### 4. Home never stays faded
**Test:** Switch between Home and other pages a few times.
**Expected:** The cards fade briefly, then show fresh values within a couple of seconds. They never stay faded and no new message appears.
**Why human:** Live behaviour in the running app.

### 5. CPU card and tweak runs
**Test:** Look at the CPU card, then run a couple of tweaks from other pages.
**Expected:** The CPU card is the same as before with no "Sockets" line. Each tweak still shows its messages and a "Done" line, and the buttons work as before.
**Why human:** Real tweak runs through the tick (behavior-unverified truth 44).

### 6. (Optional) Clipboard busy
**Test:** With another program holding the clipboard, click Copy specs.
**Expected:** The button shows "Copy failed" for about 2 seconds and the app keeps working.
**Why human:** Error path that no harness exercises (truth 18). Hard to set up. An override is reasonable.

### 7. Prohibition sign-off
**Test:** Review the Prohibitions table above.
**Expected:** You agree with the four flagged judgment verdicts.
**Why human:** Prohibitions without an enforcing test are never passed silently.

Not testable on this host, and recorded as accepted residual risk: a real hung WMI provider (truth 35) and a real dual-socket machine (truth 39 was only verified with a mock).

### Gaps Summary

There are no blocking gaps. All three roadmap success criteria are met in the code and backed by harnesses that I re-ran on the merged tree (17/17 PASS):
- The Copy specs button, the shared card model and the clipboard text.
- The strict-threshold Disk Free / RAM Used colouring.
- The 50-line README with an unchanged install line and Credits.

The 04-03 review fixes (watchdog, single SpecData writer, multi-socket sums) are also in place and tested.

Status is `human_needed` for three reasons:
- Five end-of-phase human checks were harvested from the plans.
- Three truths are present but not behaviorally proven: clipboard contention, a real single hung CIM class, and unchanged tweak runs.
- Four judgment-tier prohibitions are flagged.

Non-blocking follow-ups:
- Mark DOC-01 Complete in REQUIREMENTS.md.
- Fix the stale Phase 2 CIM mock signature.
- Decide on review warnings WR-01 (timeout budget), WR-02 (stale/failed copy unmarked) and WR-03 (host name in copied text), all still `open` in 04-REVIEW-DISPOSITION.md.

---

_Verified: 2026-10-09T09:56:41Z_
_Verifier: Claude (gsd-verifier)_
