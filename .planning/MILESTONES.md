# Milestones

## v1.0 — Home Page

**Shipped:** 2026-10-09
**Phases:** 1-4 | **Plans:** 8 | **Requirements:** 14/14

A Home page for AkariOS-Ultimate that displays live system specs (CPU, RAM, GPU, disk, motherboard/BIOS, Windows edition/build) in a card grid, refreshed every time Home is shown. The Home page is the default landing tab and provides read-only system information at a glance.

**Key accomplishments:**
- Background CIM/registry spec query engine with per-field fallback
- GPU/Disk/Motherboard cards with hardware-diversity handling (VRAM registry fallback, SMBIOS filtering)
- Home shell with 6-card grid, hostname header, live refresh with loading/dimmed/failed states
- Copy-to-clipboard, health-at-a-glance indicators, README
- 20s watchdog with hung-read recovery
- All 7 Console tweaks converted to in-app Group tweaks

**Archive:** `.planning/milestones/v1.0-ROADMAP.md`
