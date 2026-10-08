---
phase: "03"
slug: "home-shell-live-refresh"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-08"
---

# Phase 03 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Host to WMI/CIM | The spec read pulls machine state through CIM and the registry. The values can only be influenced by an attacker who has already compromised the host | Hardware strings, sizes, versions (non-sensitive, local) |
| Background runspace to UI thread | Read results cross only inside the 150 ms DispatcherTimer tick, which moves data, never visuals | `@{ Specs; Host }` composite (non-sensitive) |
| Spec value to WPF visual / header text | Spec strings become visible text. A malformed or compromised SMBIOS can supply the header identity | Display strings |
| Read state to visual state | The dim, loading and failed transitions follow the read state. A wrong transition would hide staleness from the user | None persisted |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-03-01 | Tampering | Card renderer (`New-Card`, `Add-Headline`, `Add-Row`) | medium | mitigate | Cards are built from .NET objects with `.Text` assignment, and the Home path has no XamlReader call. The only XamlReader uses are the static window (`Akari.ps1:383`) and the pre-existing tweak-row `New-Row` (`:452`) | closed |
| T-03-02 | Denial of service | `Start-SpecRead` and the tick spec-completion block | medium | mitigate | One-flight guard `if ($script:SpecJob) { return }` (`Akari.ps1:739`). Completion ends in `Update-Home`, never `Show-Page` (03-01 verify #3 AST check: PASS) | closed |
| T-03-03 | Denial of service | Home render path and the tick | medium | mitigate | All CIM work runs in a separate runspace. `Start-SpecRead` never calls `Set-Busy`, never assigns `$script:Busy`, and never disables `Page` (`:741` only reads Busy to defer). The verifier harness confirmed Page.IsEnabled stays true | closed |
| T-03-04 | Information disclosure | Spec-read result handling in the tick | medium | mitigate | The tick accepts only a hashtable with a `Specs` key, stores the composite on a failed first read (`:788`) and clears `SpecJob` on both paths (03-01 verify #3: PASS) | closed |
| T-03-05 | Elevation of privilege | Host process (`Akari.ps1`) | low | accept | No new `Start-Process`, `RunAs` or TrustedInstaller path in the phase diff (grep of the added lines since 2394fc1 found none) | closed |
| T-03-06 | Denial of service | Tick failure branch and `New-FailedSpecs` | medium | mitigate | A read that throws, returns nothing or a string, or dies resolves to a terminal state: either last values at restored opacity or the composite failed skeleton (`:612`, `:788`), plus exactly one `Specs: Read failed` drawer line (`:790`). 03-02 verify #2: PASS. Residual: a read that never returns (WMI hang) has no timeout. See review finding WR-01 | closed |
| T-03-07 | Spoofing | Header identity resolution in `Update-Home` | low | mitigate | Reuses the single `Test-SmbiosValue` filler list (`:106`, used at `:369-370`) and the pair-level D-17 fallback (03-02 verify #3: PASS, four cases) | closed |
| T-03-08 | Denial of service | `$script:SpecPending` and the tweak-completion drain | low | mitigate | The flag is set while a tweak runs (`:741`), cleared on start (`:752`), and drained exactly once after the tweak completes (`:814`). The verifier harness confirmed exactly one deferred read with no second one queued | closed |
| T-03-09 | Information disclosure | `Get-HostIdentity` and the header line | low | mitigate | Only Manufacturer and Model are read from `Win32_ComputerSystem` (`:367-370`). No serial, UUID or asset tag is read or displayed (`'System Serial Number'` at `:120` is a filler-rejection string, not a read) | closed |
| T-03-SC | Tampering | Package installation surface | high | accept | Zero packages installed. Only inbox PowerShell 5.1 and WPF/.NET Framework assemblies are used (03-RESEARCH.md package audit) | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-03-01 | T-03-05 | The phase adds no privileged operation; the existing whole-process elevation model is unchanged | Plan 03-01 threat model | 2026-10-08 |
| AR-03-02 | T-03-SC | No package installs; the supply-chain surface is unchanged | Plans 03-01 and 03-02 threat model | 2026-10-08 |

*Accepted risks do not resurface in future audit runs.*

### Residual Notes (non-blocking, tracked elsewhere)

- **WR-01 (03-REVIEW.md):** the spec read has no CIM timeout and no watchdog. A hung WMI provider leaves Home dimmed or on Loading… for the session, with no log line. This is availability-only and local, so it does not count as an open threat at the `high` block threshold. It stays `open` in 03-REVIEW-DISPOSITION.md.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-08 | 10 | 10 | 0 | /gsd-secure-phase orchestrator (L1 grep depth; auditor skipped per short-circuit: threats_open 0, plan-time register, ASVS 1) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-08
