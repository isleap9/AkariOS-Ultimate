---
phase: 03
review: 03-REVIEW.md
titles: json
findings:
  - id: WR-01
    severity: warning
    disposition: open
    title: "A stuck spec read freezes Home for the whole session (no timeout, no recovery)"
  - id: WR-02
    severity: warning
    disposition: open
    title: "Dormant `-ResultVar` harvest overwrites `$script:SpecData` with the old shape"
  - id: WR-03
    severity: warning
    disposition: open
    title: "CPU card under-reports cores and threads on multi-socket machines"
  - id: IN-01
    severity: info
    disposition: open
    title: "Showing Home while a read is in flight does not start a fresh read"
  - id: IN-02
    severity: info
    disposition: open
    title: "A leftover `SpecPending` starts a read after the user has left Home"
  - id: IN-03
    severity: info
    disposition: open
    title: "\"Showing last known values\" can refer to the failed skeleton"
  - id: IN-04
    severity: info
    disposition: open
    title: "Disk card loop and divider are now dead code"
  - id: IN-05
    severity: info
    disposition: open
    title: "System drive on removable media shows \"Not available\""
  - id: IN-06
    severity: info
    disposition: open
    title: "Spec runspace is not cleaned up on error or on window close"
  - id: IN-07
    severity: info
    disposition: open
    title: "Header host name is the 15-character NetBIOS name"
---

# Phase 3: Code Review Disposition

Review 03-REVIEW.md: 0 critical, 3 warning, 7 info. Every finding starts as `open`. Run `/gsd-code-review 03 --fix` to address them, or record a deferral here.

| ID | Severity | Disposition | Note |
|----|----------|-------------|------|
| WR-01 | warning | open | |
| WR-02 | warning | open | Same root cause as Phase 2 WR-06 (carried forward) |
| WR-03 | warning | open | Pre-existing in Get-Specs; first surfaced to users here |
| IN-01 | info | open | |
| IN-02 | info | open | |
| IN-03 | info | open | |
| IN-04 | info | open | Follows from the user-requested system-drive-only change (ac5bff8) |
| IN-05 | info | open | |
| IN-06 | info | open | |
| IN-07 | info | open | |
