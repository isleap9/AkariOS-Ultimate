# Codebase Concerns

**Analysis Date:** 2026-10-08

> Scope: full repo. Focus: risks of registry tweaks, admin elevation, reboot requirements, IWR remote execution, revert options.

## Tech Debt

**Run-Trusted (TrustedInstaller hijack) duplicated everywhere, no shared module:**
- Issue: The `Run-Trusted` function (stop TrustedInstaller service, `sc.exe config TrustedInstaller binPath= "cmd.exe /c powershell.exe -encodedcommand ..."`, `sc.exe start`, restore binPath, kill service) is copy-pasted as a string/heredoc into every Defender/services/GameBar tweak instead of living in one helper. `Akari.ps1` defines `$Helpers` with `Run-Trusted`/`Set-Reg`/`Remove-Reg` for the background runspace (`Akari.ps1:70-100`), but `Tweaks/Advanced.ps1` and `Tweaks/Windows.ps1` re-define their own inline copies (e.g. `Tweaks/Advanced.ps1:12-36`, `Tweaks/Advanced.ps1:231-255`, `Tweaks/Windows.ps1:5700-5724`).
- Files: `Akari.ps1`, `Tweaks/Advanced.ps1`, `Tweaks/Windows.ps1`
- Impact: Any fix to the elevation technique (e.g. restoring `binPath` quoting, handling failure mid-hijack) must be applied in ~8 places; drift means some tweaks restore the service and some do not if `sc.exe start` fails.
- Fix approach: Keep only the `Akari.ps1:$Helpers` definition; delete inline copies and rely on the injected runspace helpers. Add a `try/finally` that always restores `binPath` even when `sc.exe start` throws.

**ControlSet001 hard-coded instead of CurrentControlSet:**
- Issue: ~hundreds of registry writes target `HKLM\SYSTEM\ControlSet001\...` (services `Start` values, `FeatureManagement\Overrides`, `Enum\ACPI|HID|PCI|USB|SCSI|NVME`, power settings) while reads elsewhere use `CurrentControlSet`. `ControlSet001` is the last-known-good copy, not necessarily the live control set.
- Files: `Tweaks/Advanced.ps1` (services on/off reg blobs at `Tweaks/Advanced.ps1:1160-2001`, Defender keys at `Tweaks/Advanced.ps1:108-158`), `Tweaks/Windows.ps1:64-73`, `Tweaks/Windows.ps1:4798-4991` (Enum walks), `Tweaks/Graphics.ps1:273-1047`
- Impact: On machines booted from `ControlSet002` or after failed-boot fallback, tweaks silently write to the inactive set and appear to do nothing; reboot flows then "revert" the wrong hive.
- Fix approach: Replace all `ControlSet001` writes with `CurrentControlSet`, or resolve the live set once (`(Get-Item HKLM:\SYSTEM\Select).Current`) and template it.

**Error suppression hides failures (`>nul 2>&1`, `SilentlyContinue`):**
- Issue: Virtually every `reg add/delete`, `bcdedit`, `schtasks`, `sc stop/delete` is suffixed `>nul 2>&1` and piped `| Out-Null`, with `-ErrorAction SilentlyContinue`. `Invoke-Code` in `Akari.ps1:223-235` only surfaces stdout text via `LogQueue`; exit codes from `cmd /c reg ...` are never checked.
- Files: `Tweaks/Advanced.ps1`, `Tweaks/Windows.ps1`, `Tweaks/Graphics.ps1`, `Tweaks/Hardware.ps1`, `Akari.ps1:223-255`
- Impact: Failed TrustedInstaller writes, denied `Enum` writes, or missing keys look like success in the UI log ("Done: ..."). Planner/executor cannot trust log output as verification.
- Fix approach: Add a `Invoke-Reg` helper that checks `$LASTEXITCODE` and `Write-Log`s failures; keep `SilentlyContinue` only for best-effort cleanup.

**State tracking is write-only memory (`state.json` + almost no `Detect`):**
- Issue: `Akari.ps1:59-67` persists `{ tweakId: bool }` to `%LOCALAPPDATA%\Akari\state.json` on every Toggle Apply/Revert (`Akari.ps1:248`), and `Get-State` (`Akari.ps1:175-181`) prefers `Detect` scriptblocks but only one tweak (`widgets`, `Tweaks/Windows.ps1:809-811`) defines one. All other dots reflect "what Akari last clicked", not machine state.
- Files: `Akari.ps1:175-192`, `Tweaks/*.ps1` (absence of `-Detect`)
- Impact: Manual changes (Settings app, Windows Update resetting Defender keys, `powercfg -restoredefaultschemes`) desync the UI dot; users believe a mitigation is active when it is not, or revert something already default.
- Fix approach: Add lightweight `Detect` per Toggle (read the same `Start`/policy value the Apply writes); fall back to `state.json` only when detection is ambiguous.

**Generated-file drift (`Tweaks/*.ps1` GENERATED from numbered folders):**
- Issue: Headers say `Tweaks/*.ps1` are GENERATED from `1 Check\`, `2 Refresh\`, ... `8 Advanced\` scripts, but there is no generator script in the repo. The numbered-folder originals (e.g. `8 Advanced\1 Defender.ps1`) and `Tweaks/Advanced.ps1` must be kept in sync by hand.
- Files: `Tweaks/*.ps1`, `1 Check\*.ps1`, `2 Refresh\*.ps1`, `5 Graphics\*.ps1`, `8 Advanced\*.ps1`
- Impact: Fixes applied to one copy silently diverge; reviewers cannot tell which is canonical.
- Fix approach: Commit a generator (or delete one side and dot-source the other). Until then treat `Tweaks/*.ps1` as canonical because that is what `Akari.ps1:56` loads.

## Known Bugs

**Revert wipes instead of restoring (destructive "Default"):**
- Symptoms: Several Revert blocks delete whole keys rather than restoring captured originals: `download-warning` Revert deletes all of `HKLM\SOFTWARE\Policies\Microsoft\Internet Explorer` (`Tweaks/Advanced.ps1:486`); `context-menu` Revert deletes all of `HKLM\...\Shell Extensions\Blocked` (`Tweaks/Windows.ps1:626`); `write-cache` Revert deletes the entire `Disk` subkey (`Tweaks/Windows.ps1:5155-5164`); `autoruns-check` Apply deletes and recreates all `Run`/`RunOnce` keys and Startup folders (`Tweaks/Windows.ps1:6073-6091`).
- Files: `Tweaks/Advanced.ps1:484-489`, `Tweaks/Windows.ps1:581-640`, `Tweaks/Windows.ps1:5129-5166`, `Tweaks/Windows.ps1:6030-6127`
- Trigger: Click Optimize then Default on those rows.
- Workaround: Create a restore point first (`restore-point` tweak, `Tweaks/Windows.ps1:6154-6175`). Do not treat Default as non-destructive.

**Bloatware "Remove all" has no true revert:**
- Symptoms: `bloatware` Apply (`Tweaks/Windows.ps1:863-1057`) removes AppX packages (`Remove-AppxPackage`), Windows capabilities (`Remove-WindowsCapability`), optional features (`Disable-WindowsOptionalFeature -NoRestart`), `brltty`, GameInput MSI, OneDrive (including scheduled tasks), `mstsc /Uninstall`, SnippingTool. The Group's sub-actions only reinstall Store / all UWP / open Optional Features — capabilities, legacy features, OneDrive, and task deletions are not restored.
- Files: `Tweaks/Windows.ps1:863-1150`
- Trigger: One click on "Remove all" with only the generic confirm dialog.
- Workaround: None in-app; requires `Install all UWP apps` + manual Optional Features reinstall + OneDrive installer. Treat as one-way.

**Power-plan Apply deletes every power scheme:**
- Symptoms: `power-plan` Apply (`Tweaks/Windows.ps1:5168-5383`) duplicates the Ultimate Performance scheme to a fixed GUID then deletes *every* enumerated scheme (`powercfg /delete $plan`), disables hibernate, removes Lock/Sleep/Fast Boot, sets battery thresholds to 0%/do-nothing on laptops.
- Files: `Tweaks/Windows.ps1:5171-5199`, `Tweaks/Windows.ps1:5343-5380`
- Trigger: Apply on a laptop; unexpected shutdown at 0% with no warning because critical/low actions are "do nothing".
- Workaround: Revert runs `powercfg -restoredefaultschemes` (`Tweaks/Windows.ps1:5386`) — verify schemes return before relying on battery.

**Timer-resolution service drops a binary in `C:\Windows` and compiles with `csc.exe`:**
- Symptoms: `timer-resolution` Apply writes `C:\Windows\SetTimerResolutionService.cs`, compiles to `C:\Windows\SetTimerResolutionService.exe`, installs an auto-start `LocalSystem` service named `STR` / `Set Timer Resolution Service` (`Tweaks/Windows.ps1:5422-5646`). Fails silently when .NET Framework `csc.exe` path differs; leaves stale `.cs` on compile failure only partially cleaned.
- Files: `Tweaks/Windows.ps1:5623-5646`
- Trigger: Apply on machines without `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`.
- Workaround: Revert deletes the service and exe (`Tweaks/Windows.ps1:5648-5662`); check `services.msc` for `STR` if Apply reported success but Task Manager shows no change.

**Defender disable/enable `MitigationOptions` values are inconsistent:**
- Symptoms: Disable writes `MitigationOptions` `2222220000010000...` (`Tweaks/Advanced.ps1:104`), Revert writes `1111110000010000...` (`Tweaks/Advanced.ps1:323`), while Windows `defender` optimize writes `2222220000020000...` (`Tweaks/Windows.ps1:5792`) and its revert writes `1111110000010000...` (`Tweaks/Windows.ps1:5968`). These are opaque binary exploit-protection bitmaps with no comment on bit meaning.
- Files: `Tweaks/Advanced.ps1:104`, `Tweaks/Advanced.ps1:323`, `Tweaks/Windows.ps1:5792`, `Tweaks/Windows.ps1:5968`
- Trigger: Toggling Defender off/on/optimize in different orders leaves an unknown combination.
- Workaround: None; record the pre-tweak binary value before changing.

**Keyboard-shortcuts Apply remaps Esc to `=` and disables `hidserv`:**
- Symptoms: Apply writes a `Scancode Map` that rebinds Esc (`Tweaks/Advanced.ps1:1082`) and sets `hidserv Start=4`; users who do not read the Write-Host warning lose Esc and media keys until revert + reboot.
- Files: `Tweaks/Advanced.ps1:1060-1096`
- Trigger: One click, no `Confirm` prompt despite the severity.
- Workaround: Revert deletes `Scancode Map` (`Tweaks/Advanced.ps1:1095`); reboot required for the map to take effect (not stated in UI).

## Security Considerations

**IWR remote execution with no integrity check (primary infection vector):**
- Risk: The documented install is `iwr 'https://github.com/isleap9/AkariOS-Ultimate/raw/refs/heads/main/IWR.ps1' -useb | iex` (`README.md:13`). `IWR.ps1:40` then downloads `.../archive/refs/heads/main.zip` over TLS but never verifies hash/signature; every `Installers`/`Check`/`ReBar` action further `IWR`s unsigned exes from `github.com/isleap9/AkariOS-Files/releases/download/Files/*` (`Tweaks/Installers.ps1:10-887`, `Tweaks/Check.ps1:78-176`, `Tweaks/Advanced.ps1:564-925`) into `%SystemRoot%\Temp` or `Program Files` and executes them. A compromised release asset, DNS/TLS-intercepted mirror, or typosquatted fork runs as admin.
- Files: `README.md:13`, `IWR.ps1:40`, `Tweaks/Installers.ps1`, `Tweaks/Check.ps1:78-181`, `Tweaks/Advanced.ps1:564-925`, `Tweaks/Windows.ps1:6108`
- Current mitigation: TLS only. No `Get-FileHash` pin, no signature check, no version pin (always `main`/`latest`).
- Recommendations: Pin per-file SHA256 in the script and verify before `Start-Process`; or vendor binaries into the release. At minimum add `-UseBasicParsing` + hash check helper and fail closed (`return` before execute). Never pipe `iwr | iex` from `main` in docs — pin a tag/commit.

**Permanent `Unrestricted` execution policy + file association hijack:**
- Risk: `IWR.ps1:52-54` and `AllowScripts.cmd:28-32` set `HKCR\Applications\powershell.exe\shell\open\command` to `powershell.exe -NoLogo -ExecutionPolicy unrestricted -File "%1"` and force `HKCU`+`HKLM\...\PowerShell\1\ShellIds\Microsoft.PowerShell\ExecutionPolicy = Unrestricted`. This persists after Akari exits and lets any double-clicked `.ps1` run without prompt.
- Files: `IWR.ps1:52-54`, `AllowScripts.cmd:25-38`
- Current mitigation: `AllowScripts.cmd:40-51` offers a Scripts-Off mode, but the UI never calls it and IWR never reverts.
- Recommendations: Scope Bypass to the single launch (`-ExecutionPolicy Bypass` process arg, already done in `Akari.ps1:11` and `IWR.ps1:66`) and stop writing machine-wide `Unrestricted`. If double-click support is needed, document it as opt-in with a revert button.

**Whole-app admin + silent elevation chain:**
- Risk: `Akari.ps1:6-13` re-launches itself with `-Verb RunAs` (admin) + `-ExecutionPolicy Bypass` on every start; `IWR.ps1:17-24` self-elevates *before* download so the UAC prompt appears before any context. Every tweak then runs as admin in a background runspace (`Akari.ps1:223-235`), and Defender/services tweaks escalate further to TrustedInstaller via `sc.exe config`. A single misclicked row (Defender off, Services off, Bloatware remove-all) executes with the highest privilege.
- Files: `Akari.ps1:6-13`, `IWR.ps1:17-24`, `Akari.ps1:223-235`
- Current mitigation: `Confirm-Run` dialog, but only 4 of ~100 tweaks set `-Confirm` (bloatware, edge-webview, cleanup, to-bios). Defender-off, firewall-off, UAC-off, services-off, DEP-off have no confirm.
- Recommendations: Add `-Confirm` to every `Risk Advanced` tweak and every `shutdown`/`bcdedit` flow; consider a per-launch (non-admin) UI that elevates only the worker runspace.

**Defender / Firewall / SmartScreen / VBS / LSA / Vulnerable-driver-blocklist disablement:**
- Risk: One-click toggles disable layered protections: Defender real-time + TamperProtection=4 + services `Start=4` + `smartscreen.exe` moved out of System32 (`Tweaks/Advanced.ps1:3-223`); Firewall profiles `EnableFirewall=0` (`Tweaks/Advanced.ps1:437-448`); SmartScreen/PUA/SmartLocker off; `RunAsPPL=0`, `VulnerableDriverBlocklistEnable=0`, HVCI `Enabled=0`, `bcdedit /deletevalue hypervisorlaunchtype` (`Tweaks/Advanced.ps1:104-158`); Spectre/Meltdown `FeatureSettingsOverride=3` (`Tweaks/Advanced.ps1:450-461`); DEP `nx AlwaysOff` (`Tweaks/Advanced.ps1:463-474`); UAC `EnableLUA=0` (`Tweaks/Windows.ps1:5664-5673`); Edge/WebView uninstall (`Tweaks/Windows.ps1:1512-...`). Descriptions understate blast radius ("Turn Windows Defender off", "Turn UAC off").
- Files: `Tweaks/Advanced.ps1:3-474`, `Tweaks/Windows.ps1:1512-1670`, `Tweaks/Windows.ps1:5664-5673`, `Tweaks/Windows.ps1:5682-6028`
- Current mitigation: Risk labels (`Advanced`/`Caution`) and red badges in `Akari.ps1:127-165`; no confirm, no restore-point gate except `services`.
- Recommendations: Require typed or double confirm + automatic restore point for all security-surface tweaks; link revert limitations (Defender-Default-Definitions cannot be re-enabled — see `Tweaks/Advanced.ps1:390` comment) in the description text.

**HTTP-adjacent risks: `Test-Connection 8.8.8.8` gate + Google search with board serial:**
- Risk: Internet checks ping `8.8.8.8` in cleartext ICMP before every download (`Tweaks/Installers.ps1`, `Tweaks/Check.ps1`, `Tweaks/Advanced.ps1:560`); `bios-check`/`network-driver` exfiltrate the Win32_BaseBoard product string into a Google search URL (`Tweaks/Check.ps1:10-15`, `Tweaks/Refresh.ps1:50-54`).
- Files: `Tweaks/Check.ps1:6-15`, `Tweaks/Refresh.ps1:49-54`
- Current mitigation: None needed functionally, but privacy-sensitive.
- Recommendations: Replace ping gate with the download's own try/catch; warn that board model is sent to Google.

## Performance Bottlenecks

**Recursive `Enum` walks on every power/wake tweak:**
- Problem: `devmgr-power` enumerates all of `HKLM\SYSTEM\ControlSet001\Enum\{ACPI,HID,PCI,USB}` twice (Device Parameters + WDF) plus four more full walks for `WaitWakeEnabled` — each spawning a `cmd /c reg add` per device (`Tweaks/Windows.ps1:4792-4891`). Same pattern in `write-cache` (`Enum\SCSI|NVME`), `netadapter-power`, ULPS/GPU class walks.
- Files: `Tweaks/Windows.ps1:4792-4991`, `Tweaks/Windows.ps1:5129-5148`, `Tweaks/Advanced.ps1:1002-1047`, `Tweaks/Graphics.ps1:279-1047`
- Cause: One process per value instead of batching via .NET `RegistryKey` or a single `.reg` import.
- Improvement path: Build one `.reg` file in memory and import once (as Defender/services tweaks already do), or use `Set-ItemProperty` in-process. Keep per-device logging but not per-device processes.

**Single-threaded background runspace + 150 ms UI pump:**
- Problem: `Invoke-Code` allows one job at a time (`$script:Busy` gate, `Akari.ps1:224`); long installs (DDU, Media Creation Tool, OCCT downloads) block all other rows while the `DispatcherTimer` drains the log queue every 150 ms (`Akari.ps1:237-256`).
- Files: `Akari.ps1:220-256`
- Cause: By design (avoid concurrent registry writes) but no queue — extra clicks are silently dropped (`if ($script:Busy) { return }`).
- Improvement path: Replace silent drop with a pending-action queue or disable buttons with a "busy" tooltip; document that only one tweak runs at a time.

**Broad `Get-AppXPackage -AllUsers` / capability scans:**
- Problem: Bloatware remove-all and Store reinstall enumerate every AppX/capability/optional feature with per-item try/catch (`Tweaks/Windows.ps1:870-952`); on slow disks this runs for minutes with only "Please wait..." feedback.
- Files: `Tweaks/Windows.ps1:870-952`, `Tweaks/Windows.ps1:1124-1132`
- Cause: No filtering at provider level, no progress reporting.
- Improvement path: Stream progress lines to `Write-Log` per batch (as `Helpers` already supports) instead of one final Done.

## Fragile Areas

**Double-reboot safeboot flows (Defender, Services, Driver clean/install):**
- Files: `Tweaks/Advanced.ps1:189-222` (defender off), `Tweaks/Advanced.ps1:401-434` (defender on), `Tweaks/Advanced.ps1:2003-2036` (services off), `Tweaks/Graphics.ps1:79-192` (DDU/driver)
- Why fragile: Pattern is `write RunOnce *.ps1 to SystemRoot\Temp` → `bcdedit /set {current} safeboot minimal` → `shutdown -r -t 00` (5 s sleep, no save check) → RunOnce payload runs in safe mode → payload does `bcdedit /deletevalue {current} safeboot` → `shutdown -r`. Any interruption (power loss, user cancels RunOnce, Defender TamperProtection blocks the write, `Temp` cleaned between boots) leaves the machine stuck in Safe Boot loop or half-disabled protection with `smartscreen.exe` moved (`C:\Windows\smartscreen.exe` vs `System32\smartscreen.exe`).
- Safe modification: Never change one half of the pair; always edit Apply+Revert payloads together and keep the `RunOnce` name (`*defenderdisable`, `*servicesoff`) unique. Test in a VM snapshot.
- Test coverage: None automated; manual VM reboot test only.

**`bcdedit` + `shutdown -r -t 00` with 5-second fuse and selective confirms:**
- Files: `Tweaks/Advanced.ps1` (12 `shutdown` call sites), `Tweaks/Graphics.ps1:98-192`, `Tweaks/Windows.ps1:5825-6027`, `Tweaks/Refresh.ps1:57-65`, `Tweaks/Check.ps1:39-43`
- Why fragile: `shutdown -r -t 00` gives the user zero seconds after a 5 s `Start-Sleep`; only `to-bios` shows the unsaved-work confirm (`Tweaks/Refresh.ps1:57`). Defender-flows reboot *twice*. `bios-check` reboots straight to firmware (`shutdown /r /fw /t 0`).
- Safe modification: Route every `shutdown`/`bcdedit` through a helper that calls `Confirm-Run` first; change `-t 00` to `-t 30` with abort instructions, or at minimum reuse the existing to-bios confirm string.
- Test coverage: No tests; grep `shutdown` before release to audit new call sites.

**Services on/off 400-line registry blobs:**
- Files: `Tweaks/Advanced.ps1:1156-2001` (off), `Tweaks/Advanced.ps1:2095-...` (on)
- Why fragile: ~250 services pinned to `Start=2/3/4` by name; Windows 10 vs 11 vs Server have different service sets; a typo'd `Start=4` on `PlugPlay`, `Power`, `RpcSs`, `DcomLaunch`, `Winmgmt`, `gpsvc`, `CryptSvc` = unbootable or no-login. The "untouched" comment list (camsvc, netprofm, dnscache, sppsvc...) is advisory text, not enforced. Revert blob is *not* a snapshot — it is a second hardcoded list that may not match the machine's original OEM values.
- Safe modification: Snapshot current `Start` values to a `.reg`/JSON backup before writing (as `account-pictures` does for images at `Tweaks/Windows.ps1:761-763`); revert = re-import snapshot. Never add a service to the off-list without booting both W10 and W11 in a VM.
- Test coverage: None; the only safety net is the pre-apply restore point (`Checkpoint-Computer`), which itself fails silently on Home SKU or disabled System Protection.

**AppX/Edge/WebView removal breaks dependents:**
- Files: `Tweaks/Windows.ps1:863-1057` (bloatware), `Tweaks/Windows.ps1:1320-1510` (gamebar), `Tweaks/Windows.ps1:1512-1670` (edge-webview), `Tweaks/Setup.ps1:138-205` (edge-settings deletes Edge services + scheduled tasks)
- Why fragile: Edge removal also deletes all `*Edge*` services/tasks and the IEToEdge BHO; WebView2 removal breaks any app hosting WebView2 (Store, Copilot, widgets, third-party). GameBar removal touches `Windows.Gaming.GameBar.PresenceServer` activation via TrustedInstaller. Comments admit breakage (`# breaks file explorer`, `# breaks start menu`, `# windows 11 breaks msi installers if removed`) yet exclusions are name-pattern heuristics (`-notlike '*CBS*'`), not dependency checks.
- Safe modification: Keep the exclusion lists; add `Get-AppxPackage` dry-run output to the log before deleting; require the existing `-Confirm` on edge-webview for any new removal tweak.
- Test coverage: None.

**Registry-file import via temp `.reg` + `regedit.exe /S`:**
- Files: `Tweaks/Windows.ps1:80-83` (taskbar), `Tweaks/Windows.ps1:343-346`, `Tweaks/Advanced.ps1:2003-2009` + `Run-Trusted` variant
- Why fragile: `.reg` content is built with PowerShell here-strings into `%SystemRoot%\Temp\*.reg`; encoding (Unicode vs ASCII), `[-KEY]` delete syntax, and `hex:` line continuations must be exact or `regedit /S` silently skips lines. Temp files are never cleaned and can be re-imported by a later tweak version accidentally.
- Safe modification: Prefer `Set-ItemProperty`/`Remove-ItemProperty` (already used in `power-plan`, `updates-pause`) so failures throw; when `.reg` is unavoidable, verify with `reg query` after import.
- Test coverage: None.

## Scaling Limits

**Single-user, single-machine imperative script — no fleet story:**
- Current capacity: One admin on one machine clicking rows; `state.json` is per-user (`%LOCALAPPDATA%\Akari`), but most writes are HKLM (machine-wide) — two users on one box see different dots for the same machine state.
- Limit: No idempotency (re-Apply duplicates shortcuts, re-imports `.nip` profiles, re-deletes keys), no dry-run, no export/import of "my configuration", no logging beyond a local `akari.log` (`Akari.ps1:24-28`).
- Scaling path: Make Apply idempotent (test-before-write), add "Export applied IDs" from `state.json`, and centralize `Write-ErrLog`/`Add-Log` so a future CLI can run headless.

## Dependencies at Risk

**`AkariOS-Files` release bucket (single maintainer, no mirror):**
- Risk: ~40 installer/check payloads and both Media Creation Tools resolve to `github.com/isleap9/AkariOS-Files/releases/download/Files/*`. If the bucket is renamed, rate-limited, DMCA'd, or serves a stale CVE'd build (Chrome, Firefox, 7-Zip, DDU, Edge, VC++ redists listed in `LICENSE`), every Installers row 404s or installs vulnerable software. Filenames are generic (`edge.exe`, `chrome.exe`, `cpuz.exe`) with no version in the URL.
- Impact: Installers category fully breaks; no fallback URL.
- Migration plan: Vendor hashes per file (see Security) + add a second mirror or fall back to winget (`winget install --id ...`) which is already the OS-native path.

**External vendor installers pulled at click-time (no pin):**
- Risk: One Firefox path pulls `https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi` (`Tweaks/Installers.ps1:303`); Brave/Chrome force-install extensions by ID from the web store (`Tweaks/Installers.ps1:85`, `Tweaks/Installers.ps1:396`). Store/Edge policy keys assume current ADMX semantics.
- Impact: Silent behavior change when vendors rotate IDs or policies.
- Migration plan: Pin extension versions/XPI hash; note policy key source + Windows build tested.

## Missing Critical Features

**No backup / restore-point gate before destructive tweaks:**
- Problem: Only `services` and `autoruns-check` create a restore point inline, and `restore-point` is a separate manual row. Defender-off, firewall-off, bloatware-remove-all, Edge-removal, UAC-off, `cleanup` (deletes `Windows.old`, `SoftwareDistribution\*`), and `power-plan` (deletes all schemes) run without snapshot. `Checkpoint-Computer` failures are swallowed (`-ErrorAction SilentlyContinue`), so even the two gated tweaks may proceed unprotected on Home edition or with System Protection off.
- Blocks: Safe "try and revert" workflow; every incident becomes a reinstall (`Reinstall Windows` group, `Tweaks/Refresh.ps1:15-38`).

**No pre-flight checks (edition, build, Secure Boot, BitLocker, network):**
- Problem: DEP-off requires Secure Boot off (noted only in description, `Tweaks/Advanced.ps1:463-474`); VBS/HVCI toggles conflict with FaceIt/Vanguard (noted in comments, not in UI); `home-to-pro` uses a generic key with "disable internet first" as text (`Tweaks/Setup.ps1:66-81`); BitLocker-off runs `Disable-BitLocker` without checking protectors/suspend state (`Tweaks/Setup.ps1:3-35`); `updates-pause` writes a 365-day pause with no unpause button (`Tweaks/Setup.ps1:284-301`).
- Blocks: Users cannot tell whether a tweak applies to their machine before clicking.

**No revert-verification or health check after reboot flows:**
- Problem: After double-reboot flows there is no "verify" step (re-read the key, confirm service `Start`, confirm normal boot). The log drawer (`Akari.ps1:119-122`) is in-memory; post-reboot evidence is gone except `akari.log` errors.
- Blocks: Confirming the machine landed in the intended state vs. stuck in safeboot/half-applied.

## Test Coverage Gaps

**No automated tests of any kind:**
- What's not tested: Everything — no Pester, no PSScriptAnalyzer config, no CI workflow, no `.reg` syntax validation, no `Detect` vs Apply consistency check, no revert-round-trip test.
- Files: All of `Tweaks/*.ps1`, `Akari.ps1`, `IWR.ps1`, `AllowScripts.cmd`, numbered `*\*.ps1` folders.
- Risk: A one-character `.reg` typo (e.g. `SeleactiveSuspendEnabled` at `Tweaks/Windows.ps1:4803` — note the transposed `ea`) ships silently; the key is written and the revert deletes the same misspelled name, so neither ever affects the real `SelectiveSuspendEnabled` value.
- Priority: High — add at minimum: (1) `PSScriptAnalyzer` run, (2) a parser test that every `Add-Tweak -Id` is unique and every Toggle has both Apply and Revert, (3) a `.reg`-block syntax lint, (4) a `shutdown`/`bcdedit` call-site audit listing which have `-Confirm`.

**Revert parity is unverified:**
- What's not tested: Whether every value written by Apply is restored by Revert (vs deleted, vs left). Spot-checked gaps: `netadapter-power` Apply writes 15 values but Revert deletes them (acceptable only if absent originally — never verified); `edge-settings` Apply deletes Edge services/tasks with no Revert path except reinstalling Edge (`Tweaks/Setup.ps1:181-205`); `cleanup` has no Revert by design (Kind Action) but deletes `Windows.old`, killing the 10-day rollback.
- Files: `Tweaks/Windows.ps1:4993-5084`, `Tweaks/Setup.ps1:138-205`, `Tweaks/Windows.ps1:6129-6152`
- Risk: "Default" button gives false confidence; support burden falls on reinstall flows.
- Priority: High — generate an Apply-write vs Revert-restore matrix per tweak ID before adding new tweaks.

**Console-kind scripts (`Kind Console`) bypass UI review:**
- What's not tested: `autounattend` (`2 Refresh\4 Autounattend.ps1`), `updates-drivers-block` (`2 Refresh\5 Updates Drivers Block.ps1`), `smt-ht`, `core1-thread1`, `priority` (`8 Advanced\8-10 *.ps1`) run in their own console window (`Akari.ps1:277-280`) outside the runspace/log pipeline; interactive prompts (`show-menu`, `Pause`) hang if the worker context changes.
- Files: `Tweaks/Refresh.ps1:40-44`, `Tweaks/Advanced.ps1:934-941`, `2 Refresh\4 Autounattend.ps1`, `2 Refresh\5 Updates Drivers Block.ps1`
- Risk: Failures in these scripts never reach `akari.log` or the log drawer.
- Priority: Medium — wrap console launches with transcript logging.

---

*Concerns audit: 2026-10-08*
