---
status: testing
phase: 04-home-polish-documentation
source: [04-VERIFICATION.md]
started: 2026-10-09T10:02:02Z
updated: 2026-10-09T10:02:02Z
---

## Current Test

number: 1
name: Copy specs button
expected: |
  On Home, click "Copy specs". The button briefly says "Copied", then goes back to "Copy specs".
  Paste into Notepad: you get a plain list of your PC's specs (CPU, memory, graphics, disk, motherboard, Windows).
awaiting: user response

## Tests

### 1. Copy specs button
expected: Clicking "Copy specs" shows "Copied" for about 2 seconds; pasting into Notepad gives the full spec list matching the cards.
result: [pending]

### 2. Health colours
expected: Disk free space turns amber when under 15% free and red under 10%; RAM used turns amber above 80% and red above 90%. Everything else stays the normal colour. (If your PC is healthy, nothing is coloured — that is correct.)
result: [pending]

### 3. README
expected: The README on GitHub reads well, describes the Home page and the categories, and the install line still works.
result: [pending]

### 4. Home never stays faded
expected: Switch between Home and other pages several times. Home always comes back fully visible with values, never stuck faded or blank.
result: [pending]

### 5. CPU card and tweaks still normal
expected: The CPU card looks the same as before (no extra "Sockets" line on a normal single-CPU PC). Running any tweak still shows its messages in the log and a "Done" line.
result: [pending]

### 6. Copy failed message (optional)
expected: If another program is locking the clipboard, clicking "Copy specs" shows "Copy failed" instead of crashing. Fine to skip.
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0
blocked: 0

## Gaps
