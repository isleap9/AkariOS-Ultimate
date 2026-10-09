---
phase: "04-home-polish-documentation"
slug: "04-home-polish-documentation"
status: verified
threats_open: 0
asvs_level: 1
created: "2026-10-09"
---

# Phase 04 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Akari process → Windows clipboard | User-initiated: the spec sheet leaves the app and becomes readable by any program the user pastes into, or any program that reads the clipboard | Spec sheet text (computer name, Maker · Model, six card values) — low sensitivity, already on screen |
| Spec read value → copied text | Strings that a compromised or malformed SMBIOS/WMI can supply are written into text the user pastes elsewhere | WMI/SMBIOS strings → clipboard plain text |
| Live values → health colour | A colour is a judgement drawn from numbers; a wrong judgement misleads the user about the machine's state | Disk/RAM numbers → Warn/Bad brush key |
| README → user's elevated shell | The README tells users to paste a remote-code one-liner (`iwr … \| iex`) into an Administrator PowerShell window | Remote script URL → local admin execution |
| README → user's system policy | The README tells users to run AllowScripts.cmd, which relaxes the PowerShell execution policy machine-wide | Execution-policy change (Unrestricted on / Restricted off) |
| WMI/CIM provider → background runspace | A provider can hang, which is outside the app's control; the read must stay bounded | CIM query results → spec composite |
| Background runspace → UI thread | Read results and abandoned pipelines cross only inside the 150 ms tick | Spec composite, stale runspace handles |
| Tweak runspace → $script:SpecData | Before plan 04-03, any finished tweak job that carried a result variable could write the shared Home data | Tweak output (must NOT reach SpecData) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-04-01 | Information disclosure | `Copy-Specs` / `Get-SpecText` in `Akari.ps1` | low | mitigate | Copy happens only on explicit click (`$CopySpecs.Add_Click({ Copy-Specs })`). Text holds only what Home already shows: computer name, Maker · Model, six card values. No serial, UUID, product key, MAC/IP or user name is read or written. Local clipboard only via `[Windows.Clipboard]::SetText`; no network call, no file write in the four functions. | closed |
| T-04-02 | Tampering | Clipboard payload built by `Get-SpecText` | low | mitigate | Payload set with single-string `[Windows.Clipboard]::SetText((Get-SpecText))` — one Unicode text format, no HTML/RTF flavour. Hostile spec strings paste as inert text. | closed |
| T-04-03 | Denial of service | `Copy-Specs` when another program holds the clipboard | low | mitigate | Clipboard call wrapped in try/catch (`Akari.ps1:825-832`): failure shows `Copy failed` for ~2 s via `$script:CopiedUntil`, app keeps running, no exception escapes, no retry loop on UI thread. | closed |
| T-04-04 | Spoofing | `Get-DiskHealth` / `Get-RamHealth` health colours | low | mitigate | Colour only when both numbers are numeric and total > 0; string sentinel / null / zero-total returns `Tx` (`Akari.ps1:629-646`). Failed groups forced to `Tx` (`Akari.ps1:688,703`). Strict thresholds (Disk <10 Bad, <15 Warn; RAM >90 Bad, >80 Warn), multiply-first percentage. | closed |
| T-04-05 | Spoofing | IWR one-liner in `README.md` | medium | mitigate | Install line kept byte-identical (`iwr 'https://github.com/isleap9/AkariOS-Ultimate/raw/refs/heads/main/IWR.ps1' -useb \| iex`, `README.md:34`); no other download source is named; prohibitions forbid changing host/owner/branch/path. | closed |
| T-04-06 | Elevation of privilege | Run-from-zip and Safety sections in `README.md` | low | mitigate | README states Akari runs as Administrator, AllowScripts.cmd option 1 allows scripts and option 2 reverts to Restricted, reboot required, Advanced tweaks can lower security — informed consent before elevation. | closed |
| T-04-07 | Denial of service | Tick spec-completion block, `Start-SpecRead` in `Akari.ps1` | medium | mitigate | Each read stamped `Deadline = UtcNow + $script:SpecTimeoutSec (20)` (`Akari.ps1:849`). Past-deadline tick frees slot, calls only non-blocking `BeginStop`, parks in `$script:SpecStale`, redraws Home undimmed with one `Specs: Read failed (timed out after 20 seconds).` line (`Akari.ps1:869-901`). All 8 spec-read `Get-CimInstance` calls carry `-OperationTimeoutSec 10`. | closed |
| T-04-08 | Tampering | `Invoke-Code` and tick tweak-completion block | medium | mitigate | `Invoke-Code([string]$code, [string]$label, $meta = $null)` — result-variable path removed; no `ResultVar` string remains in `Akari.ps1`. Tweak-completion block is `EndInvoke` + drain only, touches neither output collection nor `$script:SpecData` (`Akari.ps1:911-913`). Spec-completion block accepts only hashtables with a `Specs` key. | closed |
| T-04-09 | Tampering | CPU group in `Get-Specs` (displayed/copied data integrity) | low | mitigate | Cores/threads summed across every `Win32_Processor` via `Measure-Object -Sum`; model/clock from first socket; `CPU.Sockets` written and shown as a `Sockets` row/line only when numeric and > 1 (`Akari.ps1:159-176,664`). Failed CPU carries `Sockets = Not available`. | closed |
| T-04-10 | Denial of service | `$script:SpecStale` (abandoned runspaces) | low | accept | A pipeline stuck in native code may never end; its runspace stays in `$script:SpecStale` until close — at most one runspace per 20 s timeout. Keeps the UI thread non-blocking; bounded, accepted. See Accepted Risks Log. | closed |
| T-04-SC | Tampering | Package installation surface | high | accept | Phase installs nothing: Windows PowerShell 5.1 + inbox WPF/.NET/CimCmdlets only. No npm/pip/cargo install exists; package-legitimacy audit has zero rows. See Accepted Risks Log. | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-04-01 | T-04-10 | A pipeline stuck in native code may never end; its runspace leaks (one per 20 s timeout) rather than blocking the UI. Bounded cost, no crash path; disposal loop frees every pipeline that does end. | Phase 4 plan 04-03 (D-16 flagged assumption) | 2026-10-09 |
| R-04-02 | T-04-SC | No supply-chain surface: zero third-party packages installed by any plan in this phase; inbox assemblies only. Nothing to audit, nothing to pin. | Phase 4 plans 04-01/04-02/04-03 | 2026-10-09 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-09 | 11 | 11 | 0 | secure-phase (State B, L1 grep-depth, ASVS 1) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-09
