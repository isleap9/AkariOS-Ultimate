# Phase 3: Home Shell & Live Refresh - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-08
**Phase:** 03-home-shell-live-refresh
**Areas discussed:** Card grid look, Loading & refresh feel, Home header, Sidebar & search

---

## Card grid look

| Option | Description | Selected |
|--------|-------------|----------|
| CPU, GPU, RAM, Disk, Board, Windows | Six cards, hardware first | ✓ |
| Windows first, then hardware | OS identity up top | |
| Fold Board into header | Five cards | |

| Option | Description | Selected |
|--------|-------------|----------|
| Wrap fluidly | Fixed-width cards flow into columns | ✓ |
| Fixed 2 columns | | |
| Fixed 3 columns | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Label / value rows | Spec-sheet style | ✓ |
| Headline + detail line | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Stacked inside one card | Multi GPU/drive blocks in one card | ✓ |
| One card per item | | |

**Notes:** User raised a tweak progress bar under the log — deferred as its own phase.

---

## Loading & refresh feel

| Option | Description | Selected |
|--------|-------------|----------|
| Last values, then update | Dimmed previous values; "Loading…" first visit | ✓ |
| "Loading…" every time | | |
| Thin progress bar under the log | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Silent | Errors only | ✓ |
| Log it | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Show last values, refresh after | Auto re-read when tweak finishes | ✓ |
| Read specs alongside the tweak | | |
| Show a 'waiting for tweak' note | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Fully usable | Nothing greys out | ✓ |
| Lock until loaded | | |

---

## Home header

| Option | Description | Selected |
|--------|-------------|----------|
| PC name + maker/model | Big name, muted "Maker · Model" | ✓ |
| PC name only | | |
| 'Home' + PC name below | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Use motherboard name instead | Fallback on SMBIOS filler | ✓ |
| Hide the line | | |

---

## Sidebar & search

| Option | Description | Selected |
|--------|-------------|----------|
| Top, with a gap below | | ✓ |
| Top, no separation | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Search tweaks as usual | | ✓ |
| Hide search on Home | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, any time Home appears | Launch, click, clear search | ✓ |
| Only when clicking Home | | |

---

## Claude's Discretion

Card sizing/spacing, number formatting, failed-field visuals, background-read mechanism, dimming style.

## Deferred Ideas

- Progress bar under the log while a tweak applies — own phase.
