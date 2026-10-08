# Pitfalls Research: Home System-Info Page (AkariOS-Ultimate)

**Domain:** Live system-info dashboard added to a PowerShell 5.1 + WPF desktop tweaking tool
**Researched:** 2026-10-08
**Confidence:** HIGH (WMI/CIM quirks are extensively documented across MS Learn, vendor errata, and community post-mortems; app-specific pitfalls grounded in `.planning/codebase/` analysis)

## Critical Pitfalls

### Pitfall 1: Synchronous CIM/WMI queries on the UI thread freeze the window

**What goes wrong:**
The Home spec queries (`Win32_Processor`, `Win32_PhysicalMemory`, `Win32_VideoController`, `Win32_LogicalDisk`, `Win32_BaseBoard`, `Win32_BIOS`, `Win32_OperatingSystem`) run inline in `Show-Page` or a click handler. The first `Get-CimInstance` call in a session is 2.5–3x slower than subsequent ones (implicit session setup), and any single provider hiccup can stall for seconds. The whole WPF window goes unresponsive — can't drag, can't switch tabs — on every Home visit.

**Why it happens:**
`Akari.ps1` already isolates tweak bodies via `Invoke-Code` (background runspace + `BeginInvoke` + 150 ms `DispatcherTimer` log pump), so it feels natural to treat spec reads as "fast local calls" and skip that machinery. Developers also test on healthy bare-metal machines where all seven queries return in <200 ms, never seeing the slow path (stale CIM session, busy WMI provider, VM without integration services).

**How to avoid:**
- Route ALL Home spec gathering through the existing `Invoke-Code` background-runspace + `DispatcherTimer` pump pattern (`Akari.ps1:223-256`). No `Get-CimInstance` on the UI thread, ever — not even "just one quick query."
- Render placeholder cards immediately ("Reading specs…"), then fill values when the runspace completes. This matches the existing log-and-continue UX.
- Guard rapid tab-switching: reuse the existing `$script:Busy` guard or a Home-specific in-flight flag so a second Home visit while a query runspace is active doesn't spawn a second one (the architecture allows exactly one background runspace at a time by design).

**Warning signs:**
- Any `Get-CimInstance` / `Get-WmiObject` / `Get-Counter` call reachable from `Show-Page`, nav handlers, or `New-Row`-style rendering code without going through `Invoke-Code`.
- Code review shows `PowerShell.Invoke()` (synchronous) instead of `BeginInvoke()` for the spec runspace — `Invoke()` blocks by design even from a runspace.

**Phase to address:**
Phase 1 (spec-gathering engine + threading model). This decision constrains everything after it; retrofitting async later means rewriting every card.

---

### Pitfall 2: RAM total computed from a single instance instead of summed across sticks

**What goes wrong:**
Home shows "8 GB installed" on a 32 GB machine (4×8 GB), or crashes with a null-reference on single-stick machines. Variants: using `Win32_ComputerSystem.TotalPhysicalMemory` and reporting usable memory (BIOS-reserved subtracted) as installed memory; using `.Capacity` directly on the collection and getting `$null` back.

**Why it happens:**
`Win32_PhysicalMemory` returns **one instance per DIMM**. Three separate traps compound:
1. Forgetting `Measure-Object -Property Capacity -Sum` (the classic Spiceworks/StackOverflow FAQ — per-stick rows displayed as if each were the total).
2. PowerShell 5.1 collection unrolling: `(Get-CimInstance Win32_PhysicalMemory).Capacity` returns `$null` when the property access hits an array strangely on some hosts, and a scalar (not an array) when exactly one stick is present — so `.Count` / `[0]` indexing breaks on single-stick machines.
3. `TotalPhysicalMemory` (Win32_ComputerSystem) is documented by Microsoft as potentially inaccurate ("not accurate if the BIOS is using some of the physical memory") — it's usable RAM, not installed RAM.

**How to avoid:**
- Canonical pattern: `@(Get-CimInstance Win32_PhysicalMemory | Select-Object -ExpandProperty Capacity | Measure-Object -Sum).Sum` — force array context with `@()`, sum explicitly, divide by 1GB with rounding.
- Prefer the summed `Win32_PhysicalMemory.Capacity` over `TotalPhysicalMemory` for the "installed" number (matches Task Manager's installed figure and `GetPhysicallyInstalledSystemMemory`).
- Known-hardware caveat to document, not fix: on old-SMBIOS/multi-socket servers (>32 GB sticks, pre-2.7 SMBIOS), WMI can report half the RAM (Extended Size field missed). Out of scope for a consumer tool, but the code must not crash on it.
- Test matrix must include: 1 stick, 2 sticks, 4 sticks, and a VM (see Pitfall 5).

**Warning signs:**
- Code reads `.Capacity` without `Measure-Object -Sum`.
- Code indexes `[0]` into a WMI result or calls `.Count` on it without `@()` wrapping.
- Any use of `TotalPhysicalMemory` labeled "installed."

**Phase to address:**
Phase 1 (spec-gathering engine). Add the 1-stick / multi-stick / VM matrix to that phase's verification checklist.

---

### Pitfall 3: GPU card shows the wrong adapter or "4 GB" on an 8 GB+ card

**What goes wrong:**
Two failure modes, both extremely common in the wild (launcher/display-tool bug reports):
1. Machine with iGPU + discrete GPU shows the Intel iGPU (or a virtual adapter — Parsec, Bomgar, RDP mirror driver) as "the GPU" because the code took `Win32_VideoController` instance `[0]`, which is enumeration order, not "primary."
2. Any card with >4 GB VRAM reports exactly 4 GB (or a wrapped/negative number) because `Win32_VideoController.AdapterRAM` is a **uint32** — it physically cannot represent more than 4 GB. This is a WMI-level bug affecting all Windows versions.

**Why it happens:**
Single-GPU dev machines never expose the multi-instance path, and the uint32 cap is invisible until someone with an RTX card files a bug. Copy-pasted `($gpu.AdapterRAM / 1GB)` snippets dominate blogs and Stack Overflow.

**How to avoid:**
- Never take instance `[0]`. Enumerate all `Win32_VideoController` instances; prefer the discrete adapter: filter out known virtual/mirror entries (`PNPDeviceID` starting with `ROOT\DISPLAY`, names matching `*Parsec*`, `*Bomgar*`, `*RDP*`, `*Basic Display*` / Microsoft Basic Display Adapter fallback), then pick the instance with the largest VRAM (or list all adapters if more than one physical GPU remains).
- For VRAM >4 GB, read the registry fallback `HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\<nnnn>\HardwareInformation.qwMemorySize` (uint64, correct values) matched by adapter, instead of `AdapterRAM`. Keep `AdapterRAM` only as a fallback when the registry value is absent.
- `DriverVersion` comes from WMI per-instance — keep it paired with the same instance selected as primary, not from a different index.
- Null-tolerant: on headless VMs / Server Core without display drivers, `Win32_VideoController` can return nulls for `CurrentBitsPerPixel`/`Current*Resolution` (documented Microsoft KB issue) — don't bind those to cards at all.

**Warning signs:**
- Any `...VideoController...[0]` or `Select-Object -First 1` without a filter.
- Any `$_.AdapterRAM / 1GB` without a >4 GB handling path.
- GPU name and VRAM sourced from different instances/queries.

**Phase to address:**
Phase 2 (GPU + disk + board cards — the "quirky hardware" phase). The registry-fallback helper belongs here, not in Phase 1.

---

### Pitfall 4: Windows 10 vs 11 misidentified ("Windows 10 Pro" on a Windows 11 machine)

**What goes wrong:**
Home proudly displays "Windows 10 Pro 23H2" on a Windows 11 machine, or shows a blank version on Server/LTSC. Users treat OS identity as ground truth — getting it wrong destroys trust in every other card.

**Why it happens:**
Three compounding facts:
1. Registry `ProductName` still says "Windows 10 …" on Windows 11 — Microsoft never updated it.
2. `[Environment]::OSVersion.Version` and `Win32_OperatingSystem.Version` both report `10.0.x` for Windows 10 AND 11 — they cannot distinguish the two.
3. `ReleaseId` is deprecated (frozen/stale since 21H1); `DisplayVersion` (e.g. `23H2`) is the correct source but is **absent on Server SKUs, LTSC, and older builds** — code that assumes it exists shows blanks.

**How to avoid:**
- Edition/name: use `(Get-CimInstance Win32_OperatingSystem).Caption` (e.g. "Microsoft Windows 11 Pro"), not registry `ProductName`, not `Get-ComputerInfo WindowsProductName` (which has the same Win10-label problem).
- 10-vs-11 disambiguation: `[int]$CurrentBuild -ge 22000` → Windows 11 (build table: 22000=21H2, 22621/22631=22H2/23H2, 26100=24H2, 26200=25H2). Note `CurrentBuild` is a **string** — cast to `[int]` before comparing.
- Version label: `DisplayVersion` with fallback (build-number lookup table, then "Build NNNNN") when the value is missing; full build as `CurrentBuild.UBR`.
- Test on at least: Windows 11 client, Windows 10 (if reachable), and one Server/VM image to exercise the `DisplayVersion`-missing fallback.

**Warning signs:**
- Code reads `ProductName` from the registry for the OS name.
- Code compares build numbers as strings (`"26100" -gt "22000"` works by accident; `"9300" -gt "22000"` is `$true` as string — Server 2012 R2 edge).
- No fallback branch for missing `DisplayVersion`.

**Phase to address:**
Phase 1 (spec engine) — OS identity is the simplest query group and the right first consumer of the placeholder-then-fill + fallback-text conventions.

---

### Pitfall 5: Nulls, blanks, and placeholder strings on VMs, OEM boards, and driver-less machines

**What goes wrong:**
Home shows empty cards, "0 GB", or a crash (divide-by-`$null`, `.ToString()` on `$null`) on perfectly valid machines: Hyper-V/VirtualBox VMs, whitebox boards, fresh installs without chipset drivers. Worse: it displays literal garbage like `SerialNumber = "Base Board Serial Number"` or `Manufacturer = "To be filled by O.E.M."` as if it were real data.

**Why it happens:**
- `Win32_BaseBoard.Manufacturer/Model/SerialNumber` are frequently empty or contain SMBIOS filler (`"To be filled by O.E.M."`, `"System Serial Number"`, `"Base Board Serial Number"`, `"None"`). VMs return hypervisor-generic strings.
- `Win32_PhysicalMemory` can be **entirely empty** on some VMs; `Win32_BIOS.SerialNumber` likewise.
- `Win32_Processor` fields vary: `NumberOfCores`/`ThreadCount` depend on SMBIOS version; VMs may report 0 or 1 unexpectedly.
- `Win32_LogicalDisk` (if used for disks) returns `$null` Size/FreeSpace for some volumes.

**How to avoid:**
- Establish a single `Get-SpecSafe` convention in the spec engine: every query wrapped in try/catch with `-ErrorAction SilentlyContinue`, every displayed value passed through a formatter that maps `$null`/`""`/`0`/known-filler-strings → `"Not available"` (or hides the row). Never let raw WMI strings reach the UI.
- Maintain a small filler-string blocklist: `"To be filled by O.E.M."`, `"To Be Filled By O.E.M."`, `"System Serial Number"`, `"Base Board Serial Number"`, `"None"`, `"Unknown"`, `"Default string"`.
- For the board card, prefer `Product` over `Model` (on consumer boards `Model` is often empty while `Product` holds e.g. `GA-78LMT-S2P`); display `Manufacturer + Product`, fall back to `Name`, then to "Not available."
- Guard all arithmetic: `if ($sum -gt 0)` before dividing; format sizes with a helper that handles `$null`.

**Warning signs:**
- Any `$x.Property.ToString()` / division / `-f` formatting applied directly to a WMI property without a null check.
- Board/BIOS values displayed without filler-string filtering.
- Testing only on the developer's own bare-metal machine.

**Phase to address:**
Phase 1 (conventions + `Get-SpecSafe`/formatter helpers) with enforcement in every later card phase; VM testing explicitly in verification.

---

### Pitfall 6: Breaking the default-tab change and Tuner visibility gating

**What goes wrong:**
After adding Home, the app still lands on Windows; or lands on Home but the nav highlight is wrong; or the Advanced-page `Tuner`/`SvcTuner` panels now show on every tab (or never show); or search/content rendering throws because `Show-Page` assumes every category is a tweak list. These are startup-path regressions — every user hits them on first launch.

**Why it happens:**
Home is the first non-tweak page in an architecture where everything is tweak-list-shaped:
- `$script:Cat` defaults to `'Windows'` (`Akari.ps1:135`-area state); nav buttons, `Show-Page` filtering (`Akari.ps1:194-218`), and `$script:RowCache` all assume `$script:Cat` names a tweak category.
- `Tuner`/`SvcTuner` visibility is hard-gated on `$script:Cat -eq 'Advanced'` (`Akari.ps1:204-206`). A well-meaning refactor ("hide tuners on non-tuner pages" → generic hide) can invert or break the gate.
- Search box filtering operates over tweak rows; Home cards must be immune to (or explicitly cooperate with) search text.
- `Show-Page` rebuilds `$Rows` children per category — Home cards injected into the same container can be wiped by a re-render, or duplicate on each visit if `RowCache` keys collide.

**How to avoid:**
- Treat Home as a first-class page kind in `Show-Page`: explicit `if ($script:Cat -eq 'Home')` branch that renders/caches cards separately from tweak rows; never shoehorn cards into `$script:RowCache` tweak entries.
- Change the default in exactly one place (`$script:Cat = 'Home'`) plus the matching nav-button default-highlight; keep the `'Advanced'` tuner gate as an exact-match condition — do not generalize it.
- Home is read-only: ensure the bubbled `$Rows` click handler (`Akari.ps1:264-290`, tag-split `"<id>|<kind>|<arg>"`) ignores card elements (cards carry no action tags; verify clicks on cards are no-ops, not exceptions).
- Out-of-scope guard: no spec editing, no hub shortcuts, no activation/uptime additions — each would entangle Home with tweak execution and expand this pitfall's blast radius.

**Warning signs:**
- `Show-Page` edited without a visually separate Home branch.
- Tuner visibility condition changed from exact `-eq 'Advanced'` to anything else.
- Nav items added without updating the default-selection highlight logic.
- Click-handler exceptions when clicking card whitespace during manual testing.

**Phase to address:**
Phase 3 (Home page shell: default tab + navigation + card-grid container). All card-content phases must come after the shell branch exists so they have a safecontainer to target.

---

### Pitfall 7: Card grid breaks the dark theme or layout at real-world sizes

**What goes wrong:**
Cards render with white backgrounds, unreadable grey-on-grey text, or fixed-pixel widths that overflow on 125%/150% DPI scaling; long GPU/board names (`"12th Gen Intel(R) Core(TM) i7-1260P"`, `"ROG STRIX Z790-E GAMING WIFI"`) clip or push neighboring cards off the grid; the Home page looks like a different application from the tweak pages.

**Why it happens:**
- `UI/MainWindow.xaml` theming lives in resource tokens (`Bg S1 S2 Bd Tx Mu Inv InvT Warn Bad`, `Ink` tokens; `Btn/BtnP/Nav/Chip/Flat` styles) — hand-written card XAML that hardcodes `Background="White"` / `Foreground="#333"` bypasses all of it, including any future theme tweak.
- Dynamic rows are generated in code (`New-Row`, `Akari.ps1:125-173`), not XAML — cards built as static XAML in a second file create a parallel construction path the host doesn't manage (FindName wiring, disposal, re-render).
- Fixed `Width="300"` cards ignore WPF's layout system; at higher DPI or narrow windows the `WrapPanel`/grid overflows instead of reflowing.

**How to avoid:**
- Build cards in code following the `New-Row` pattern (Border/StackPanel/TextBlock composition), referencing theme brushes via `FindResource`/existing brush keys only — zero hardcoded colors, zero hardcoded fonts.
- Use fluid layout (`WrapPanel` or star-sized `Grid` columns, `TextWrapping="Wrap"`, `TextTrimming="CharacterEllipsis"` on single-line values) and test at 100%/125%/150% scaling plus the minimum window size.
- Card chrome (headers, value/error styling) reuses existing style keys where possible; any new style goes into `MainWindow.xaml` resources alongside the existing tokens, not inline on elements.

**Warning signs:**
- Any `Background=` / `Foreground=` literal (hex or named color) in new card code.
- Fixed `Width`/`Height` on cards or card text.
- A second XAML file for cards that the host loads separately from `MainWindow.xaml`.
- Manual test only at 100% DPI with short device names.

**Phase to address:**
Phase 3 (card-grid shell + one reference card establishes the code-gen + theme-token pattern); all content phases reuse it. Add a DPI/name-length visual check to each card phase's verification.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| One mega-query function returning all specs as a hashtable | Fewer runspaces to manage | Single provider stall blocks ALL cards; can't show CPU while GPU times out; all-or-nothing error handling | Never — query per group so each card degrades independently |
| `Get-WmiObject` instead of `Get-CimInstance` | Slightly faster single local query; familiar snippets | Deprecated cmdlet, no CIM-session reuse, PS7-incompatible if the codebase ever migrates; inconsistent with inbox-only future | Never for new code — use `Get-CimInstance` throughout |
| Caching specs once at startup instead of live-on-show | Faster tab switches; simpler code | Violates the core requirement (live every time Home is shown); RAM/disk numbers go stale within the session | Never — live-on-show is a Key Decision in PROJECT.md |
| Hardcoded GPU-position index after "it works on my machine" | Ships faster | Wrong-GPU bug reports from every iGPU+dGPU laptop (the majority of real users) | Never |
| Putting card value-formatting inline per card | No helper to design | Five inconsistent "Not available" wordings; null-guards rot independently | Only for the first reference card; extract helpers by the second card |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Spec runspace → UI thread | Setting `TextBlock.Text` directly from the background runspace (cross-thread `InvalidOperationException`, swallowed by `Dispatcher.UnhandledException` into a confusing log line) | Marshal via `$window.Dispatcher.Invoke()` or write results to the existing `ConcurrentQueue` and let the `DispatcherTimer` pump apply them — same bridge as tweak output |
| Spec runspace lifecycle | `BeginInvoke()` without matching `EndInvoke()`/`Dispose()` — leaks a runspace + thread on every Home visit; memory grows per tab switch | Mirror `Invoke-Code`'s completion handler: `EndInvoke`, dispose `$ps` and runspace, clear the in-flight flag — verify handle count flat across 20 Home visits |
| `Get-Counter` for live CPU frequency | Calling `Get-Counter '\Processor Information(_Total)\% Processor Performance'` on every refresh | Don't ship live frequency at all: WMI `CurrentClockSpeed` is NOT live (Turbo Boost is invisible to Windows; value is static SMBIOS). Show `MaxClockSpeed` as base speed plus the model string from `Name` (which embeds marketed GHz). Live frequency needs perf counters + sampling delay — out of scope |
| Disk query scope | `Win32_LogicalDisk` unfiltered — USB sticks, DVD drives, network shares, and `null`-size volumes appear as "drives" | Filter `DriveType=3` (local fixed disks) only; skip instances with `$null`/0 `Size`; show per-volume `DeviceID + Free/Total`; consider rolling up multiple partitions per physical disk in display, not in query |
| Search box vs Home | Search text filters tweak rows; Home cards either vanish under search or break the filter | Scope search to tweak categories only; entering search while on Home either switches to a tweak context or leaves cards untouched — decide explicitly, don't let `Show-Page` fall through |
| `state.json` persistence | Persisting spec values to `state.json` "for faster loads" | Specs are live by design; `state.json` holds Toggle memory only. Never cache specs on disk — stale hardware data is worse than a 300 ms load |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full unfiltered `Get-CimInstance` (all properties, no `-Property`) × 7 classes on every show | Each Home visit takes 1–3 s even on fast machines; tab feels laggy | Pass `-Property` with only needed properties to every query (also reduces DCOM payload); query per group in one runspace, sequentially — total stays well under a second locally | Immediately on first implementation if unfiltered; compounds on HDD/VM hosts |
| No guard against overlapping refreshes | Rapid Home↔Advanced tab toggling spawns queued runspaces; UI stutters, results arrive out of order (stale data overwrites fresh) | Single in-flight flag (`$script:HomeBusy` or reuse `$script:Busy` semantics); ignore re-entry while busy; always apply results only if Home is still the active tab | First time a user double-clicks the Home nav item |
| `Get-ComputerInfo` for OS details | Single call takes seconds (it gathers far more than needed) and blocks even in a runspace longer than necessary | Use targeted `Win32_OperatingSystem -Property Caption,Version,BuildNumber,OSArchitecture` + 3 registry reads — milliseconds | Always slower; noticeable on every Home show |
| Per-card runspaces (7 parallel runspaces) | Faster in theory; in practice 7× runspace setup/teardown + 7× implicit CIM sessions, plus contention with the single-runspace execution architecture | One spec runspace per refresh, sequential queries inside it; optionally one shared `New-CimSession` passed to all queries (measurably faster than 7 implicit sessions) | At implementation; also violates the "exactly one background runspace" architectural constraint |

## Security Mistakes

This addition is read-only (CIM reads + HKLM reads the app already performs elevated). No new attack surface is introduced provided these hold:

| Mistake | Risk | Prevention |
|---------|------|------------|
| Displaying BIOS/board serial numbers prominently with copy-paste affordance | Serial numbers in screenshots end up in support requests / public issues — minor PII-ish fingerprinting aid | PROJECT.md scope is board *model* + BIOS *version/date* — do NOT display board/BIOS serial numbers on cards at all |
| Running spec "helpers" via `Run-Trusted` (TrustedInstaller hijack) | Rewrites a service `binPath` for a read that admin rights already permit; crash mid-hijack leaves the service broken | Never use `Run-Trusted` for spec queries — plain admin `Get-CimInstance`/registry reads suffice |
| Interpolating WMI strings into XAML/dynamic code without escaping | Device names contain `&<>"` rarely, but `XamlReader`-parsed strings with unescaped entities throw and break the page | Prefer code-constructed controls (`New-Object TextBlock`, `.Text = $value` assignments — no parsing) over string-built XAML; if building XAML strings, XML-escape all injected values |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Bare numbers without units or with raw bytes (`17179869184`, `2793`) | Users can't parse values at a glance — defeats the "specs at a glance" core value | Format every value: RAM/disk in GB with 1 decimal + free/total pairs; CPU speed as GHz with 2 decimals; driver date as short date; label every number (`Total`, `Free`, `Base speed`) |
| Cards show technical WMI vocabulary (`Caption`, `NumberOfLogicalProcessors: 16`, `DriveType 3`) | Reads as a debug dump, not an overview | Curate 2–4 human lines per card: CPU → model/cores-threads/base speed; RAM → total installed (+ used/free via `Win32_OperatingSystem.FreePhysicalMemory`); GPU → model/VRAM/driver; Disk → per-drive free/total bar or text; Board → manufacturer+product/BIOS version+date; Windows → Caption-derived edition + DisplayVersion + build |
| Stale "Reading…" placeholders that never resolve on failure | User stares at spinners with no recourse; looks broken rather than degraded | Every placeholder has a failure terminal state (`"Couldn't read disk info"`), never an infinite spinner; failures also write one line to the existing Log drawer (consistent with log-and-continue) |
| Over-eager precision implying live data (CPU "4.312 GHz" static) | Users compare against Task Manager, see mismatch, file "wrong speed" bugs | Label static values honestly (`Base speed 3.6 GHz`); never present `CurrentClockSpeed`/`MaxClockSpeed` as live frequency |
| Home empty on first launch before queries complete | Flash of blank page undermines "specs-first experience" | Skeleton/placeholder cards render synchronously with the page shell; values stream in — page shape is stable from frame one |

## "Looks Done But Isn't" Checklist

- [ ] **RAM card:** Often missing multi-stick summation — verify on 1-stick AND multi-stick AND VM; confirm figure matches Task Manager installed (not usable) RAM.
- [ ] **GPU card:** Often missing >4 GB handling — verify on a >4 GB card (or mock `AdapterRAM=4294967295` + registry value in a unit check); verify on iGPU+dGPU laptop that the discrete GPU is shown, not the iGPU or a virtual adapter.
- [ ] **Windows card:** Often missing Win11 disambiguation — verify registry-`ProductName`-based code path never ships; verify on Win11 (shows 11), on Server/LTSC/older build (no blank version — fallback fires).
- [ ] **Board card:** Often missing filler-string filtering — verify output never contains "To be filled by O.E.M." / "System Serial Number" / empty manufacturer; verify on a VM (graceful "Not available," no exception).
- [ ] **Live refresh:** Often missing actual re-query — verify values update between visits (change something observable, e.g. plug in a USB drive excluded from disks vs free-space change, or RAM free figure moves); verify NO disk cache/`state.json` involvement.
- [ ] **Default tab:** Often missing nav-highlight sync — verify cold launch lands on Home WITH Home highlighted, tuners hidden; switching to Advanced shows tuners; switching back to Home re-triggers live refresh.
- [ ] **No UI freeze:** Often missing slow-path test — verify windows drags/resizes during refresh (simulate slow WMI with `Start-Sleep` in the spec scriptblock during dev); verify rapid tab-switching doesn't overlap runspaces or leak handles.
- [ ] **Theme/layout:** Often missing DPI + long-name test — verify at 125%/150% scaling, minimum window width, and with the longest realistic device strings; zero hardcoded colors (grep for `#"[0-9A-Fa-f]{6}"` / `Background="` literals in new code).

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| UI-thread blocking queries shipped | MEDIUM | Move query block into `Invoke-Code`-style runspace; add placeholder cards; no card-content changes needed if formatting already isolated in helpers |
| Wrong RAM totals shipped | LOW | Replace total computation with `Measure-Object -Sum` pattern + `@()` guard; add 1-stick case to manual test; no architectural change |
| Wrong-GPU / 4 GB-cap shipped | LOW–MEDIUM | Add discrete-first selection + `qwMemorySize` registry fallback; existing card layout unchanged, only the data source changes |
| Win10-label-on-Win11 shipped | LOW | Swap name source to WMI `Caption` + build≥22000 gate; one-function fix, high embarrassment factor — prioritize |
| Broken default tab / tuner gating regression | MEDIUM | Restore exact `-eq 'Advanced'` gate; re-separate Home branch in `Show-Page`; add cold-launch nav-state assertions to prevent recurrence |
| Theme/layout breakage shipped | LOW | Replace literals with resource keys; switch fixed widths to fluid layout; no data-layer changes |
| Runspace leak (handles grow per visit) | MEDIUM | Add `EndInvoke`+dispose completion path mirroring `Invoke-Code`; verify with handle-count observation over 20 visits; may need app restart for already-affected sessions (no data loss — specs are never persisted) |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1 — UI-thread blocking queries | Phase 1: spec engine + threading | Drag window during refresh with injected 2 s provider delay; UI stays responsive; results fill placeholders |
| 2 — RAM summation errors | Phase 1: spec engine (CPU/RAM/OS first — simplest queries) | 1-stick / multi-stick / VM matrix; figure matches Task Manager installed RAM |
| 4 — Win10/Win11 misidentification | Phase 1: spec engine | Win11 shows 11; Server/no-DisplayVersion machine shows fallback, never blank |
| 5 — Null/filler-string handling | Phase 1: `Get-SpecSafe` + formatter conventions | VM pass with all-expected-nulls; output grep finds no filler strings |
| 3 — Wrong GPU / 4 GB cap | Phase 2: GPU + disk + board cards | >4 GB card shows real VRAM; iGPU+dGPU shows discrete; virtual adapters excluded; headless VM degrades gracefully |
| Disk scope (USB/network/ DVDs) | Phase 2: GPU + disk + board cards | Only `DriveType=3` with nonzero size shown; USB insert doesn't add a "drive" |
| 6 — Default tab + tuner gating | Phase 3: Home shell + navigation | Cold launch → Home highlighted, tuners hidden; Advanced → tuners back; Home revisit → refresh fires; card clicks are no-ops |
| 7 — Theme/layout breakage | Phase 3: card-grid shell (reference card sets the pattern) | 125%/150% DPI + min-width + long-name pass; grep shows zero hardcoded colors in new code |
| Overlapping refreshes / runspace leak | Phase 3 (shell owns the in-flight flag) + every card phase | Rapid tab-toggle: single in-flight refresh, no out-of-order writes, flat handle count over 20 visits |
| Honest labeling (no fake-live GHz) | Each card phase, enforced at Phase 3 review | No "current speed" claims; static speeds labeled `Base`; used/free RAM labeled as point-in-time |

## Sources

- Microsoft Learn: `Win32_PhysicalMemory`, `Win32_VideoController`, `Win32_Processor`, `Win32_BaseBoard`, `Win32_OperatingSystem` class docs (property types, SMBIOS provenance notes, `TotalPhysicalMemory` accuracy caveat, `AdapterRAM` uint32) — HIGH confidence
- Microsoft Support KB: null `Current*` values from `Win32_VideoController` on headless/driver-less systems — HIGH confidence
- Maik Koster CIM-vs-WMI benchmarks (implicit-session cost ~2.5–3x; DCOM/WSMAN session reuse) — MEDIUM-HIGH confidence
- Stack Overflow / Server Fault / Spiceworks threads: per-stick summation (`Measure-Object -Sum`), `.Capacity` `$null`-on-array, `CurrentClockSpeed` static-under-Turbo-Boost with `% Processor Performance` explanation, `AdapterRAM` 4 GB cap with `qwMemorySize` registry workaround, `Win32_BaseBoard` empty/filler serials, `ProductName`-says-Windows-10-on-11 + build≥22000 gate, `Get-CimInstance` single-vs-array `.Count` unrolling — MEDIUM confidence each, HIGH in aggregate (same answers recur independently for a decade)
- Hardware.Info issue #40 (`AdapterRAM` >4 GB bug + fix) — HIGH confidence on the uint32 cap
- SillyTavern-Launcher issue #72 (iGPU picked over dGPU; virtual-adapter contamination; registry-VRAM iteration fix) — MEDIUM confidence, directly on-point for multi-adapter selection
- PowerShellFAQs / Windows OS Hub / tseknet / ctrlaltnod guides on `DisplayVersion` vs `ReleaseId`, `CurrentBuild`/`UBR`, `Get-ComputerInfo` cost — MEDIUM confidence
- `.planning/codebase/ARCHITECTURE.md` (AkariOS-Ultimate): `Invoke-Code` runspace + `DispatcherTimer` pump, `$script:Cat` default, `Tuner`/`SvcTuner` `'Advanced'` gate, `Show-Page`/`RowCache`, bubbled click handler, `state.json` toggle-only scope — HIGH confidence (repo-grounded)

---
*Pitfalls research for: AkariOS-Ultimate Home system-info page*
*Researched: 2026-10-08*
