---
phase: "02"
slug: "hardware-spec-cards"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-08"
---

# Phase 02 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Firmware/OS (CIM/WMI providers) to Get-Specs | OEM-controlled SMBIOS data and volume metadata enter the app; untrusted for accuracy and format | Hardware strings, dates, sizes (non-sensitive, local) |
| Get-Specs runspace to `$script:SpecData` (UI thread) | Result hashtable crosses via Invoke-Code ResultVar and the DispatcherTimer tick | Spec hashtable (non-sensitive) |
| Verify harness to host machine | Harness temporarily overrides timezone/culture in-process | None persisted |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T1 | Denial of Service | GPU VRAM registry fallback | low | mitigate | `-ErrorAction SilentlyContinue`; VRAM stays 'Not available' | closed |
| T2 | Tampering (data integrity) | Registry subkey ↔ WMI instance match | low | mitigate | MatchingDeviceId prefix match first, index fallback (02-SUMMARY key-decisions) | closed |
| T3 | Denial of Service | Win32_VideoController 0 instances | low | mitigate | `_Status = 'Failed'`, empty Adapters | closed |
| T4 | Denial of Service | Win32_LogicalDisk 0 fixed drives | low | mitigate | `_Status = 'Failed'`, empty Volumes | closed |
| T5 | Tampering (data integrity) | FreeSpace null on not-ready drives | low | mitigate | Null-only guard, `Akari.ps1:314` | closed |
| T6 | Tampering (data integrity) | SMBIOS filler strings | low | mitigate | Test-SmbiosValue filler filter | closed |
| T7 | Denial of Service | ReleaseDate null | low | mitigate | `if ($bios.ReleaseDate)` guard, `Akari.ps1:345` | closed |
| T8 | Tampering (data integrity) | Test-SmbiosValue false positives | low | accept | Filler list specific; see Accepted Risks | closed |
| T9 | — (design note) | GPU/Disk array structure | low | accept | Design decision, not a threat | closed |
| T10 | Tampering | `$script:SpecData` thread safety | low | mitigate | Set and read only on UI thread | closed |
| T-02-11 | Tampering (data integrity) | Motherboard.ReleaseDate | medium | mitigate | `ToUniversalTime()` + InvariantCulture, `Akari.ps1:345`; zone/culture matrix PASS | closed |
| T-02-12 | Tampering (data integrity) | Disk FreeGB and _Status | low | mitigate | Null-only FreeSpace guard (`Akari.ps1:314`); Label excluded from counted fields | closed |
| T-02-13 | Denial of Service | BIOS block exception path | low | accept | Existing empty catch leaves 'Not available' | closed |
| T-02-14 | Tampering (host configuration) | Verify harnesses | low | mitigate | In-process TimeZoneInfo/culture only; no `Set-TimeZone`/`tzutil` in `Akari.ps1` (grep 0) | closed |
| T-02-15 | Information Disclosure | Spec values | low | accept | Local display only; no network/logging/persistence | closed |
| T-02-SC | Tampering | Package installs | low | accept | No packages installed | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-01 | T8 | Unknown OEM fillers may pass through; preferable to blanking legitimate values | plan (02-PLAN.md) | 2026-10-08 |
| AR-02 | T9 | Structural design note, no security impact | plan (02-PLAN.md) | 2026-10-08 |
| AR-03 | T-02-13 | Existing suppress-and-continue catch covers unexpected exceptions | plan (02-02-PLAN.md) | 2026-10-08 |
| AR-04 | T-02-15 | Local-only display of non-sensitive hardware info | plan (02-02-PLAN.md) | 2026-10-08 |
| AR-05 | T-02-SC | No package installs in this phase | plan (02-02-PLAN.md) | 2026-10-08 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-08 | 16 | 16 | 0 | /gsd-secure-phase (ASVS L1 short-circuit, plan-time register) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-08
