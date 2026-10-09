# Phase 4: Home Polish & Documentation - Context

**Gathered:** 2026-10-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Finish the Home page: a Copy button that puts the full spec text on the clipboard (SPEC-07), amber/red health colouring for system-drive free space and RAM use (SPEC-08), a concise README rewrite documenting the project and the Home page (DOC-01), and closing the three open Phase 3 review findings (WR-01, WR-02, WR-03) so Home ships without known defects.

</domain>

<decisions>
## Implementation Decisions

### Copy Button & Text (SPEC-07)
- **D-01:** Copy button sits on the **right side of the Home header** (`HomeHeader` DockPanel, space reserved for it in `UI/MainWindow.xaml`). Uses the existing `Btn` style.
- **D-02:** Copied text is a **plain spec sheet**: computer name line, maker · model line (same resolved value as `HostSub`, omitted when collapsed), blank line, then per card a `Group: headline` line followed by indented `  Label: value` lines, in card order CPU, GPU, RAM, Disk, Board, Windows. Values formatted exactly as the cards show them (same `Fmt-Num` output, same "Not available").
- **D-03:** Disk section includes the **system drive only** — matches the card.
- **D-04:** Feedback: button label changes to **"Copied"** for ~2 seconds, then reverts. No log drawer line.
- **D-05:** Copying while a refresh is in flight copies the **last values** (what the cards show). The button is disabled only while no data exists yet (first load).
- **D-06:** Computer name **is included** in the copied text.
- **D-07:** Copy must not use `Invoke-Code -ResultVar`; build the text on the UI thread from `$script:SpecData` already in hand (no new query).

### Health Colours (SPEC-08)
- **D-08:** Disk (system drive) free space: **amber (`Warn`) below 15% free, red (`Bad`) below 10% free**.
- **D-09:** RAM used: **amber above 80% used, red above 90% used**.
- **D-10:** Only the **value text** changes colour (Disk card `Free` value, RAM card `Used` value). No percentage added, no border change.
- **D-11:** Healthy values stay **neutral `Tx`** — no green, no new theme brush.
- **D-12:** If the needed numbers are "Not available" / failed, no colouring.

### README (DOC-01)
- **D-13:** **Full but concise** rewrite (~one screen): what AkariOS-Ultimate is, Home page (live specs, copy button, health colours), the 8 tweak categories one line each, how Apply/Revert works, requirements, IWR one-liner install, running from a downloaded zip (`AllowScripts.cmd` then `Akari.ps1`), safety note (Administrator, reboot, risk labels).
- **D-14:** **No screenshots.**
- **D-15:** Credits section kept **verbatim** (rebrand of FR33THY's Ultimate, MIT).

### Phase 3 Leftovers (user: "lets just finish the work")
- **D-16:** Fix **WR-01**: spec read must not leave Home dimmed forever — add CIM operation timeouts and/or a watchdog in the tick that abandons a read after a fixed time, clears the in-flight state, and shows "Not available" / last values undimmed.
- **D-17:** Fix **WR-02**: remove or correct the dormant `Invoke-Code -ResultVar` harvest so it can never overwrite `$script:SpecData` with the wrong shape.
- **D-18:** Fix **WR-03**: CPU card sums cores/threads across all `Win32_Processor` sockets (show socket count when > 1). Note `Get-Specs` was "byte-for-byte unchanged" in Phase 3 (03 D-18); changing the CPU group is now allowed, but keep the six-group contract (`CPU,Disk,GPU,Motherboard,RAM,Windows`).

### Claude's Discretion
- Exact copy button label ("Copy specs" or similar), size and placement details within the header.
- Watchdog timeout value for WR-01 (fast enough to not feel stuck; long enough for slow WMI on cold boot).
- README wording and section order within D-13.
- Minor visual polish of Home (spacing/alignment) if needed while integrating the button — user said the UI was never fully polished, but gave no specific complaints; do not redesign.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & scope
- `.planning/REQUIREMENTS.md` — SPEC-07, SPEC-08, DOC-01 definitions; Out of Scope table
- `.planning/ROADMAP.md` §Phase 4 — success criteria

### Prior Home decisions
- `.planning/phases/03-home-shell-live-refresh/03-CONTEXT.md` — card order, layout, loading/dim behaviour, header fallback (D-01..D-18)
- `.planning/phases/03-home-shell-live-refresh/03-UI-SPEC.md` — Home visual contract (sizes, tokens)
- `.planning/phases/03-home-shell-live-refresh/03-REVIEW.md` — WR-01, WR-02, WR-03 findings with suggested fixes
- `.planning/phases/03-home-shell-live-refresh/03-REVIEW-DISPOSITION.md` — open status of those findings

### Project docs
- `README.md` — current README to rewrite (keep Credits verbatim)
- `AGENTS.md` — conventions (naming, comments, error handling, no new dependencies)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Update-Home`, `New-Card`, `Add-Row`, `Add-Headline`, `Fmt-Num` in `Akari.ps1` (~lines 532-730): card rendering; copy text should reuse the same formatting so it matches the cards.
- `$script:SpecData` = `@{ Specs; Host }` composite; header maker/model resolution already in `Update-Home`.
- Theme brushes `Warn` (#D9A441) and `Bad` (#E5645A) in `UI/MainWindow.xaml`; already used for risk labels (`$riskKey` in `New-Row`).
- `[Windows.Clipboard]::SetText` available inbox (WPF, STA thread).

### Established Patterns
- Spec read runs in a second runspace (`Start-SpecRead`, `$script:SpecJob`), harvested in the 150 ms `DispatcherTimer` tick before the tweak block.
- Dimming via `$Cards.Opacity` / `$HostSub.Opacity` while `$script:SpecJob` or `$script:SpecPending`.
- Lowercase one-line intent comments above blocks; `Verb-Noun` function names; no `$ErrorActionPreference = 'Stop'`.

### Integration Points
- `UI/MainWindow.xaml` `HomeHeader` DockPanel (right side) for the button; add its name to the `FindName` list in `Akari.ps1:384`.
- Tick handler (WR-01 watchdog, WR-02 harvest removal) and `Get-Specs` CPU block (WR-03).

</code_context>

<specifics>
## Specific Ideas

Copied text shape (user-approved preview):
```
DESKTOP-AKARI
ASUSTeK COMPUTER INC. · TUF GAMING B550-PLUS

CPU: AMD Ryzen 7 5800X
  Cores: 8 / 16 threads
  Speed: 3.80 GHz
GPU: NVIDIA GeForce RTX 5070
  VRAM: 11.9 GB
  Driver: 32.0.15.7680
RAM: 32.0 GB (Used 12.4 GB, Free 19.6 GB)
...
```

</specifics>

<deferred>
## Deferred Ideas

- Broader UI polish of the app (user mentioned the UI was never fully polished) — no specifics given; candidate for its own phase if the user lists concrete issues.
- Tweak progress bar under the log drawer (carried from Phase 3).

</deferred>

---

*Phase: 04-home-polish-documentation*
*Context gathered: 2026-10-09*
