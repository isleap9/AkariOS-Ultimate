# Requirements: AkariOS-Ultimate Home Page

**Defined:** 2026-10-08
**Core Value:** The Home page shows accurate, live system specs at a glance — if the specs are wrong or stale, the page fails its purpose.

## v1 Requirements

### Spec Cards

- [x] **SPEC-01**: User sees CPU card with model, core/thread counts, and base speed
- [x] **SPEC-02**: User sees RAM card with total installed memory and used/free amounts in GB
- [ ] **SPEC-03**: User sees GPU card listing all adapters with model, VRAM, and driver version
- [ ] **SPEC-04**: User sees disk card with per-volume free/total space for fixed drives
- [ ] **SPEC-05**: User sees motherboard + BIOS card with board manufacturer/product, BIOS version, and release date
- [x] **SPEC-06**: User sees Windows card with edition, friendly version, and full build number (incl. UBR)
- [ ] **SPEC-07**: User can copy the full spec text to the clipboard from Home
- [ ] **SPEC-08**: User sees health-at-a-glance indicators (disk-free % / RAM pressure threshold coloring)

### Shell & Navigation

- [ ] **SHELL-01**: User lands on the Home page by default on app launch
- [ ] **SHELL-02**: User sees specs arranged in a fluid card grid matching the existing dark theme
- [ ] **SHELL-03**: User sees a friendly hostname/manufacturer header on Home

### Refresh & Robustness

- [ ] **REFR-01**: User sees freshly queried specs every time Home is shown (background query with loading/placeholder state, UI never blocks)
- [x] **REFR-02**: User sees "Not available" for individual fields that fail to query instead of a blank card or error

### Documentation

- [ ] **DOC-01**: README is revamped to document the AkariOS-Ultimate project including the new Home page feature

## v2 Requirements

### Spec Depth

- **SPEC-09**: User can expand a card for per-component detail (e.g. per-DIMM RAM slots)

### Monitoring

- **MON-01**: User sees CPU/GPU temperature readout on Home

## Out of Scope

| Feature | Reason |
|---------|--------|
| Windows update status / pending-reboot flag | Not requested; defer beyond v2 |
| License / activation state | Not requested; defer beyond v2 |
| Install date / uptime display | Not requested; defer beyond v2 |
| Hub shortcuts to Check/Refresh pages | User chose plain default landing, not a hub |
| Spec editing or actions from Home | Home is read-only overview by design |
| Real-time sensor polling graphs | Monitoring belongs to specialist tools; refresh-on-show is the chosen middle ground |
| Benchmarks / stress tests | Specialist-tool territory, not an overview page |
| Network adapter card | Explicitly excluded; no user demand |
| Temperature via third-party drivers | No reliable inbox source; forbidden dependency |
| Cross-platform / PowerShell 7 support | App is locked to Windows PowerShell 5.1 STA + WPF |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SPEC-01 | Phase 1 | Complete |
| SPEC-02 | Phase 1 | Complete |
| SPEC-03 | Phase 2 | Gaps Found |
| SPEC-04 | Phase 2 | Gaps Found |
| SPEC-05 | Phase 2 | Gaps Found |
| SPEC-06 | Phase 1 | Complete |
| SPEC-07 | Phase 4 | Pending |
| SPEC-08 | Phase 4 | Pending |
| SHELL-01 | Phase 3 | Pending |
| SHELL-02 | Phase 3 | Pending |
| SHELL-03 | Phase 3 | Pending |
| REFR-01 | Phase 3 | Pending |
| REFR-02 | Phase 1 | Complete |
| DOC-01 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0 ✓

---
*Requirements defined: 2026-10-08*
*Last updated: 2026-10-08 after initial definition*
