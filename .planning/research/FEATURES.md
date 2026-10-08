# Feature Research: Home System-Info Dashboard

**Domain:** System-info Home/dashboard page in a Windows tweaking utility
**Researched:** 2026-10-08
**Confidence:** HIGH (competitor patterns stable and well-documented; Speccy/msinfo32/Settings About conventions unchanged for years)

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = the page feels broken or untrustworthy.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| CPU card: model name, core/thread count, current speed | Every reference tool (Speccy summary, CPU-Z, Settings > About, msinfo32) leads with the CPU string; users cross-check it against what they know they bought | LOW | Single `Win32_Processor` CIM query (Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed). Normalize whitespace in Name — some vendors pad it. |
| RAM card: total installed + used/free | "How much RAM do I have" is the #2 spec question after CPU; totals alone feel incomplete — Speccy and Task Manager both show usage alongside total | LOW | `Win32_ComputerSystem.TotalPhysicalMemory` for total + `Win32_OperatingSystem.FreePhysicalMemory` for free. Compute used = total − free. Format in GB with 1 decimal. |
| GPU card: model name, VRAM, driver version | GPU is the #3 spec question, especially for gamers/tweakers; model-only without VRAM/driver feels thin vs GPU-Z/Speccy | LOW | `Win32_VideoController` (Name, AdapterRAM, DriverVersion). Multi-GPU (iGPU + dGPU) machines return multiple instances — show all rows, don't take just the first. AdapterRAM can be null on some drivers — fall back to "n/a". |
| Disk card: per-drive model/capacity + free space | Single "500 GB disk" line is distrusted when users have C: + D: + external; Speccy lists each physical drive, Settings lists each volume's usage | MEDIUM | Two queries to join: `Win32_DiskDrive` (model, size) + `Win32_LogicalDisk` (free/total per volume). Correlate via partition mapping or present volumes only — volumes (C:, D:) match user mental model better than `\\.\PHYSICALDRIVE0`. One card with N rows. |
| Motherboard + BIOS card: board model, BIOS version/date | Expected on any Speccy-class summary; critical for driver/BIOS-update troubleshooting, which is a tweaking tool's core job | LOW | `Win32_BaseBoard` (Product, Manufacturer) + `Win32_BIOS` (SMBIOSBIOSVersion, ReleaseDate — WMI datetime, needs conversion). On VMs/branded OEMs Product may be generic ("Virtual Machine") — show as-is, don't hide. |
| Windows card: edition + build (+ friendly version) | Users verify "am I on 11 Pro 23H2 / correct build" before applying tweaks; Settings > About and `winver` both anchor on edition + build | LOW | Registry `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion` (ProductName, DisplayVersion, CurrentBuildNumber, UBR). Compose "Windows 11 Pro · 23H2 (Build 22631.4169)". UBR (revision) matters — two machines on the same build with different UBR have different patch levels. |
| Default landing tab on launch | A "Home" page that isn't home on launch is a naming lie; every dashboard (Speccy summary, HWiNFO summary, Winhance landing) opens on its overview first | LOW | Nav-state default change (`$script:Cat` default → Home) + nav button ordering. Trivial code, high UX weight. |
| Live refresh every time Home is shown | Stale specs destroy trust (RAM used from 3 hours ago); PROJECT.md Core Value states accuracy-is-everything; users expect Task-Manager-fresh numbers | MEDIUM | Re-query on each page show, off the UI thread (existing `Invoke-Code` runspace pattern). Must add a loading/placeholder state so cards don't flash blank on slow WMI. |
| Graceful "unknown / n/a" fallbacks per field | Real machines have missing data (null AdapterRAM, generic VM board strings, unpopulated BIOS dates); blank cards or thrown errors read as broken | LOW | Per-field try/catch with "n/a" fallback, never fail the whole card or page on one bad query. This is table stakes *robustness*, not polish. |
| Read-only presentation (no edit affordances) | Users don't expect to *change* their CPU string from an overview; editable-looking fields invite fear of breaking the machine | LOW | Static text rows, no textboxes/toggles on Home cards. Enforced by omission. |

### Differentiators (Competitive Advantage)

Features that set the page apart. Not required, but valuable. Pick one or two — don't build all.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Copy-to-clipboard spec export | #1 support-forum workflow: "paste your specs" for troubleshooting; Speccy has File > Publish, forums beg for text dumps — one click turns the page into a help artifact | LOW | Compose plaintext summary from already-queried values, `Set-Clipboard`. Near-zero cost since data is already in hand. Highest value/effort ratio on this list. |
| Health-at-a-glance indicators (disk-free %, RAM pressure) | Transforms a static readout into an actionable overview: red/amber affordance on a nearly-full C: tells the user *what to care about* without reading numbers | LOW | Threshold coloring on already-queried numbers (e.g. <10% free = red, <20% = amber). Pure presentation logic, no new queries. |
| Friendly device/hostname header on System card | "DESKTOP-AB12CD · Dell XPS 15" personalizes the page and matches msinfo32's System Manufacturer/Model line; helps users with multiple machines confirm *which* PC they're tweaking | LOW | `Win32_ComputerSystem` (Name, Manufacturer, Model) — same query object already needed for RAM total, so free. |
| Expandable per-card detail (collapsed → full) | Speccy pattern: summary line on the card, click for the full breakout (per-slot RAM, per-drive SMART-ish basics); keeps cards scannable while offering depth | MEDIUM | Requires a second-tier query set (e.g. `Win32_PhysicalMemory` per-slot) + expand/collapse UI state. Genuinely useful, but doubles card complexity. |
| CPU/GPU temperature readout | The most-missed Speccy feature in tweaking dashboards; temp next to load answers "is my machine healthy" in one glance | HIGH | No inbox CIM class exposes temps reliably — needs `MSAcpi_ThermalZoneTemperature` (often absent/stale) or OpenHardwareMonitor-style drivers (out of scope: no new dependencies). Recommend deferring; listing here to explain *why not v1*. |

### Anti-Features (Deliberately NOT Building)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Editing specs or actions from Home | "One-click fix from the dashboard" sounds efficient | Home's contract is read-only overview; actions belong on tweak pages with Apply/Revert semantics. Mixing execution into Home breaks the page's trust model and the existing runspace flow. | Keep Home read-only; link nothing executable. (PROJECT.md out of scope.) |
| Real-time sensor polling / live graphs | Task Manager-style live CPU/GPU graphs look impressive | Requires a DispatcherTimer polling loop + charting (no inbox WPF chart control); burns CPU, fights the existing log-pump timer, and duplicates Task Manager. Live-*on-open* refresh already solves staleness. | Refresh-on-show only; leave continuous monitoring to Task Manager/HWiNFO. |
| Update status / pending-reboot flag | Seems natural on an "overview" page | Needs Windows Update Agent API queries (slow, COM-heavy, version-sensitive); pending-reboot detection spans 4+ registry locations with false positives. Separate feature with its own failure modes. | Defer to later milestone. (PROJECT.md out of scope.) |
| License / activation state | "System info" feels like it should include activation | `SoftwareLicensingProduct` queries are slow and return confusing multi-entry results (OEM + KMS + retail ghosts); misreporting activation creates support load. | Defer to later milestone. (PROJECT.md out of scope.) |
| Install date / uptime display | Cheap trivia for a dashboard | Low value, and uptime via `Win32_OperatingSystem.LastBootUpTime` is misleading under Fast Startup (uptime ≠ session age). Clutters cards for near-zero decision value. | Defer to later milestone. (PROJECT.md out of scope.) |
| Hub shortcuts to Check/Refresh pages | Dashboard-as-launcher is a common pattern | User explicitly chose plain default landing, not a hub; shortcut tiles add nav-state coupling and dilute the specs-first purpose. | Plain landing; existing sidebar nav already reaches every page. (PROJECT.md out of scope.) |
| Benchmark / stress-test buttons | Tweakers love scores | Benchmarking is a separate domain (methodology, baselines, thermal risk); a misleading score damages credibility more than no score. | Leave to Cinebench/CrystalDiskMark; Home reports facts, not scores. |
| Network / IP / Wi-Fi details on Home | "Full system info" completists ask | Network state changes constantly (VPN, DHCP), needs admin-adjacent APIs, and IP display has screenshot-sharing privacy implications. Not part of the five-spec-groups decision. | Defer; a future Network card can be its own scoped addition. |

## Feature Dependencies

```
[Home default landing]
    └──requires──> [Card grid shell + nav entry]
                        └──requires──> [Per-group CIM/registry queries]
                                            ├──> [CPU query] (Win32_Processor)
                                            ├──> [RAM query] (Win32_ComputerSystem + Win32_OperatingSystem)
                                            ├──> [GPU query] (Win32_VideoController, multi-instance aware)
                                            ├──> [Disk query] (Win32_DiskDrive + Win32_LogicalDisk join)
                                            ├──> [Board/BIOS query] (Win32_BaseBoard + Win32_BIOS)
                                            └──> [Windows edition/build query] (registry CurrentVersion + UBR)

[Live refresh on show] ──requires──> [Per-group queries] + [Background runspace execution]
[Live refresh on show] ──requires──> [Loading/placeholder state] (else blank-flash on slow WMI)

[Copy-to-clipboard export] ──enhances──> [Per-group queries] (reuses queried values, zero new queries)
[Health indicators] ──enhances──> [RAM query] + [Disk query] (threshold coloring on existing numbers)
[Hostname header] ──enhances──> [RAM query] (same Win32_ComputerSystem object, free fields)
[Expandable card detail] ──enhances──> [Per-group queries] (second-tier queries per card)
```

### Dependency Notes

- **Card grid shell requires per-group queries:** the shell is empty chrome without data; queries are the true foundation — build and validate queries first (even in console), then hang cards on them.
- **Live refresh requires background execution + loading state:** refresh-on-show without off-UI-thread execution freezes the window on slow WMI (first-launch WMI warmup can take seconds); without a placeholder state, cards flash blank and read as broken.
- **Copy export enhances queries:** strictly additive — needs no new data sources, only formats what's already queried. Cheapest differentiator to add.
- **Health indicators enhance RAM + Disk queries:** presentation-only layer; no new queries, but depends on those two cards existing with numeric values.
- **GPU multi-instance awareness conflicts with "first result only" shortcuts:** taking `VideoController[0]` silently drops the dGPU on dual-GPU laptops or reports the wrong adapter — always enumerate all instances.

## MVP Definition

### Launch With (v1)

- [ ] CPU card (model, cores/threads, speed) — the lead spec; wrong or missing = page distrusted
- [ ] RAM card (total + used/free) — #2 spec question; usage makes it live, not static
- [ ] GPU card (model + VRAM + driver, all adapters) — #3 spec question for the tweaker audience
- [ ] Disk card (per-volume free/total) — actionable storage state; volumes match user mental model
- [ ] Motherboard + BIOS card (board model, BIOS version/date) — troubleshooting cornerstone
- [ ] Windows card (edition + friendly version + full build incl. UBR) — tweak-safety context
- [ ] Default landing + card grid shell — Home must *be* home, in overview layout
- [ ] Live refresh on show (background runspace + loading state) — Core Value: accurate, never stale
- [ ] Per-field n/a fallbacks — real-world hardware/VM data is messy; robustness is table stakes

### Add After Validation (v1.x)

- [ ] Copy-to-clipboard spec export — trigger: first user asks "how do I share my specs"; near-zero cost, add as soon as v1 queries are stable
- [ ] Health indicators (disk/RAM thresholds) — trigger: cards feel like "dead numbers"; pure presentation pass over existing data
- [ ] Hostname/manufacturer header — trigger: multi-PC users confuse machines; free fields from existing query

### Future Consideration (v2+)

- [ ] Expandable per-card detail (per-slot RAM, per-drive detail) — why defer: doubles card UI complexity; validate that users want depth before building it
- [ ] Temperature readout — why defer: no reliable inbox source; needs driver-level dependency the project forbids
- [ ] Update status / activation / uptime — why defer: explicitly out of scope; each is its own failure-prone feature

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| CPU card | HIGH | LOW | P1 |
| RAM card (total + usage) | HIGH | LOW | P1 |
| GPU card (multi-adapter) | HIGH | LOW | P1 |
| Disk card (per-volume) | HIGH | MEDIUM | P1 |
| Motherboard + BIOS card | HIGH | LOW | P1 |
| Windows edition + build | HIGH | LOW | P1 |
| Default landing + card grid | HIGH | LOW | P1 |
| Live refresh (background + loading) | HIGH | MEDIUM | P1 |
| Per-field n/a fallbacks | HIGH | LOW | P1 |
| Copy-to-clipboard export | MEDIUM | LOW | P2 |
| Health indicators | MEDIUM | LOW | P2 |
| Hostname header | LOW | LOW | P2 |
| Expandable card detail | MEDIUM | MEDIUM | P3 |
| Temperature readout | MEDIUM | HIGH | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | Speccy (reference standard) | Settings > About / msinfo32 (inbox baseline) | WinUtil / Winhance (tweaker peers) | Our Approach |
|---------|----------------------------|----------------------------------------------|-------------------------------------|--------------|
| Summary overview page | Summary tab: OS/CPU/RAM/board/GPU/storage + temps at a glance — the pattern to clone | About page: CPU/RAM/edition/version/build only; msinfo32: exhaustive but unnavigable wall of text | WinUtil has NO dashboard (Install/Tweaks/Config/Updates tabs) — deliberate non-example; Winhance opens on grouped tweak categories, not specs | Speccy-style summary card grid scoped to the five spec groups + Windows card; inbox-data only |
| CPU detail level | Model, cores/threads, speed, temp, cache | Model string only | None shown | Model + cores/threads + speed (temps deferred — no inbox source) |
| RAM detail level | Total, per-slot, usage, timings | Installed total only | None shown | Total + used/free (per-slot deferred to v2 expandable detail) |
| GPU detail level | Model, VRAM, driver, temp, clocks | Not shown | None shown | Model + VRAM + driver, all adapters enumerated |
| Disk detail level | Per-drive model, capacity, SMART, temp | Per-volume usage bars (Storage settings) | None shown | Per-volume free/total; volumes over physical drives (user mental model) |
| OS detail level | Edition, version, build, install date | Edition + version + build (+ hostname) | None shown | Edition + friendly version + full build incl. UBR (install date out of scope) |
| Export / share | Snapshot file + publish URL | Copy button on About page (Win11) | None | Copy-to-clipboard plaintext (P2 — mirrors Win11 About's Copy button) |
| Live / refresh | Temp-driven live updates | Static until reopened | n/a | Refresh-on-show (deliberate middle ground: never stale, no polling loop) |

## Sources

- Speccy summary-page conventions (CCleaner Speccy product page; MakeUseOf walkthrough — Summary lands on OS edition, CPU, RAM, motherboard, graphics, storage)
- Microsoft Support: `msinfo32` system-summary fields (OS version/build, processor, installed RAM, BIOS) and Settings > System > About fields (processor, RAM, edition, version, build)
- Chris Titus Tech WinUtil repo/docs (tab structure: Install/Tweaks/Config/Updates — no system-info dashboard; confirms dashboard is a differentiator among tweakers, not table stakes there)
- Winhance site/repo (grouped tweak-category landing; optimization dashboard framing without a specs page — same gap)
- CPU-Z / HWiNFO positioning (deep-dive tools: tabbed detail + sensor monitoring; confirms polling-graphs belong to specialist tools, supporting the anti-feature call)

---
*Feature research for: Home system-info dashboard in Windows tweaking tool (AkariOS-Ultimate)*
*Researched: 2026-10-08*
