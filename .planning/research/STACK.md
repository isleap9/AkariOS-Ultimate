# Stack Research

**Domain:** Home system-info dashboard (Windows PowerShell 5.1 + WPF, inbox-only)
**Researched:** 2026-10-08
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `Get-CimInstance` (CimCmdlets, inbox in PS 3.0+) | PowerShell 5.1 inbox | All live hardware/OS queries | Supersedes `Get-WmiObject` since PS 3.0; Microsoft docs ("Working with WMI", PS101 ch.7) say WMI cmdlets are deprecated and CIM cmdlets are for all new development. CIM is measurably faster (community benchmarks ~35s WMI vs ~2.5s CIM on remote batches; local gap is smaller but same direction), returns lighter objects (no system properties/methods baggage), and supports `-Property`/`-Filter` to trim payload before it crosses the provider boundary. `Get-WmiObject` is removed entirely in PS 6+/7 — CIM is the only forward-compatible choice. |
| Registry provider (`Get-ItemProperty`) on `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` | Inbox | Windows edition + build display (ProductName, DisplayVersion, CurrentBuildNumber, UBR, EditionID) | Fastest source for the Windows card (~1ms, no provider round-trip). CIM `Win32_OperatingSystem` confirms Caption/BuildNumber but registry is canonical for the human display string ("Windows 11 Pro", "23H2", full build `CurrentBuildNumber.UBR`). Must be read from the 64-bit view — app is 64-bit PS 5.1 so no WOW6432Node redirection concern, but never hard-code the WOW6432Node path. |
| `Win32_OperatingSystem` (CIM, singleton) | `root/cimv2`, inbox | Live RAM used/free + OS cross-check | Only source that gives *live* free memory (`FreePhysicalMemory`, KB) alongside totals (`TotalVisibleMemorySize`, KB) in one cheap singleton query. Cross-checks `Caption`/`Version`/`BuildNumber`/`OSArchitecture` against registry so the Windows card is never wrong if one source lags a feature update. Singleton = one instance, always fast. |
| Existing `Invoke-Code` background-runspace + log-pump pattern | Existing app infra | Executing all spec queries off the UI thread | Live-on-open refresh must not block WPF rendering. The app already owns this pattern (runspace + DispatcherTimer pump); spec collection is a natural `Invoke-Code` scriptblock returning a hashtable/PSObject per card. No new threading machinery. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Win32_Processor` | `root/cimv2` inbox | CPU card: `Name`, `NumberOfCores`, `NumberOfLogicalProcessors`, `MaxClockSpeed` | Always. One instance per physical socket — take instance `[0]` (or max) on consumer boards; sum cores only for multi-socket servers. Prefer `MaxClockSpeed` (MHz, static) over `CurrentClockSpeed` (throttled value, misleading on display). Verified: learn.microsoft.com `win32-processor`. |
| `Win32_ComputerSystem` | `root/cimv2` inbox | RAM card total: `TotalPhysicalMemory` (bytes); system `Manufacturer`/`Model` | Always. Single instance, very fast. NOTE per MS docs: `TotalPhysicalMemory` can under-report when BIOS reserves memory — treat `Win32_PhysicalMemory.Capacity` sum as authoritative total and `ComputerSystem` as fast fallback. Verified: learn.microsoft.com `win32-computersystem`. |
| `Win32_PhysicalMemory` | `root/cimv2` inbox | RAM card detail: per-stick `Capacity` (bytes), `Speed`/`ConfiguredClockSpeed` (MHz), `SMBIOSMemoryType` | Always (sum `Capacity` for authoritative total). One instance per DIMM. Use `ConfiguredClockSpeed` where present (Win10+), fall back to `Speed`. Verified: learn.microsoft.com `win32-physicalmemory`. |
| `Win32_VideoController` | `root/cimv2` inbox | GPU card: `Name`, `AdapterRAM` (bytes), `DriverVersion`, `VideoProcessor` | Always. One instance per adapter — filter out `PNPDeviceID`-less/software mirrors if needed. `AdapterRAM` is `uint32` and wraps/returns 4GB-capped values on >4GB cards (known WDDM-era limitation) — display with "≥4 GB / see dedicated app" guard or cross-check via DXGI only if ever needed (out of scope now). `DriverVersion` string is display-ready. Verified: learn.microsoft.com `win32-videocontroller`. |
| `Win32_LogicalDisk` with `-Filter "DriveType=3"` | `root/cimv2` inbox | Disk card: per-volume `DeviceID`, `VolumeName`, `Size`, `FreeSpace` (bytes), `FileSystem` | Always. `DriveType=3` = local fixed disks only — excludes optical/network/RAM disks server-side. This is what users mean by "disk free space". Verified: learn.microsoft.com `win32-logicaldisk` (DriveType enum: 2 removable, 3 local, 4 network, 5 optical, 6 RAM). |
| `Win32_BaseBoard` | `root/cimv2` inbox | Motherboard: `Manufacturer`, `Product` (board model), `SerialNumber` | Always for the board half of the board/BIOS card. Single instance, fast. `Product` (not `Model`/`Name`) is the board model per MS docs. On OEM laptops `Manufacturer`+`Product` may return the system SKU — acceptable, still accurate. Verified: learn.microsoft.com `win32-baseboard`. |
| `Win32_BIOS` | `root/cimv2` inbox | BIOS: `Manufacturer`, `SMBIOSBIOSVersion`, `ReleaseDate` (WMI datetime → convert) | Always for the BIOS half. Prefer `SMBIOSBIOSVersion` (SMBIOS-reported, stable across legacy/UEFI boot) over `Version`/`BIOSVersion[]`; `ReleaseDate` needs `ConvertToDateTime`/`ManagementDateTimeConverter`. Verified: learn.microsoft.com `win32-bios` (incl. remark that non-SMBIOS props can differ between legacy-BIOS and UEFI boot). |
| .NET `[Microsoft.Win32.Registry]` / PS Registry provider | .NET Framework inbox | Reading the CurrentVersion key | Either is fine; PS provider (`Get-ItemProperty`) is idiomatic in this codebase. Values needed: `ProductName`, `DisplayVersion` (20H2+; absent pre-1803), `ReleaseId` (legacy fallback pre-20H2), `CurrentBuild`/`CurrentBuildNumber`, `UBR` (patch revision — combine as `CurrentBuildNumber.UBR`), `EditionID`. |

## Installation

```powershell
# Nothing to install — everything is inbox on Windows 10/11 + PS 5.1.
# Required providers/namespaces (verify once on oldest target, e.g. Win10 1607/LTSC):
Get-CimClass -ClassName Win32_Processor, Win32_PhysicalMemory, Win32_VideoController, `
  Win32_LogicalDisk, Win32_BaseBoard, Win32_BIOS, Win32_ComputerSystem, Win32_OperatingSystem
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `Get-CimInstance` | `Get-WmiObject` (gwmi) | Never in new code — deprecated since PS 3.0, removed in PS 6+/7, slower, heavier objects. Only if back-porting to PS 2.0 (not a target: app requires 5.1 STA). |
| `Win32_LogicalDisk` (DriveType=3) | `Win32_DiskDrive` + partition associations | Only if per-*physical-disk* model/serial/media-type is later required. Costs 2–3 association traversals (`Win32_DiskDriveToDiskPartition`, `Win32_LogicalDiskToPartition`) — overkill for a free-space card. |
| `Win32_LogicalDisk` | `MSFT_PhysicalDisk` (`root\Microsoft\Windows\Storage`) / `Get-PhysicalDisk` | Only for NVMe health/SSD-vs-HDD media-type detail. Requires the Storage module import (slower startup, Server SKUs vary) — not needed for Size/FreeSpace display. |
| Registry CurrentVersion key | `Get-ComputerInfo` | Never for the live path — `Get-ComputerInfo` pulls the entire property bag (seconds, not ms). Registry read is ~1ms and the app needs only 6 values. |
| `Win32_PhysicalMemory.Capacity` sum | `Win32_ComputerSystem.TotalPhysicalMemory` alone | Use ComputerSystem as the fast single-value fallback, but MS docs explicitly warn it can under-report BIOS-reserved memory; the PhysicalMemory sum is the accurate total. Query both (both are cheap) and prefer the sum. |
| `MaxClockSpeed` | `CurrentClockSpeed` | `CurrentClockSpeed` reflects momentary throttling/turbo — wrong for a spec card. `MaxClockSpeed` is the rated speed. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `Get-WmiObject` / `gwmi` | Deprecated since PS 3.0; gone in PS 6+/7; returns heavier objects with system properties/methods; benchmarks slower than CIM | `Get-CimInstance -ClassName … -Property …` |
| `Win32_Product` | Triggers Windows Installer consistency/repair scan on enumeration — notoriously slow (minutes) and can mutate system state | Not needed at all for spec display; n/a |
| `Get-ComputerInfo` (unfiltered) | Aggregates dozens of sources; multi-second latency — kills live-on-open snappiness | Targeted `Get-CimInstance` per class + one registry read |
| Unfiltered `SELECT *` / bare `Get-CimInstance <class>` without `-Property` | Pulls every property including lazy/array ones over the provider boundary every refresh | Always pass `-Property` with only the columns the card renders |
| `Win32_VideoController.AdapterRAM` as exact VRAM on >4GB cards | `uint32` bytes — wraps at 4 GiB; shows 4,294,967,295 or truncated values on modern GPUs | Display with a ≥4 GB guard note; exact VRAM via DXGI is out of scope |
| Hard-coding `WOW6432Node` registry path | App runs 64-bit; hard-coding the 32-bit view reads stale/mirrored values | `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` in the native view |
| `ReleaseId` as the version label on 20H2+ | Deprecated after 20H2; frozen/missing on newer builds | `DisplayVersion` first, `ReleaseId` only as legacy fallback |
| `ProductName` alone to distinguish Win10 vs Win11 | Known Q&A issue: `ProductName`/`CurrentMajorVersionNumber` can still report "Windows 10" on Win11 builds | Combine `ProductName` + `CurrentBuildNumber` (≥22000 ⇒ Win11) + `DisplayVersion` |

## Stack Patterns by Variant

**If target includes Win10 1507–1709 (pre-DisplayVersion era):**
- Read `ReleaseId` as fallback when `DisplayVersion` is absent; `CurrentBuild`/`CurrentBuildNumber`+`UBR` still present.

**If machine has multiple GPUs (iGPU + dGPU):**
- Render all `Win32_VideoController` instances as rows; order discrete-first by non-empty `VideoProcessor`/`AdapterRAM` heuristics; never assume instance `[0]` is the interesting one.

**If `Win32_PhysicalMemory` returns zero instances (some VMs/stripped SMBIOS):**
- Fall back to `Win32_ComputerSystem.TotalPhysicalMemory` and omit the speed row.

**If live refresh ever exceeds ~500ms on spinning-HDD/low-end targets:**
- Cache static cards (CPU/board/BIOS/Windows) per session and re-query only `Win32_OperatingSystem` (free RAM) + `Win32_LogicalDisk` (free space) on each Home show. Static SMBIOS data cannot change without reboot/hardware swap.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `Get-CimInstance` | PS 5.1 `root/cimv2` on Win10 1607+/Win11/Server 2016+ | All 8 classes verified present since Vista/2008; `ConfiguredClockSpeed`/`SMBIOSMemoryType` need Win10+ (graceful `$null` on older) |
| Registry values | Win10 1803+ (`DisplayVersion`), all NT6+ (`ProductName`, `CurrentBuildNumber`, `UBR`, `EditionID`) | `UBR` absent on never-updated RTM images — default to `CurrentBuildNumber` alone |
| `Win32_LogicalDisk` DriveType=3 | All targets | Enum stable since Vista; no version risk |

## Query Performance (live-on-open budget)

| Query | Expected cost | Notes |
|-------|--------------|-------|
| Registry CurrentVersion read | ~1 ms | Cheapest; always first |
| `Win32_ComputerSystem`, `Win32_OperatingSystem`, `Win32_BIOS`, `Win32_BaseBoard` | fast (tens of ms each) | Singletons / single-instance; safe every refresh |
| `Win32_Processor`, `Win32_PhysicalMemory`, `Win32_VideoController` | fast–medium (~50–200 ms) | Use `-Property` to keep them in the fast band |
| `Win32_LogicalDisk -Filter "DriveType=3"` | fast–medium | `-Filter` pushes DriveType down to the provider; never `Where-Object` client-side on the full class |
| All 8 queries sequential in one runspace | target < 1 s total on HDD-era hardware | Run inside existing `Invoke-Code` runspace; render cards progressively if needed |

## Sources

- learn.microsoft.com `win32-processor` — Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed (HIGH)
- learn.microsoft.com `win32-computersystem` — TotalPhysicalMemory incl. BIOS-reserved caveat; Manufacturer/Model (HIGH)
- learn.microsoft.com `win32-physicalmemory` — Capacity, Speed, ConfiguredClockSpeed, SMBIOSMemoryType (HIGH)
- learn.microsoft.com `win32-videocontroller` — Name, AdapterRAM, DriverVersion, VideoProcessor (HIGH)
- learn.microsoft.com `win32-logicaldisk` — Size, FreeSpace, DriveType enum, FileSystem (HIGH)
- learn.microsoft.com `win32-baseboard` — Manufacturer, Product (HIGH)
- learn.microsoft.com `win32-bios` — SMBIOSBIOSVersion, ReleaseDate, UEFI-vs-legacy remark (HIGH)
- learn.microsoft.com `win32-operatingsystem` — Caption, Version, BuildNumber, OSArchitecture, FreePhysicalMemory/TotalVisibleMemorySize (HIGH)
- learn.microsoft.com PS101 ch.7 "Working with WMI" + SS64/PDQ CIM-vs-WMI writeups — Get-WmiObject deprecated since 3.0, CIM preferred/faster (HIGH for deprecation, MEDIUM for exact speed ratio)
- MS Q&A + community threads — DisplayVersion (20H2+) vs ReleaseId (legacy); ProductName Win10-on-Win11 quirk; CurrentBuildNumber.UBR full-build convention (MEDIUM — widely corroborated, registry values officially undocumented so pin behavior with a comment)

---
*Stack research for: AkariOS-Ultimate Home page (inbox-only spec queries)*
*Researched: 2026-10-08*
