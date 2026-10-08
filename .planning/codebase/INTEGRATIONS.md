# External Integrations

**Analysis Date:** 2026-10-08

## APIs & External Services

**Distribution / bootstrap (GitHub):**
- `github.com/isleap9/AkariOS-Ultimate` - Source of truth; `IWR.ps1:19,40` self-references `.../raw/refs/heads/main/IWR.ps1` for elevation re-launch and downloads `.../archive/refs/heads/main.zip` then extracts it to `C:\AkariOS-Ultimate`
  - SDK/Client: `Invoke-WebRequest` (alias `IWR`) + `Expand-Archive` — no GitHub API, no token
  - Auth: none (public repo, anonymous HTTPS)
- `github.com/isleap9/AkariOS-Files/releases/download/Files/*` - Binary payload CDN for ~40 installers/drivers/utilities consumed in `Tweaks/Installers.ps1`, `Tweaks/Graphics.ps1`, `Tweaks/Check.ps1`, `Tweaks/Hardware.ps1` (e.g. `7zip.exe`, `ddu.exe`, `discord.exe`, `steam.exe`, `vcredist*.exe`, `hidusbf.zip`, `furmark.zip`, `cpuz.exe`, `gpuz.exe`, `occt.exe`)
  - SDK/Client: `IWR "<url>" -OutFile "$env:SystemRoot\Temp\<name>"` then `Start-Process -Wait`
  - Auth: none. Provenance documented per-file (upstream URL + SHA256 + copyright) in `LICENSE:27-326`
- `github.com/FR33THYFR33THY/Ultimate/releases/download/Files/msiafterburner.exe` - MSI Afterburner payload (`4 Installers/2 MSI Afterburner.ps1:27`, `Tweaks/Installers.ps1:919+`)
  - Auth: none

**Driver lookup APIs / pages:**
- NVIDIA AjaxDriverService - `https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup...` queried with `Invoke-WebRequest -UseBasicParsing` and parsed via `ConvertFrom-Json` in `Tweaks/Graphics.ps1:207-213` (mirrored in `5 Graphics/2 Driver Updated Install.ps1:41`); resolved version is downloaded from `https://international.download.nvidia.com/Windows/$version/...-international-dch-whql.exe`
  - Auth: none (public JSON endpoint)
- AMD driver page scrape - `https://www.amd.com/en/support/download/drivers.html` fetched and parsed in `Tweaks/Graphics.ps1:225`
  - Auth: none
- Vendor download pages opened in browser (no API): `https://www.nvidia.com/en-us/drivers`, `https://www.amd.com/en/support/download/drivers.html`, Intel graphics search URL, `https://www.guru3d.com/download/msi-afterburner-beta-download` (commented reference in `Tweaks/Installers.ps1:914`)

**Browser extension stores (policy-pinned, not downloaded by us):**
- `https://clients2.google.com/service/update2/crx` - uBlock Origin force-install ID `ddkjiahejlhfcafbddmgiahcphecmpfh` written to Brave/Chrome `ExtensionInstallForcelist` policy (`Tweaks/Installers.ps1:85,396`)
- `https://edge.microsoft.com/extensionwebstorebase/v1/crx` - Edge extension force-install ID `odfafepnkmbhccpbejgmiehpchacaeak` (`3 Setup/10 Edge Settings.ps1:34`)
- `https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi` - Direct XPI download into `C:\Program Files\Mozilla Firefox\distribution\extensions` (`Tweaks/Installers.ps1:303`)

**Outbound informational links (`Start-Process "https://..."` — opens user browser, no data sent):**
- `https://www.google.com/search?q=$query` - BIOS / motherboard / network-driver lookup (`1 Check/1 Bios Check.ps1:26`, `Tweaks/Check.ps1:15`, `Tweaks/Refresh.ps1:54`, `2 Refresh/6 Network Driver.ps1:16`)
- `https://www.testufo.com/framerates...` - Monitor check (`Tweaks/Hardware.ps1:375`, `7 Hardware/6 Monitor Optimization.ps1:12`)
- `https://www.waveform.com/tools/bufferbloat` - Bufferbloat test (`Tweaks/Hardware.ps1:391`, `7 Hardware/7 Network Bufferbloat Test.ps1:1`)
- `https://pcpartpicker.com/user/fr33thy/saved` - Build guide (`Tweaks/Hardware.ps1:397`, `7 Hardware/8 PC Build Guide.ps1:1`)
- `https://github.com/massgravel/Microsoft-Activation-Scripts` - Activation reference link only, never executed (`3 Setup/4 Keys.ps1:1`, `Tweaks/Setup.ps1:86`)

**Connectivity probe:**
- `Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet` gates every installer/online action (e.g. `Tweaks/Installers.ps1:6,37,75`). Google DNS used as a dumb reachability ping, not a service dependency

## Data Storage

**Databases:**
- None. No SQL, NoSQL, ORM, or connection strings anywhere

**File Storage:**
- Local filesystem only:
  - `%LOCALAPPDATA%\Akari\state.json` - Applied-tweak booleans (`Akari.ps1:59-67`)
  - `%LOCALAPPDATA%\Akari\akari.log` - Error log (`Akari.ps1:24-27`)
  - `%SystemRoot%\Temp\` - Installer staging; `%SystemDrive%\Program Files (x86)\{CRUSRE,hidusbf,More Clock Tool,...}\` - Portable-tool installs
- Remote file storage: GitHub Releases (see above) — download-only, never uploaded to

**Caching:**
- None. Every run re-downloads payloads; no local cache invalidation or version pinning beyond the SHA256 record in `LICENSE`

## Authentication & Identity

**Auth Provider:**
- None / not applicable. No users, tokens, OAuth, or credentials. Elevation is local Windows UAC (`-Verb RunAs`), not an identity provider
  - Implementation: `Akari.ps1:6-13`, `IWR.ps1:17-24`, `AllowScripts.cmd:1-14` (UAC prompt dance)

## Monitoring & Observability

**Error Tracking:**
- None (no Sentry/Datadog/AppInsights). Errors go to the on-screen log drawer (`Add-Log`, `Akari.ps1:119`) and `%LOCALAPPDATA%\Akari\akari.log` via `Write-ErrLog` + `Dispatcher.UnhandledException` handler (`Akari.ps1:382-388`)

**Logs:**
- In-app scrolling `Log` textbox (`UI/MainWindow.xaml:286`) fed by a `ConcurrentQueue` drained every 150 ms (`Akari.ps1:237-256`); background-runspace output is redirected through `Write-Log` shim (`Akari.ps1:72-76`)

## CI/CD & Deployment

**Hosting:**
- GitHub (`github.com/isleap9/AkariOS-Ultimate`). No app server, no container, no store listing

**CI Pipeline:**
- None. No GitHub Actions workflows, no test gates, no release automation detected. Delivery is the `IWR.ps1` one-liner pasted into an elevated shell (`README.md:12-14`): `iwr 'https://github.com/isleap9/AkariOS-Ultimate/raw/refs/heads/main/IWR.ps1' -useb | iex`

## Environment Configuration

**Required env vars:**
- None custom. Code relies solely on standard Windows expandable vars: `%SystemRoot%`, `%SystemDrive%`, `%LOCALAPPDATA%`, `%APPDATA%`, `%ProgramData%`, `%TEMP%` (via `[System.IO.Path]::GetTempPath()` where usernames contain spaces, `Tweaks/Installers.ps1:191`)

**Secrets location:**
- Not applicable — repo holds no secrets, tokens, or private keys (verified: no `.env*`, `*credential*`, `*secret*`, `*.pem`/`*.key` files; nothing in `.gitignore` suggests otherwise)

## Webhooks & Callbacks

**Incoming:**
- None. No server, listener, or callback endpoint

**Outgoing:**
- None. No webhooks fired. The only network writes are `IWR -OutFile` downloads and `Start-Process` browser launches listed above

---

*Integration audit: 2026-10-08*
