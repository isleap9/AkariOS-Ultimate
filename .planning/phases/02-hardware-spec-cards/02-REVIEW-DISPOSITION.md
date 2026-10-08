---
phase: 02
review: 02-REVIEW.md
titles: json
findings:
  - id: CR-01
    severity: critical
    disposition: open
    title: "BIOS release date is off by one day for users west of UTC (and wrong calendar in non-Gregorian cultures)"
  - id: WR-01
    severity: warning
    disposition: open
    title: "A full disk reports free space as \"Not available\" and is counted as a failed read"
  - id: WR-02
    severity: warning
    disposition: open
    title: "Disk `_Status` is `Partial` on almost every machine because an empty volume label is treated as a failed field"
  - id: WR-03
    severity: warning
    disposition: open
    title: "The index-based VRAM fallback can silently report another (or a removed) adapter's VRAM as fact"
  - id: WR-04
    severity: warning
    disposition: open
    title: "The authoritative 64-bit VRAM value is ignored whenever AdapterRAM is not a known sentinel"
  - id: WR-05
    severity: warning
    disposition: open
    title: "Virtual and basic display adapters are listed as GPUs and force GPU `_Status` to `Partial`"
  - id: WR-06
    severity: warning
    disposition: open
    title: "`-ResultVar` is accepted but ignored; results are always written to `$script:SpecData`"
  - id: WR-07
    severity: warning
    disposition: open
    title: "Spec refreshes are silently dropped while busy, and finished result jobs run Show-Page and a synchronous CIM query on the UI thread"
  - id: WR-08
    severity: warning
    disposition: open
    title: "A `BeginInvoke` failure leaves the app permanently busy and leaks the runspace"
  - id: IN-01
    severity: info
    disposition: open
    title: "Redundant and unreachable conditions in the capped-VRAM check"
  - id: IN-02
    severity: info
    disposition: open
    title: "SMBIOS filler list is incomplete, and matching is case-insensitive despite documented intent"
  - id: IN-03
    severity: info
    disposition: open
    title: "`$script:SpecData` is not type-checked; any stray output object becomes the spec data"
open: 12
total: 12
recorded: 2026-10-08T14:17:35.292Z
---

# Phase 02: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| CR-01 | critical | open | - |
| WR-01 | warning | open | - |
| WR-02 | warning | open | - |
| WR-03 | warning | open | - |
| WR-04 | warning | open | - |
| WR-05 | warning | open | - |
| WR-06 | warning | open | - |
| WR-07 | warning | open | - |
| WR-08 | warning | open | - |
| IN-01 | info | open | - |
| IN-02 | info | open | - |
| IN-03 | info | open | - |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.
Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.
Re-running the gate keeps every row it can. A row the current review no longer reports is kept and its Source cell flagged, so a finding does not leave this record silently. ONE exception: when a finding id is REUSED by a different finding, the earlier decision cannot keep a row — the id is taken — and it is dropped. A RECORDED decision (anything but `open`) is named on the console when that happens; a row still at `open` is replaced silently, because `open` records no decision to lose.
