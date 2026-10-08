---
status: testing
phase: 02-hardware-spec-cards
source: [02-VERIFICATION.md]
started: 2026-10-08T15:10:00Z
updated: 2026-10-08T15:10:00Z
---

## Current Test

number: 1
name: SPEC-05 prohibition: BIOS date never differs from the firmware date
expected: |
  Accept the evidence: the 14-line zone/culture/DST/null matrix passes. A real Get-CimInstance Win32_BIOS read under swapped Eastern, Hawaiian and Line Islands zones with en-US, th-TH and ar-SA cultures returns 2026-08-18 every time. The live value equals the raw firmware string 20260818000000.000000+000. The verifier's verdict (not authoritative) is that the prohibition holds.
awaiting: user response

## Tests

### 1. SPEC-05 prohibition: BIOS date never differs from the firmware date
expected: Get-Specs formats ReleaseDate with ToUniversalTime() and InvariantCulture, and the result always equals the firmware's yyyyMMdd. Evidence: harness matrix PASS, an independent real-CIM zone/culture run, and a live value that matches the firmware. Verifier verdict: holds.
result: [pending]

### 2. SPEC-04 prohibition: no reported disk value is shown as failed, and free space is never invented
expected: FreeSpace 0 gives FreeGB 0 (a number, counted as a successful read). FreeSpace null gives 'Not available'. An unlabeled volume gets Label '' and does not affect _Status. A live run shows Disk=OK with an unlabeled C:. Edge for you to decide: a volume with Size = 0 still shows TotalGB 'Not available' and Partial, which the plan intends. Verifier verdict: holds.
result: [pending]

### 3. Get-Specs path is read-only
expected: $GetSpecsFunc contains only Get-CimInstance, Get-ItemProperty and Get-ChildItem reads. The grep for write commands returns 0. The harness timezone swap only changes the in-process TimeZoneInfo cache. Verifier verdict: holds.
result: [pending]

### 4. End-of-phase smoke test: launch the app and run a tweak and the tuners
expected: Run powershell -ExecutionPolicy Bypass -File Akari.ps1 elevated, click through the categories, run one Toggle tweak (Optimize, then Default), and run the Advanced-page Read/Apply tuners. The window opens with no error box, the rows, Set-Prio and Set-Svc behave as before, 'Done: ...' is logged, and the page re-enables after each run.
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
