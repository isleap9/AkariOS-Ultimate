---
title: Run the 7 Console-kind tweaks inside the app (no terminal)
created: 2026-10-09
area: Akari.ps1, Tweaks/Refresh.ps1, Tweaks/Graphics.ps1, Tweaks/Advanced.ps1
priority: high
---

## Problem

User report: clicking Autounattend and Updates and drivers block does nothing — no terminal opens.
User wants everything to run inside the app, never in a separate terminal.

Root cause: commit d38e5e1 ("Updated the repo") deleted the numbered folders (`1 Check/` … `8 Advanced/`).
Every `-Kind Console` tweak still calls `Start-Process powershell.exe -File "$Root\<Script>"`
(Akari.ps1 'Run' handler), so the child exits immediately on the missing file.

Affected (7): autounattend, updates-drivers-block (Refresh); driver-install-settings, driver-debloat (Graphics);
smt-ht, core1-thread1, priority (Advanced).

## Direction (user-approved)

Convert all 7 to in-app tweaks: recover each script body from `git show d38e5e1^:"<path>"`,
turn its Read-Host menu choices into `-Kind Group` `-Actions` sub-buttons (like `reinstall`),
run through Invoke-Code in the background runspace. Any free-text input (e.g. file/folder pick)
needs an in-app prompt rather than Read-Host. Remove the Console launch path once nothing uses it.
Schedule after Phase 4 completes (as a new phase).
