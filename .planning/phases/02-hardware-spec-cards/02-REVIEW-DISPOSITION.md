| WR-02 |  | fixed | 02-02 c55c7a0 (harness PASS) || WR-01 |  | fixed | 02-02 cd79bf5 (harness PASS) || CR-01 |  | fixed | 02-02 fbb2bc1 (harness PASS) |---
phase: 02
review: 02-REVIEW.md
titles: json
findings:
  - id: WR-03
    severity: warning
    disposition: open
    title: "The index-based VRAM fallback can silently report another (or a removed) adapter's VRAM as fact (carried forward, deferred)"
  - id: WR-04
    severity: warning
    disposition: open
    title: "The authoritative 64-bit VRAM value is ignored whenever AdapterRAM is not a known sentinel (carried forward, deferred)"
  - id: WR-05
    severity: warning
    disposition: open
    title: "Virtual and basic display adapters are listed as GPUs and force GPU `_Status` to `Partial` (carried forward, deferred)"
  - id: WR-06
    severity: warning
    disposition: open
    title: "`-ResultVar` is accepted but ignored; results are always written to `$script:SpecData` (carried forward, deferred to Phase 3)"
  - id: WR-07
    severity: warning
    disposition: open
    title: "Spec refreshes are silently dropped while busy, and finished result jobs run Show-Page and a synchronous CIM query on the UI thread (carried forward, deferred to Phase 3)"
  - id: WR-08
    severity: warning
    disposition: open
    title: "A `BeginInvoke` failure leaves the app permanently busy and leaks the runspace (carried forward, deferred to Phase 3)"
  - id: WR-09
    severity: warning
    disposition: open
    title: "Windows `_Status` can report `OK` when the Edition read failed, because Build is counted twice (new, pre-existing Phase 1 code)"
  - id: IN-01
    severity: info
    disposition: open
    title: "Redundant and unreachable conditions in the capped-VRAM check (carried forward, deferred)"
  - id: IN-02
    severity: info
    disposition: open
    title: "SMBIOS filler list is incomplete, and matching is case-insensitive despite documented intent (carried forward, deferred)"
  - id: IN-03
    severity: info
    disposition: open
    title: "`$script:SpecData` is not type-checked; any stray output object becomes the spec data (carried forward, deferred to Phase 3)"
  - id: IN-04
    severity: info
    disposition: open
    title: "CPU \"Cores\" silently falls back to the logical-processor count (new, pre-existing Phase 1 code)"
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
open: 11
total: 14
recorded: 2026-10-08T14:57:46.468Z
---

# Phase 02: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| WR-03 | warning | open | - |
| WR-04 | warning | open | - |
| WR-05 | warning | open | - |
| WR-06 | warning | open | - |
| WR-07 | warning | open | - |
| WR-08 | warning | open | - |
| WR-09 | warning | open | - |
| IN-01 | info | open | - |
| IN-02 | info | open | - |
| IN-03 | info | open | - |
| IN-04 | info | open | - |
| CR-01 | critical | open | - (not in the current review) |
| WR-01 | warning | open | - (not in the current review) |
| WR-02 | warning | open | - (not in the current review) |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.
Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.
Re-running the gate keeps every row it can. A row the current review no longer reports is kept and its Source cell flagged, so a finding does not leave this record silently. ONE exception: when a finding id is REUSED by a different finding, the earlier decision cannot keep a row — the id is taken — and it is dropped. A RECORDED decision (anything but `open`) is named on the console when that happens; a row still at `open` is replaced silently, because `open` records no decision to lose.
