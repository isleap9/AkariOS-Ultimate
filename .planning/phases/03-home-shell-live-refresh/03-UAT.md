---
status: testing
phase: 03-home-shell-live-refresh
source: [03-VERIFICATION.md]
started: 2026-10-08T20:36:11Z
updated: 2026-10-08T20:36:11Z
---

## Current Test

number: 1
name: Open the app.
expected: |
  It opens on Home. Home is the first item in the left menu and is selected, with a thin line under it and Check below that. Clicking the thin line does nothing.
awaiting: user response

## Tests

### 1. Open the app.
expected: It opens on Home. Home is the first item in the left menu and is selected, with a thin line under it and Check below that. Clicking the thin line does nothing.
result: [pending]

### 2. Look at the Home page at its normal size.
expected: Six cards in this order: CPU, GPU, RAM, Disk, Board, Windows. They sit in three columns, and cards in the same row are the same height. They have the same dark look and colours as the rest of the app.
result: [pending]

### 3. Make the window as narrow as it goes.
expected: The cards sit in two columns. You can scroll the page up and down, but it never scrolls sideways. Long names wrap onto more lines inside their card and never stick out.
result: [pending]

### 4. Read the numbers on the cards.
expected: They use a dot, not a comma, like 3.80 GHz and 31.9 GB. The Disk card shows only the Windows drive (C:). If your PC has more than one graphics card, they all appear in the GPU card with a thin line between them.
result: [pending]

### 5. Look at the top of Home.
expected: Your computer's name is in large text. Under it is your PC maker and model, which on this PC reads ASUSTeK COMPUTER INC. · TUF GAMING B550-PLUS. When the window is narrow, that line stays on one line and ends in … if it does not fit. Hovering over it shows the full text.
result: [pending]

### 6. Go to another page, then click Home again.
expected: The cards look faded for a moment while they update, then go back to normal. While they are faded you can still click the menu, type in the search box and start a tweak on another page. No new message appears at the bottom of the window.
result: [pending]

### 7. Start a tweak that takes a while, then click Home straight away.
expected: The cards are still there, faded. When the tweak finishes, they go back to normal on their own.
result: [pending]

### 8. On Home, type something in the search box, then clear it.
expected: While you type, Home goes away and matching results show. When you clear the box, Home comes back with its cards.
result: [pending]

### 9. Click through a few of the other pages (Check, Windows, Advanced).
expected: They look and work exactly as before.
result: [pending]

## Summary

total: 9
passed: 0
issues: 0
pending: 9
skipped: 0
blocked: 0

## Gaps
