---
phase: 03-home-shell-live-refresh
verified: 2026-10-08T20:33:00Z
status: passed
score: 37/37 must-haves verified
covered_files:
  - .planning/phases/03-home-shell-live-refresh/03-01-PLAN.md
  - .planning/phases/03-home-shell-live-refresh/03-01-SUMMARY.md
  - .planning/phases/03-home-shell-live-refresh/03-02-PLAN.md
  - .planning/phases/03-home-shell-live-refresh/03-02-SUMMARY.md
  - Akari.ps1
  - UI/MainWindow.xaml
covered_digest: "v3:sha256:77e28890c95ff51ead03a7eb72880ca853fb7de9a28281ddcd3a807a41b36f9f"
behavior_unverified: 0
overrides_applied: 0
coincidental_reliance_items:
  - truth: "Cards wrap into 3 columns at the default 1000px window width"
    reason: undeclared-precondition
    harden: "The fit relies on the default window frame and a 17 DIP scrollbar at 100% scaling. Measured: 762 DIP available without a vertical scrollbar, about 745 DIP with one, and 744 DIP needed for 3 cards (240 + 8 margin each). That leaves about 1 DIP of slack. Another scaling or theme setting could drop the grid to 2 columns. Either accept that or declare a minimum slack."
flagged_prohibitions:
  - statement: "The spec read must not send machine specs anywhere (local CIM/registry read only)"
    verdict: "holds (non-authoritative LLM judge)"
    flag: "unverified-prohibition - human review recommended"
  - statement: "Home must not auto-apply, auto-run, or offer to run any tweak"
    verdict: "holds (non-authoritative LLM judge)"
    flag: "unverified-prohibition - human review recommended"
  - statement: "Home must not visually restyle the existing app chrome; no new style, brush or colour value"
    verdict: "holds (non-authoritative LLM judge)"
    flag: "unverified-prohibition - human review recommended"
  - statement: "No spec value may be hard-coded or synthesized as a static string"
    verdict: "holds (non-authoritative LLM judge)"
    flag: "unverified-prohibition - human review recommended"
  - statement: "The refresh must not present stale values as freshly queried"
    verdict: "holds (non-authoritative LLM judge); see review IN-01 for the in-flight reuse edge"
    flag: "unverified-prohibition - human review recommended"
  - statement: "A card must never stay on the loading placeholder after a read ends"
    verdict: "holds for throw / empty result (tested); a read that never ends is review WR-01"
    flag: "unverified-prohibition - human review recommended"
  - statement: "The spec read must not block the UI thread or prevent starting a tweak"
    verdict: "holds (non-authoritative LLM judge, backed by harness run)"
    flag: "unverified-prohibition - human review recommended"
  - statement: "A successful refresh must not write to the log drawer"
    verdict: "holds (non-authoritative LLM judge, backed by harness run)"
    flag: "unverified-prohibition - human review recommended"
  - statement: "The header must not surface serial numbers, UUIDs, asset tags or hardware ids"
    verdict: "holds (non-authoritative LLM judge)"
    flag: "unverified-prohibition - human review recommended"
human_verification:
  - test: "Open the app."
    expected: "It opens on Home. Home is the first item in the left menu and is selected, with a thin line under it and Check below that. Clicking the thin line does nothing."
    why_human: "What the menu looks like on screen"
  - test: "Look at the Home page at its normal size."
    expected: "Six cards in this order: CPU, GPU, RAM, Disk, Board, Windows. They sit in three columns, and cards in the same row are the same height. They have the same dark look and colours as the rest of the app."
    why_human: "Visual look and the column count at your screen's scaling"
  - test: "Make the window as narrow as it goes."
    expected: "The cards sit in two columns. You can scroll the page up and down, but it never scrolls sideways. Long names wrap onto more lines inside their card and never stick out."
    why_human: "Visual layout when the window is resized"
  - test: "Read the numbers on the cards."
    expected: "They use a dot, not a comma, like 3.80 GHz and 31.9 GB. The Disk card shows only the Windows drive (C:). If your PC has more than one graphics card, they all appear in the GPU card with a thin line between them."
    why_human: "Checks the on-screen values against your machine"
  - test: "Look at the top of Home."
    expected: "Your computer's name is in large text. Under it is your PC maker and model, which on this PC reads ASUSTeK COMPUTER INC. · TUF GAMING B550-PLUS. When the window is narrow, that line stays on one line and ends in … if it does not fit. Hovering over it shows the full text."
    why_human: "Visual header and tooltip"
  - test: "Go to another page, then click Home again."
    expected: "The cards look faded for a moment while they update, then go back to normal. While they are faded you can still click the menu, type in the search box and start a tweak on another page. No new message appears at the bottom of the window."
    why_human: "A short timing effect while the specs update"
  - test: "Start a tweak that takes a while, then click Home straight away."
    expected: "The cards are still there, faded. When the tweak finishes, they go back to normal on their own."
    why_human: "Live timing with a real tweak"
  - test: "On Home, type something in the search box, then clear it."
    expected: "While you type, Home goes away and matching results show. When you clear the box, Home comes back with its cards."
    why_human: "On-screen behaviour of the page"
  - test: "Click through a few of the other pages (Check, Windows, Advanced)."
    expected: "They look and work exactly as before."
    why_human: "Confirms nothing else in the app changed"
---

# Phase 3: Home Shell & Live Refresh Verification Report

**Phase Goal:** Home as default landing with card grid, live refresh, and navigation
**Verified:** 2026-10-08T20:33:00Z
**Status:** human_needed
**Re-verification:** No. This is the initial verification.

> **MVP-mode note:** ROADMAP marks Phase 3 `Mode: mvp`, but its goal line is not a user story. `user-story.validate` returns `valid: false` for it. Both PLANs restate it as a user story, and that wording validates (`valid: true`): «As a user, I want to land on Home by default and see my system specs in a card grid, so that I can see accurate, live system specs at a glance.» The User Flow Coverage table below uses that restatement. To make ROADMAP.md consistent, run `/gsd-mvp-phase 3`. This does not change the verdict.

## User Flow Coverage

User story: «As a user, I want to land on Home by default and see my system specs in a card grid, so that I can see accurate, live system specs at a glance.»

| Step | Expected | Evidence | Status |
|------|----------|----------|--------|
| Launch the app | Opens on Home, and Home is selected first in the sidebar | `Akari.ps1:34` `$script:Cat = 'Home'`. `Add_Loaded` (`:947`) checks the nav item whose Tag matches, which raises the nav handler and then `Show-Page`. Harness: the real sidebar loop gives `Home,Check,…,Advanced` with a 1px non-focusable Bd divider at index 1 | ✓ |
| See the Home page | Header with the computer name, plus a six-card grid. No heading and no "Nothing here yet." | `Show-Page` `$onHome` branch (`:476-500`). The 03-01 Task 1 verify passed: HomePanel Visible, Heading Collapsed, Rows empty, HostName equals COMPUTERNAME | ✓ |
| Specs load in the background | Six Loading… cards first, then live values. The app stays usable | `Start-SpecRead` (`:737`) runs on a separate runspace and is harvested by the tick (`:770`). Harness: Page stays enabled, `Busy` stays false, and the real tick harvest gives the composite with groups `CPU,Disk,GPU,Motherboard,RAM,Windows` | ✓ |
| Return to Home later | Values are queried again, the grid dims while it updates, and nothing is cleared | Harness: Check, then Home starts a new read. Cards/HostSub opacity is 0.6 while HostName stays at 1, six cards stay present, and opacity is back to 1 after the harvest | ✓ |
| Outcome: accurate, live specs at a glance | Real machine values in a readable grid | Live run on this host: HostSub = `ASUSTeK COMPUTER INC. · TUF GAMING B550-PLUS`, six cards. Layout measured at 3 columns (1000px) and 2 columns (820px), never with a horizontal scrollbar | ✓ (visual sign-off pending) |

## Goal Achievement

### Observable Truths

ROADMAP success criteria (contract):

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1: User lands on Home by default on app launch | ✓ VERIFIED | Default category `'Home'` (`:34`). The sidebar's first RadioButton is Home (`:854`). `Add_Loaded` selects it. Verify 03-01 #3 checks "default landing category is Home": PASS |
| 2 | SC2: Specs in a fluid card grid matching the dark theme | ✓ VERIFIED | `Cards` WrapPanel (`MainWindow.xaml:217`). `New-Card` gives a 240px Border using `S1`/`Bd`, and the text uses `Tx`/`Mu` only. Layout measured: 3 columns at 1000, 2 columns at 820, horizontal scroll Collapsed |
| 3 | SC3: Friendly hostname/manufacturer header | ✓ VERIFIED | `HostName = $env:COMPUTERNAME` (`:625`). HostSub is the Maker · Model pair with the D-17 fallback (`:716-733`). Verify 03-02 #3 passed all four cases, and the live host shows the board pair |
| 4 | SC4: Freshly queried every time Home is shown, without UI blocking | ✓ VERIFIED | Show-Page's Home branch calls `Update-Home; Start-SpecRead`. The read uses its own runspace, never `Set-Busy`. Verify 03-01 #1 and #3 PASS. Harness: re-show starts a read, Page.IsEnabled stays true, and a read deferred during a real tweak runs exactly once afterwards |

Plan 03-01 truths:

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 5 | `$script:SpecData` is always the `@{Specs;Host}` composite, including after a failed first read | ✓ VERIFIED | Tick `:772-791`. Verify 03-01 #3 (AST check of the composite literal) and 03-02 #2 (a fabricated failing runspace gives Specs+Host, CPU Failed, Host both Not available): PASS |
| 6 | CPU card: model headline, Cores and Speed rows, invariant culture | ✓ VERIFIED | `:643-652`. Verify 03-01 #4 gives `8 / 16 threads` and `3.80 GHz` (the host culture is it-IT) |
| 7 | Spec values never reach markup through interpolation | ✓ VERIFIED | Every card is built with `[Windows.Controls.*]::new()` and `.Text =`. No XamlReader call in the Home block |
| 8 | FA adjacency: cards never overlap, and the spec render runs before the tweak redraw in the same tick | ✓ VERIFIED | Margin `0,0,8,8`. Measured Y positions give distinct rows. Verify 03-01 #3 checks that `$sj = ` comes before `$j = ` |
| 9 | FA empty: with no data, the grid shows the loading placeholder | ✓ VERIFIED | `:630-640`. Verify 03-02 #1 shows six Loading… cards |
| 10 | FA ordering: fixed card order, items in read order | ✓ VERIFIED | Sequential blocks with `for` loops over `@($list)`. Verify 03-01 #4 confirms the order |
| 11 | FA: the Home shell follows the 03-UI-SPEC layout contract | ✓ VERIFIED | The static panel sits inside Page and Heading is collapsed on Home. The empty-state guard includes `-not $onHome` |
| 12 | FA: no tweak registers the Home category | ✓ VERIFIED | `grep "Category 'Home'" Tweaks/` finds 0 matches |
| 13 | FA: 3 columns fit at 1000px (tight) | ✓ VERIFIED (coincidental-reliance) | Measured Cards ActualWidth 762 and 3 columns in the first row. About 1 DIP of slack once a vertical scrollbar appears, see `coincidental_reliance_items` |
| 14 | Sidebar Home is first and checked, followed by a 1px Bd divider that cannot be clicked or focused | ✓ VERIFIED | Harness ran the real loop: child 0 is the Home RadioButton, child 1 is a Border with Height 1, Focusable False, IsHitTestVisible False and Bd brush, child 2 is Check |
| 15 | Six cards in order, and cards in a row share the tallest height | ✓ VERIFIED | Measured heights 323/323, 133/133 and 132/132 per row |
| 16 | Wrap: 2 columns at 820, 3 at 1000, vertical scroll only | ✓ VERIFIED | Measured. The ScrollViewer has `HorizontalScrollBarVisibility="Disabled"` (`MainWindow.xaml:204`) |
| 17 | Each adapter or volume is its own headline-plus-rows block | ✓ VERIFIED | `:656-666` and `:683-695`. Verify 03-01 #4 |
| 18 | Zero, one or many items: dividers only between items | ✓ VERIFIED | `if ($i -gt 0) { Add-Divider }`. Verify 03-01 #4 gives 1 GPU divider. The 3-adapter harness gives 2 |
| 19 | Many items make the card taller and the page scroll vertically | ✓ VERIFIED | 3-adapter GPU card measures 323 tall, with vScroll Visible and hScroll Collapsed |
| 20 | Formats `0.0 GB` and `0.00 GHz`, Cores partial rule, GPU Status only when not OK | ✓ VERIFIED | `Fmt-Num` uses InvariantCulture. Verify 03-01 #4 shows exactly 1 Status row, and a sentinel never gets a unit |
| 21 | Values wrap, labels sit in a 72px column, card width stays 240 | ✓ VERIFIED | `Add-Row` Grid uses a 72/* layout with TextWrapping Wrap. Long-text harness: card ActualWidth 240 |
| 22 | Home with an empty search shows the panel, collapses the heading, leaves Rows empty and shows no empty-state | ✓ VERIFIED | Verify 03-01 #1 |
| 23 | Typing hides Home. Clearing shows it again with one refresh | ✓ VERIFIED | Verify 03-01 #1 runs the search for "bios", then clears it. The one-flight guard holds |
| 24 | Long model names and values wrap inside 240px and never widen the card | ✓ VERIFIED | Long-text harness: CPU and GPU cards stay 240 wide, and the headline wraps to 120 DIP high |

Plan 03-02 truths:

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 25 | First show: every card shows title and Loading… in Mu, and HostSub is collapsed | ✓ VERIFIED | Verify 03-02 #1 checks for U+2026 and Collapsed |
| 26 | In flight or deferred: grid and HostSub at 0.6, name at 1, nothing cleared | ✓ VERIFIED | Verify 03-02 #1. Harness used the real Show-Page path, where `Set-HomeDim` dims after the read starts |
| 27 | On completion, all six are rebuilt in one pass and opacity goes back to 1 | ✓ VERIFIED | `Update-Home` clears and rebuilds synchronously. The harness confirmed opacity 1 after the tick |
| 28 | Partial group: Not available for failed fields, normal values elsewhere | ✓ VERIFIED | Verify 03-01 #4: the Board headline drops the sentinel and the second adapter's VRAM reads Not available |
| 29 | Failed group: muted Not available headline with rows still listed. Zero-item GPU/Disk shows headline only | ✓ VERIFIED | Verify 03-02 #1 checks the Mu brush and that the GPU card has exactly 2 children |
| 30 | A throwing or empty read never strands Loading… and writes exactly one log line | ✓ VERIFIED | Verify 03-02 #2: one line per failure, with both tail copies |
| 31 | A successful refresh writes nothing to the log | ✓ VERIFIED | Harness: two real successful reads, and the log has no `Specs:` line |
| 32 | Header Maker · Model, with D-17 pair-level fallback | ✓ VERIFIED | Verify 03-02 #3 cases 0-1 |
| 33 | One valid value shows with no separator. Both filler collapses the line | ✓ VERIFIED | Verify 03-02 #3 cases 2-3 |
| 34 | HostName and HostSub stay single-line with ellipsis, and HostSub has a tooltip, including for a long line | ✓ VERIFIED | XAML `TextTrimming="CharacterEllipsis"` (no wrap). Long-text harness: HostSub is 17 DIP high (one line) and clipped to 565, with no horizontal scroll and the tooltip equal to the text |
| 35 | The read never blocks a tweak and a tweak never blocks the read. A deferred read runs exactly once after the tweak | ✓ VERIFIED | Harness: a real `Invoke-Code` tweak sets Busy, Show-Page then sets SpecPending with no job and dims, the tweak-completion tick starts exactly one read and clears the flag, and no second read queues |
| 36 | FA: the dim-to-fresh swap is a single synchronous swap, and reads never queue | ✓ VERIFIED | `if ($script:SpecJob) { return }`. Verify 03-01 #1 re-show reuses the read in flight |
| 37 | FA: zero-item groups and a whole failed read both use the Failed-shaped card, never an empty grid | ✓ VERIFIED | Verify 03-02 #2 re-renders 6 cards after a failed first read |

**Score:** 37/37 truths verified (0 present but behavior-unverified, 1 advisory coincidental-reliance)

Merged duplicates: the 03-01 truths 1-4 restate SC1-SC4. The 03-02 "failed first read composite" truth is #5. The 03-02 "long names wrap" truth is #24. The 03-02 "long Maker · Model ellipsis" truth is #34.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Akari.ps1` | Home landing, spec channel, renderer, sidebar item, header resolution | ✓ VERIFIED | All 19 `contains` tokens are present (each grep count ≥ 1), and the file parses with 0 errors. Every function is called: `Update-Home` from Show-Page and the tick, `Start-SpecRead` from Show-Page and the drain |
| `UI/MainWindow.xaml` | HomePanel, HomeHeader, HostName, HostSub, Cards WrapPanel, ellipsis trimming | ✓ VERIFIED | All x:Names are present, and XamlReader parse plus FindName succeed. Bound through the Set-Variable list at `Akari.ps1:384` |

Note: `gsd query verify.artifacts` reported 0/2 with "Missing pattern" because it treats the YAML `contains:` array as one comma-joined string. Each token was checked individually and every one is present. This is a tool false negative, not a stub.

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| MainWindow.xaml HomePanel | Akari.ps1 Show-Page | `$HomePanel.Visibility` flipped by `$onHome` | ✓ WIRED | verify.key-links 3/3 (03-01) |
| Show-Page Home branch | Start-SpecRead | `if ($onHome) { Update-Home; Start-SpecRead }` | ✓ WIRED | |
| Start-SpecRead | 150 ms tick | `$script:SpecJob` slot, separate from `$script:Job`/Busy | ✓ WIRED | Static verify 03-01 #3 |
| Read state | Cards/HostSub opacity | `$dim` in Update-Home plus `Set-HomeDim` | ✓ WIRED | verify.key-links 3/3 (03-02) |
| Header | Motherboard fallback | `$d.Specs.Motherboard.Manufacturer/Product` | ✓ WIRED | |
| Tick failure branch | `New-FailedSpecs` composite | `@{ Specs = New-FailedSpecs; Host = … }` | ✓ WIRED | |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| Six cards | `$script:SpecData.Specs` | `Get-Specs` (CIM) in the spec runspace, harvested by the tick | Yes. The live run returned all six groups | ✓ FLOWING |
| HostSub | `$script:SpecData.Host` / `.Specs.Motherboard` | `Get-HostIdentity` (Win32_ComputerSystem) plus Get-Specs | Yes: `ASUSTeK COMPUTER INC. · TUF GAMING B550-PLUS` | ✓ FLOWING |
| HostName | `$env:COMPUTERNAME` | Process environment, synchronous | Yes | ✓ FLOWING |

### Behavioral Spot-Checks

PowerShell could run in this verifier's process, so I ran every check myself. I did not rely on the orchestrator's or the SUMMARY's PASS claims.

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 03-01 T1: Home landing, real tick harvest, CPU card | plan `<automated>` #1 | PASS (groups=CPU,Disk,GPU,Motherboard,RAM,Windows) | ✓ PASS |
| 03-01 T1: Get-Specs six-group regression | plan #2 | PASS live | ✓ PASS |
| 03-01 T1: static guards (busy, Show-Page, composite, HOME, -ResultVar) | plan #3 | PASS | ✓ PASS |
| 03-01 T2: six-card content map | plan #4 | PASS | ✓ PASS |
| 03-01 T2: regression | plan #5 | PASS live | ✓ PASS |
| 03-02 T1: loading, dimmed, deferred, failed and zero-item states | plan #1 | PASS | ✓ PASS |
| 03-02 T1: failed read through the real tick (first read and with earlier data) | plan #2 | PASS | ✓ PASS |
| 03-02 T2: header four cases plus single Test-SmbiosValue | plan #3 | PASS | ✓ PASS |
| 03-02 T2: regression | plan #4 | PASS live | ✓ PASS |
| Sidebar loop, launch selection, real re-show dim/restore, no log on success, deferred read during a real tweak | scratch harness `vx-extra.ps1` | PASS | ✓ PASS |
| Column fit at 1000 and 820, no horizontal scroll | `vx-layout.ps1` (hidden off-screen window) | 3 columns and 2 columns, hScroll Collapsed | ✓ PASS |
| Long text wraps in 240px, HostSub single-line ellipsis and tooltip | `vx-wrap.ps1` | card 240, HostSub 17 DIP high, tooltip full text | ✓ PASS |
| Row height matching, multi-item growth | `vx-rows.ps1` | 323/323, 133/133, 132/132, 2 dividers | ✓ PASS |

### Probe Execution

Not applicable. The phase declares no probes, and the repo has no `scripts/*/tests/probe-*.sh`.

### Prohibitions (judgment tier)

Every prohibition is a plain must-NOT statement with no wired test. Each gets a non-authoritative judge verdict and the flag `unverified-prohibition - human review recommended` (also listed in `flagged_prohibitions`).

| Prohibition | Judge verdict | Evidence |
|-------------|---------------|----------|
| No outbound send of specs | Holds | `$GetSpecsFunc`, `$HostIdentityFunc` and `$SpecReadCode` contain no web, socket or REST call. The only `Serial` text is a filler string in `Test-SmbiosValue` |
| Home never auto-runs a tweak | Holds | The Home path calls no `Invoke-Code` and has no button. The empty Home category has no rows |
| No chrome restyle or new brush | Holds | The XAML diff adds only the Home panel. The Akari.ps1 diff adds no `Warn`/`Bad`/hex colour and uses FindResource S1/Bd/Tx/Mu only |
| No hard-coded spec value | Holds | Every card value comes from `$script:SpecData.Specs`. Literals are titles, labels and the `Not available` sentinel |
| No stale-as-fresh | Holds, with an edge case | Every show re-queries and the grid is dimmed while the read is in flight. Review IN-01: a re-show during a read that is still running reuses that read |
| Never stuck on Loading… after a read ends | Holds for throw and empty result | Review WR-01: a read that never ends (hung CIM) has no timeout |
| No UI block or tweak block | Holds | Harness checks for Page.IsEnabled and Busy |
| No log on success | Holds | Harness |
| No serial, UUID or hardware ids | Holds | Host keys are exactly `Manufacturer,Model` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SHELL-01 | 03-01 | Lands on Home by default | ✓ SATISFIED | Truths 1, 14, 22 |
| SHELL-02 | 03-01, 03-02 | Fluid card grid in the dark theme | ✓ SATISFIED (visual sign-off pending) | Truths 2, 15-21, 24-29 |
| SHELL-03 | 03-01, 03-02 | Friendly hostname/manufacturer header | ✓ SATISFIED | Truths 3, 32-34 |
| REFR-01 | 03-01, 03-02 | Fresh specs on every Home show, background, loading state, never blocks | ✓ SATISFIED | Truths 4, 23, 25-27, 30, 35-37 |

Orphaned requirements: none. REQUIREMENTS.md maps exactly SHELL-01/02/03 and REFR-01 to Phase 3, and every one is claimed by a plan. The REQUIREMENTS.md checkboxes and traceability rows still read Pending, so the orchestrator should update them.

Phase 2 items deferred to this phase: card rendering is delivered. The refresh lifecycle concerns are resolved as follows:
- WR-07 (refresh dropped while busy) is resolved by `SpecPending`.
- WR-08 (BeginInvoke failure leaves Busy stuck) no longer applies, because the spec path never sets Busy.
- WR-06 (ResultVar harvest) is still dormant. It has no caller (static check), and is carried as review WR-02.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| Akari.ps1, UI/MainWindow.xaml | none | TBD/FIXME/XXX/TODO/HACK debt markers | none | None found |
| Akari.ps1 | 739, 770 (review WR-01) | No timeout on the spec read. A hung CIM query keeps Home dimmed or on Loading… for the session, with no log line | ⚠️ Warning | REFR-01 robustness on a broken WMI host. Not a must-have failure, because no read ends stuck |
| Akari.ps1 | 797-801 (review WR-02) | The dormant `-ResultVar` harvest would overwrite `$script:SpecData` with a non-composite shape | ⚠️ Warning | No caller today (AST check PASS). Phase 4 must not reuse it |
| Akari.ps1 | 152-158 (review WR-03) | The CPU card uses only the first socket | ⚠️ Warning | Under-reports cores and threads on multi-socket hosts. Inherited from Phase 2 |
| Akari.ps1 | 683-695 (review IN-04) | The Disk loop and divider are dead after the system-drive-only change | ℹ️ Info | Harmless |

The three open review warnings are recorded in 03-REVIEW-DISPOSITION.md. They do not fail any must-have. The developer can fix them (`/gsd-code-review 03 --fix`) or record a deferral there. WR-01 is the most relevant to the core value of live, accurate specs.

### Human Verification Required

These checks are plain on-screen checks with no internals. They are also in the frontmatter.

1. **Opening screen.** Open the app. It opens on Home. Home is the first item in the left menu and is selected, with a thin line under it and Check below that. Clicking the thin line does nothing.
2. **Card grid.** At normal size you see six cards in this order: CPU, GPU, RAM, Disk, Board, Windows. They sit in three columns, and cards in the same row are the same height. They have the same dark look as the rest of the app.
3. **Narrow window.** Make the window as narrow as it goes. The cards sit in two columns, and the page never scrolls sideways. Long names wrap inside their card.
4. **Numbers.** Numbers use a dot, like 3.80 GHz and 31.9 GB. The Disk card shows only the Windows drive (C:). If you have more than one graphics card, they all appear in the GPU card with a thin line between them.
5. **Header.** Your computer's name is in large text. Under it is the maker and model (on this PC: ASUSTeK COMPUTER INC. · TUF GAMING B550-PLUS). In a narrow window that line stays on one line and ends in …. Hovering over it shows the full text.
6. **Coming back to Home.** Go to another page, then click Home. The cards fade for a moment and then go back to normal. While they are faded you can still click around, type in search and start a tweak. No new message appears at the bottom.
7. **During a tweak.** Start a tweak that takes a while and click Home right away. The cards are still there, faded. When the tweak finishes they go back to normal on their own.
8. **Search.** On Home, type in the search box: Home goes away and results show. Clear it: Home comes back.
9. **Other pages.** Check, Windows and Advanced look and work as before.

### Gaps Summary

No gaps. All four ROADMAP success criteria and all 33 additional plan truths are achieved in the code, and I confirmed them by running every plan verify command (9/9 PASS) plus four extra harnesses in this verifier's own process. Those harnesses covered the sidebar, the real re-show and deferred-read paths, and the measured layout. The status is `human_needed` for two reasons:
- The visual and timing checks above can only be confirmed by looking at the running app.
- Nine judgment-tier prohibitions are flagged for human review under the prohibition protocol. All of them hold on the evidence.

Separately, review WR-01 (no timeout on the spec read) is the remaining robustness risk to REFR-01's "live" promise. It should be fixed or explicitly deferred.

---

_Verified: 2026-10-08T20:33:00Z_
_Verifier: Claude (gsd-verifier)_
