# Roadmap: AkariOS-Ultimate

## Overview

Add a Home page to AkariOS-Ultimate — a PowerShell 5.1 + WPF tweaking tool — that displays live system specs (CPU, RAM, GPU, disk, motherboard/BIOS, Windows edition/build) in a card grid, refreshed every time Home is shown. The Home page is the default landing tab and provides read-only system information at a glance.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Spec Query Engine** - Background CIM/registry queries for CPU, RAM, and Windows specs with per-field fallback
- [ ] **Phase 2: Hardware Spec Cards** - GPU, disk, and motherboard/BIOS queries with hardware-diversity handling
- [ ] **Phase 3: Home Shell & Live Refresh** - Default landing tab, card grid layout, hostname header, and refresh-on-show
- [ ] **Phase 4: Home Polish & Documentation** - Copy-to-clipboard, health indicators, and README

## Phase Details

### Phase 1: Spec Query Engine

**Goal**: Reliable background queries for CPU, RAM, and Windows specs with per-field fallback
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: SPEC-01, SPEC-02, SPEC-06, REFR-02
**Success Criteria** (what must be TRUE):
  1. User sees CPU model, core/thread counts, and base speed queried from CIM
  2. User sees total RAM and used/free amounts computed from PhysicalMemory sum
  3. User sees Windows edition, friendly version, and full build number (incl. UBR)
  4. Individual fields that fail to query show "Not available" instead of blank or error

**Plans**: 1

### Phase 2: Hardware Spec Cards

**Goal**: GPU, disk, and motherboard/BIOS cards with hardware-diversity handling
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: SPEC-03, SPEC-04, SPEC-05
**Success Criteria** (what must be TRUE):
  1. User sees all GPU adapters with model, VRAM (with registry fallback for >4GB), and driver version
  2. User sees per-volume free/total space for fixed drives only
  3. User sees motherboard manufacturer/product, BIOS version, and release date
  4. Null/filler SMBIOS strings are filtered to "Not available"

**Plans**: 2 plans
- [x] 02-PLAN.md
- [ ] 02-02-PLAN.md — gap closure: BIOS release date in UTC + invariant culture (CR-01), 0 GB free (WR-01), label not counted in Disk status (WR-02)

### Phase 3: Home Shell & Live Refresh

**Goal**: Home as default landing with card grid, live refresh, and navigation
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: SHELL-01, SHELL-02, SHELL-03, REFR-01
**Success Criteria** (what must be TRUE):
  1. User lands on Home page by default on app launch
  2. User sees specs arranged in a fluid card grid matching the existing dark theme
  3. User sees a friendly hostname/manufacturer header on Home
  4. User sees freshly queried specs every time Home is shown without UI blocking

**Plans**: TBD
**UI hint**: yes

### Phase 4: Home Polish & Documentation

**Goal**: Copy-to-clipboard, health indicators, and project documentation
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: SPEC-07, SPEC-08, DOC-01
**Success Criteria** (what must be TRUE):
  1. User can copy the full spec text to the clipboard from Home
  2. User sees health-at-a-glance indicators (disk-free % / RAM pressure threshold coloring)
  3. README documents the AkariOS-Ultimate project including the Home page feature

**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Spec Query Engine | 1/1 | Complete | 2026-10-08 |
| 2. Hardware Spec Cards | 1/1 | In Progress | - |
| 3. Home Shell & Live Refresh | TBD | Not started | - |
| 4. Home Polish & Documentation | TBD | Not started | - |
