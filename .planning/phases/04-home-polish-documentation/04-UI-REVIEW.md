# Phase 04 — UI Review

**Audited:** 2026-10-09
**Baseline:** no phase-local UI-SPEC.md — audited against the abstract 6-pillar standards, with `.planning/phases/03-home-shell-live-refresh/03-UI-SPEC.md` (approved design contract for the Home page: token set, spacing scale, 4-size/2-weight typography table, 60/30/10 colour split, copywriting contract) used as the nearest design-system reference, and `04-CONTEXT.md` D-01…D-18 as the phase's own copy/colour decisions.
**Screenshots:** not captured (no dev server — this is a Windows PowerShell 5.1 + WPF desktop app; nothing listens on localhost:3000/5173/8080, verified by port probe). Code-only audit.
**Interaction captures:** off (`workflow.ui_interaction_capture` is false; the chrome-devtools driver targets Chromium and is not applicable to a WPF window). All interaction findings below are code-derived and labelled as such.

**Sources audited:** `UI/MainWindow.xaml` (306 lines, whole file), `Akari.ps1` (1020 lines, Home/copy/watchdog regions in full), `README.md` (50 lines, whole file).

**Registry safety audit:** skipped — no `components.json` and no registry table in any UI-SPEC for this project (WPF/inbox .NET only, zero third-party UI code).

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | Every string is specific and contract-exact, but the disabled and failure states carry no reason or remedy |
| 2. Visuals | 3/4 | CopySpecs has no MinWidth, so the label swap re-trims the computer name for 2 s on every click |
| 3. Color | 3/4 | Token discipline is perfect (15 keys, zero hardcoded hex), but the 0.6 refresh dim drops the new red/amber health values to ≈2.7:1 / ≈3.7:1 contrast |
| 4. Typography | 3/4 | Home now carries 5 sizes — the Btn label's 12.5 is a fifth size the design contract's typography table never lists |
| 5. Spacing | 4/4 | Every Home spacing literal sits on the declared 4/8/12/16 scale; zero arbitrary values |
| 6. Experience Design | 3/4 | State coverage is complete and WR-01 is closed, but a hung read leaves Home silently faded at 0.6 for up to 20 s |

**Overall: 19/24**

---

## Top 3 Priority Fixes

1. **Pin the CopySpecs button width** — *User impact:* every click (and every revert 2 s later) changes the button's auto width between "Copied" / "Copy specs" / "Copy failed". Docked `Right` in `HomeHeader`, it steals or returns width from the fill child, so `HostName` (which is `TextTrimming=CharacterEllipsis`) visibly gains and loses characters and the header reflows mid-interaction. — **Fix:** in `UI/MainWindow.xaml:212` add `MinWidth="104"` (widest label "Copy failed" at 12.5px + 12,5 padding + 1px borders + 6 margin, rounded up) or a fixed `Width`, so the three label states occupy identical layout space.

2. **Keep the two health values at full opacity during a refresh dim** — *User impact:* the amber/red Disk-Free and RAM-Used values are the only signal-bearing text on Home, and they are exactly what a user reads while the grid sits at `Opacity=0.6`. Blended over the `S1` card, `Warn` `#D9A441` falls to ≈3.7:1 and `Bad` `#E5645A` to ≈2.7:1 — both below WCAG AA 4.5:1 — for the whole in-flight window, which this phase extended to as long as 20 s (watchdog deadline). — **Fix:** in `Akari.ps1`, instead of `$Cards.Opacity` / `$HostSub.Opacity` (lines 756-757, 857-858), tag the two health TextBlocks (set `Tag = 'Health'` in `Add-Row` when a non-`Tx` key is passed) and either leave them at opacity 1 or apply the dim only to the card `Border` children that are not health values.

3. **Give the user feedback during the 20-second watchdog window** — *User impact:* after this phase's WR-01 fix, a hung WMI provider no longer freezes Home forever — but for up to 20 seconds the only visible symptom is the cards sitting at 0.6 opacity, with no text and no log line until the deadline fires. From the user's seat that is indistinguishable from the Phase 3 bug the phase set out to close. — **Fix:** in the 150 ms tick (`Akari.ps1:869`), when a read is older than ~5 s and still running, either `Add-Log 'Specs: Reading (taking longer than usual)...'` once, or set a small `Mu` TextBlock ("Reading specs…") in `HomeHeader` until the read completes or is abandoned.

---

## Detailed Findings

### Pillar 1: Copywriting (3/4)

**What holds (verified by grep over all user-facing strings in `Akari.ps1:534-900` and the whole of `MainWindow.xaml`):**

- The CTA label is specific and verb-first: `Copy specs` (`MainWindow.xaml:212`), matching the README's "Copy specs" (`README.md:6`) and the approved plan D-01. No generic `Submit` / `Click Here` / `OK` anywhere — the only grep hits for those tokens in the repo are `$ok` locals and `_Status = 'OK'` data keys, not user-visible copy.
- Transient feedback is two distinct states, not one success-only path: `Copied` (`Akari.ps1:827`) and `Copy failed` (`Akari.ps1:830`), reverted by the existing tick after 2 s (`Akari.ps1:867`).
- The button has a purpose-stating tooltip: `Copy all specs as text` (`MainWindow.xaml:213`) — it is not an unlabelled icon button.
- The copied sheet matches the user-approved preview in `04-CONTEXT.md` line-for-line: computer name, `Maker · Model` (separator built from `[char]0x00B7`, `Akari.ps1:745`), blank line, then `Title: Head` with indented `  Label: Value` rows, and the RAM card inline as `RAM: 31.9 GB (Used 12.4 GB, Free 19.5 GB)` (`Get-SpecText`, `Akari.ps1:799-820`).
- The failure log line is the contractual copy from the 03-UI-SPEC Copywriting Contract, with the timeout variant reusing it verbatim: `Specs: Read failed (timed out after 20 seconds).` plus the existing keep-values / switch-page tail (`Akari.ps1:877, 898-899`).
- `README.md` is 50 lines, contains zero image syntax (0 `![`, 0 `<img`), keeps the IWR one-liner and the Credits sentence byte-identical, and documents the exact label and thresholds the code implements.

**Findings:**

- **W-1.1 (WARNING)** — The disabled first-load state gives the user no reason. `CopySpecs` starts as `IsEnabled="False"` (`MainWindow.xaml:213`) and is only enabled once `$script:SpecData` is non-null (`Akari.ps1:759`), which is roughly the first 1-2 s of a session. The `Btn` template renders it at `Opacity 0.35` (`MainWindow.xaml:39-41`) with no tooltip text, so a fast click lands on a greyed control with no explanation. Fix: add `ToolTip="Waiting for the first spec read"` alongside `IsEnabled="False"` and replace the tooltip in `Update-Home` when enabling.
- **W-1.2 (WARNING)** — `Copy failed` names the failure but not the cause or the remedy. A clipboard held by another process is the overwhelmingly likely cause, and the user's next move (click again) is not suggested. Fix: `Copy failed — another app is holding the clipboard` (fits the 2 s flash; the plan's width note above becomes more important, not less).
- **N-1.3 (nit)** — A failed RAM card copies `RAM: Not available (Used Not available, Free Not available)` — the sentinel is repeated three times on one line. This is exactly what D-02's inline format prescribes, so it is contract-correct, but it is the one copied line that reads as broken rather than as data.

### Pillar 2: Visuals (3/4)

**What holds:**

- Clear focal point on first paint: `HostName` at 22 / SemiBold / `Tx` (`MainWindow.xaml:215`), 69% larger than the next-largest Home text, with the 15 / SemiBold card headlines beneath it.
- The new control reuses the existing `Btn` style (`MainWindow.xaml:213`) rather than a bespoke look, so it is pixel-consistent with the Tuner's `Read current` / `Default` / `Apply` row (`MainWindow.xaml:260-262`) and with every tweak-row button.
- It is not an icon-only button: label plus tooltip, `VerticalAlignment="Center"` against the two-line header.
- Hierarchy is carried by size, weight and colour exactly as the 03-UI-SPEC declares (4 declared sizes, SemiBold vs Regular, `Tx` values against `Mu` labels/titles).
- `HomeHeader`'s structure still satisfies the layout contract: the button is the first (docked-right) child and the host-name `StackPanel` remains the last, fill child (`MainWindow.xaml:212-217`), so the name area still fills the header.

**Findings:**

- **W-2.1 (WARNING)** — **Priority fix 1.** `CopySpecs` has no `Width`/`MinWidth`, and the `Btn` style sets none (`MainWindow.xaml:20-46` — setters are Foreground, Background, BorderBrush, Padding, FontSize, Margin, Cursor, Template). As the first child of a `DockPanel` with `DockPanel.Dock="Right"` it is measured to its desired width, so the three content states have different widths: "Copied" (6 ch) is roughly 40 px narrower than "Copy specs" (10 ch), and "Copy failed" (11 ch) is wider again. Every click therefore changes the fill width of the host-name `StackPanel`, and `HostName` — which is `TextTrimming="CharacterEllipsis"` — re-trims. At the 820 px `MinWidth` the computer name visibly gains and loses characters twice during the 2 s flash. Fix: `MinWidth="104"` on the button (or set `Width`), sized so all three labels occupy identical layout space.
- **W-2.2 (WARNING)** — The button does not participate in the refresh dim. `Update-Home` dims `$Cards` and `$HostSub` to 0.6 (`Akari.ps1:756-757`) and `Set-HomeDim` does the same (`Akari.ps1:857-858`), but `$CopySpecs` stays at opacity 1 for the whole in-flight window. The 03-UI-SPEC dim contract names only the grid and the maker/model line, so this is contract-consistent; it is flagged because it leaves the header's three elements at three different visual weights for up to 20 s, which reads as an unfinished fade rather than a deliberate one. Fix: either include the button in the dim or state the exception in the contract.
- **N-2.3 (nit)** — Code-derived: `Add-Headline` takes a `$brushKey` parameter (`Akari.ps1:570`) that no caller ever passes (health colouring is row-only by D-10), so the parameter is dead. Harmless, but it invites a future caller to colour a headline against D-10.

### Pillar 3: Color (3/4)

**What holds (verified):**

- **D-11 holds exactly.** `x:Key` count in `UI/MainWindow.xaml` is **15** — identical to the 03-UI-SPEC's enumerated set. No brush, colour value or style was added for the health colours; `Warn` `#D9A441` and `Bad` `#E5645A` already existed (`MainWindow.xaml:17-18`) and are now consumed through the existing `FindResource` path.
- **Zero hardcoded colours in the Home additions.** Every Home brush is resolved by key: `S1`/`Bd`/`Tx`/`Mu` in `New-Card`, `Add-Headline`, `Add-Row`, `Add-Divider` (`Akari.ps1:544-555, 576, 595, 601, 611`), and `Warn`/`Bad` arrive only as string keys passed through `Add-Row`. The single colour literal in the whole file, `[Windows.Media.Brushes]::Transparent` (`Akari.ps1:480`), is pre-existing tweak-row code (the state dot) and is untouched by this phase.
- **Accent discipline.** Grep of `FindResource` keys in `Akari.ps1` returns exactly `Bd`, `Btn`, `Inv`, `Mu`, `Nav`, `S1` — six keys, all declared tokens. The health accent is used on at most **two** elements on Home (Disk `Free` value, RAM `Used` value), far under the >10 overuse threshold, and the 60/30/10 distribution (`Bg` page / `S1`+`Bd` surfaces / `Inv` nav bar) is otherwise unchanged from Phase 3.
- **The sentinel override is intact:** a `Not available` value is forced back to `Mu` regardless of the key it is handed, in both `Add-Row` (`Akari.ps1:601`) and `Add-Headline` (`Akari.ps1:576`), so a failed read can never render a coloured placeholder.

**Findings:**

- **W-3.1 (WARNING)** — **Priority fix 2.** The 0.6 refresh dim destroys the health signal's contrast. `Update-Home` sets `$Cards.Opacity = 0.6` and `$HostSub.Opacity = 0.6` (`Akari.ps1:756-757`); `Set-HomeDim` repeats it (`Akari.ps1:857-858`). Blending over the `S1` `#141414` card at 0.6 opacity gives, on the sRGB blend WPF performs: `Bad` `#E5645A` → ≈ **2.7:1**, `Warn` `#D9A441` → ≈ **3.7:1**, both below the 4.5:1 WCAG AA threshold the 03-UI-SPEC itself cites for the dimmed `Tx` values (≈6.5:1). Before this phase the dim lasted ≈1.5 s (a normal read); the new 20 s watchdog deadline means the failing-contrast state can now persist for twenty seconds. The two coloured values are precisely the ones the user is meant to read while waiting. Fix as described in the priority fix.
- **W-3.2 (WARNING)** — The health thresholds are computed from a single point-in-time snapshot and never re-evaluated between reads. RAM `Used` is captured at read start (`Akari.ps1:187-195`); if the user opens applications while Home sits open, the amber/red state can under-report current pressure for as long as Home is not re-shown. This is the documented "live on every Home show" model (SHELL/REFR-01), so it is contract-consistent — flagged only because SPEC-08's promise ("see at a glance when memory runs low") is bounded by navigation, not by elapsed time. A cheap improvement: re-read when the window regains activation (`Window.Activated`), one line beside the existing `$CopySpecs.Add_Click` wiring.

### Pillar 4: Typography (3/4)

**What holds:**

- On the Home panel itself, the 03-UI-SPEC's 4-size set is intact: 22 (`HostName`), 15 (card headlines, `Akari.ps1:573`), 13 (values, `HostSub`, `Loading…`), 12 (card titles, field labels).
- **Weights are exactly two on Home:** SemiBold and Regular. Grep shows `FontWeight` SemiBold ×4 in XAML (Akari wordmark, `HostName`, `Heading`) and ×2 in code (title, headline); `Medium` appears only in the pre-existing `Tuner`/`SvcTuner` headings (`MainWindow.xaml:226, 276`), which the 03-UI-SPEC explicitly excludes from Home.
- No `LineHeight` is set anywhere on Home, so the WPF default (~1.33) applies as the contract requires.
- The new `Sockets` label (7 characters at 12px ≈ 45 px) fits comfortably in the fixed 72 px label column (`Akari.ps1:588-593`), so the WR-03 change did not perturb the row layout.

**Findings:**

- **W-4.1 (WARNING)** — Home now renders **five** font sizes: 12, 12.5, 13, 15, 22. The fifth is the `CopySpecs` label at 12.5, inherited from the `Btn` style (`MainWindow.xaml:25`). The 03-UI-SPEC states plainly "Home uses exactly 4 sizes and 2 weights", and its Spacing Scale section whitelists the same `Btn` values (padding `12,5`) as chrome exceptions — but no equivalent exception was recorded for typography when D-01 mandated reusing `Btn`. The value itself is correct and consistent with every other button in the app; the finding is that the contract table was not amended. Fix: add a one-line exception to the Home typography table ("`Btn`-styled controls render at the app-standard 12.5") rather than changing the button.
- **N-4.2 (nit)** — The monospace log drawer font (`Cascadia Mono, Consolas`, `MainWindow.xaml:301`) is outside Home scope and unchanged; noted only to confirm it was not caught up in this phase's audit.

### Pillar 5: Spacing (4/4)

**Audit method applied to WPF:** every `Thickness`/`Margin`/`Padding` literal in the Home render path and `HomeHeader` was extracted and compared against the declared scale (xs 4 / sm 8 / md 12 / lg 16, label column 72, card width 240).

| Element | Value | Line | Declared token |
|---|---|---|---|
| Card padding | `16,12,16,12` | `Akari.ps1:548` | lg / md ✓ |
| Card margin (gap) | `0,0,8,8` | `Akari.ps1:549` | sm ✓ |
| Card corner radius | `5` | `Akari.ps1:547` | radius, matches panels ✓ |
| Title → headline gap | `0,0,0,4` | `Akari.ps1:556` | xs ✓ |
| Headline → first row | `0,0,0,8` | `Akari.ps1:578` | sm ✓ |
| Row → next row | `0,4,0,0` (first row `0`) | `Akari.ps1:587` | xs ✓ |
| Item divider | `0,12,0,12` | `Akari.ps1:612` | md ✓ |
| Label column width | `72` | `Akari.ps1:588` | 72 px ✓ |
| Card width | `240` | `Akari.ps1:543` | 240 px ✓ |
| Header → card grid | `0,0,0,16` | `MainWindow.xaml:210` | lg ✓ |
| HostName → HostSub | `0,4,0,0` | `MainWindow.xaml:216` | xs ✓ |

**Findings:**

- **Zero arbitrary values.** No `[Npx]`/`[Nrem]`-style magic numbers exist in WPF spacing, and no literal in the Home path falls off the 4-px grid. Grep for `Thickness]::new` in `Akari.ps1` returns exactly the ten values above plus the sidebar divider `8,8,8,8` (`Akari.ps1:973`, Phase 3, sm ✓).
- The new button's own `Padding 12,5` and `Margin 6,0,0,0` are pre-existing chrome values that the 03-UI-SPEC's Spacing Scale exception list already whitelists verbatim ("existing chrome outside Home keeps its current non-4 values … Btn padding `12,5`"). No new spacing issue introduced by this phase. Score 4 with no open findings.

### Pillar 6: Experience Design (3/4)

**What holds (code-derived):**

- **Loading:** first show renders six cards with `Loading…` (real U+2026, `Akari.ps1:564`) in `Mu` and `HostSub` collapsed (`Akari.ps1:760-769`).
- **Empty / partial / failed:** zero-item GPU and Disk blocks render a headline-only `Not available` card (`Akari.ps1:680, 710`); per-field sentinels render in `Mu` with no unit (`Fmt-Num`, `Akari.ps1:535-539`); a failed read installs the `New-FailedSpecs` composite plus one log line and undims (`Akari.ps1:895-901`). A card can never stay on `Loading…` after a read ends — that Phase 3 WR-01 defect is closed by this phase.
- **Disabled states:** `CopySpecs` disabled until the first read completes (`Akari.ps1:759`); the `Default` row button is disabled with a reason tooltip when a tweak has no safe revert (`Akari.ps1:427`, pre-existing).
- **Destructive confirmation:** unchanged `Confirm-Run` path (`Akari.ps1:929-932`) gating any tweak with a `-Confirm` string.
- **Resilience added by this phase:** the 20 s watchdog uses only non-blocking `BeginStop` and parks the job for later disposal (`Akari.ps1:871-880, 903-910`); every spec-read `Get-CimInstance` carries `-OperationTimeoutSec 10` (`Akari.ps1:159, 187, 210, 236, 314, 348, 355, 379`); the clipboard call is wrapped so a held clipboard cannot reach the host `trap` (`Akari.ps1:825-831`).
- **Concurrency:** copying touches no busy guard, starts no read and writes no log line, and copies the last values while a refresh is in flight — D-04/D-05/D-07 all hold in code.

**Findings:**

- **W-6.1 (WARNING)** — **Priority fix 3.** The 20-second silent window. The watchdog is verified (04-03-SUMMARY: 16/16 automated commands, including an uninterruptible hung-pipeline harness), but between the deadline being set and being reached the user receives nothing: the grid sits at 0.6, no text changes, no log line is written until `Akari.ps1:899` fires at the 20 s mark. On a machine with a genuinely stuck WMI provider this is 20 s of "Home looks frozen", which is the same user-visible symptom WR-01 was filed for. The plan recorded this as a flagged assumption (20 s ≈ 10× a normal 1.1-1.7 s read); the auditor position is that the assumption holds for the *timeout* but not for the *feedback*. Fix as described in the priority fix.
- **W-6.2 (WARNING)** — No recovery affordance on `Copy failed`. The label reverts to `Copy specs` after 2 s whether the copy succeeded or failed, so the failure state is transient, unexplained, and offers no retry hint (see W-1.2). A user whose clipboard is held by a remote-desktop or clipboard-manager process sees a flicker and no reason.
- **W-6.3 (WARNING)** — No keyboard or automation route to the Home page's only control. Grep for `AutomationProperties`, access keys, accelerators and `IsTabStop` across `Akari.ps1` and `MainWindow.xaml` returns only the three pre-existing `ToolTip` attributes. The `CopySpecs` button is tab-reachable (default WPF), but has no `AutomationProperties.Name` (its name comes from content, which changes to "Copied"/"Copy failed" — a screen reader would announce the transient state) and no access key. Pre-existing app-wide a11y gap, newly material because Phase 4 introduces Home's first interactive element. Low-cost fix: `AutomationProperties.Name="Copy specs"` and `AutomationProperties.HelpText="Copy all specs as text"` on `MainWindow.xaml:212`.

---

## Minor Recommendations

1. **`Get-HostLine` comment contradicts its own output** — `Akari.ps1:733` reads "`'Maker - Model' joined by a middle dot`"; the code emits `Maker · Model` (`Akari.ps1:745`). The AGENTS.md convention is that a one-line comment names the intent; this one invites a future reader to "fix" correct code.
2. **Amend the design contract, not just the code** — the 03-UI-SPEC typography table (4 sizes) and its Copywriting Contract (`Primary CTA: None in Phase 3`) are both now stale by one row. A short addendum row for the `Btn`-styled `Copy specs` control (12.5 px, label `Copy specs`, feedback `Copied`/`Copy failed`) keeps the contract auditable for the next phase.
3. **Drop or use `Add-Headline`'s `$brushKey`** — `Akari.ps1:570`; no caller passes it (D-10 makes health colouring row-only). Keeping an unused knob is how D-10 gets broken later.
4. **Tag health rows** — set `Tag='Health'` on the two `Add-Row` Grids that carry a non-`Tx` key (see priority fix 2), which also makes the "exactly 2 coloured TextBlocks" plan assertion expressible in code rather than only in a harness.
5. **Consider a log line for a swallowed non-clipboard exception** — `Copy-Specs` catches everything (`Akari.ps1:828`), so a shape change in `$script:SpecData` would surface to the user as "Copy failed" with nothing anywhere to diagnose. D-04 forbids log noise on the normal path; a narrow `catch` that only treats `COMException`/clipboard-open errors as a user-facing failure would keep both.

---

## Files Audited

| File | Lines | Scope |
|------|-------|-------|
| `UI/MainWindow.xaml` | 306 (whole file) | Ink token block, `Btn`/`Nav`/`Chip`/`Flat` styles, `HomeHeader` + `CopySpecs`, Tuner panels, log drawer |
| `Akari.ps1` | 1020 (Home/copy/watchdog regions in full; spec-read and host-identity here-strings, `New-Card`/`Add-Loading`/`Add-Headline`/`Add-Row`/`Add-Divider`, `Get-DiskHealth`/`Get-RamHealth`/`Get-HomeModel`/`Get-HostLine`/`Update-Home`/`Get-SpecText`/`Copy-Specs`, `Start-SpecRead`, the 150 ms tick, click wiring) | Full Home render path, copy path, watchdog, CIM timeouts, multi-socket CPU block |
| `README.md` | 50 (whole file) | Section order, Copy specs/threshold accuracy, 8 category lines, IWR verbatim, Credits verbatim, no images, ≤80-line budget |
| `.planning/phases/04-home-polish-documentation/04-CONTEXT.md` | 122 | D-01…D-18 conformance basis |
| `.planning/phases/03-home-shell-live-refresh/03-UI-SPEC.md` | 295 | Design contract: tokens, spacing scale, typography, colour split, copywriting |
| `.planning/phases/04-home-polish-documentation/04-01/02/03-PLAN.md` + `-SUMMARY.md` | — | Intent vs. built |

**Convention conformance (AGENTS.md):** `Akari.ps1` is pure ASCII (0 non-ASCII bytes, verified) with all special characters built from `[char]` code points; `x:Key` count unchanged at 15; new functions are `Verb-Noun` (`Get-HomeModel`, `Get-HostLine`, `Get-SpecText`, `Copy-Specs`, `Get-DiskHealth`, `Get-RamHealth`) with lowercase one-line intent comments above each block; no new dependency, no `$ErrorActionPreference = 'Stop'`, no `Set-StrictMode`; braces balance at 468/468.

---

*Reviewed: 2026-10-09 · Auditor: gsd-ui-auditor (6-pillar, code-only — no dev server, no interaction capture)*
