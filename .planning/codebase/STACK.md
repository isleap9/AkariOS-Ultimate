# Technology Stack

**Analysis Date:** 2026-10-08

## Languages

**Primary:**
- PowerShell 5.1 (Windows PowerShell) - All logic: `Akari.ps1`, `IWR.ps1`, `Tweaks/*.ps1`, ~114 numbered scripts under `1 Check/`–`8 Advanced/`
- XAML (WPF markup) - Declarative UI in `UI/MainWindow.xaml`

**Secondary:**
- Batch (`.cmd`) - Execution-policy bootstrap in `AllowScripts.cmd`
- Inline C# (P/Invoke signature only) - Single `DllImport("dwmapi.dll")` declaration in `Akari.ps1:16`

## Runtime

**Environment:**
- Windows PowerShell 5.1 (`powershell.exe`, NOT PowerShell 7 / `pwsh`). Enforced by `#requires -Version 5.1` in `Akari.ps1:1` and explicit `powershell.exe -STA` relaunch in `Akari.ps1:11` and `IWR.ps1:66`
- .NET Framework (inbox WPF stack) + STA apartment thread (required by WPF; checked in `Akari.ps1:7`)
- Must run elevated (Administrator); self-elevates via `Start-Process -Verb RunAs` in `Akari.ps1:11` and `IWR.ps1:22`

**Package Manager:**
- None. No `package.json`, `requirements.txt`, `Cargo.toml`, `go.mod`, `*.csproj`, `*.sln`, or module manifest (`.psd1`) anywhere in repo
- Lockfile: missing (not applicable — zero package dependencies)

## Frameworks

**Core:**
- WPF (`PresentationFramework, PresentationCore, WindowsBase, System.Xaml` loaded via `Add-Type` in `Akari.ps1:15`) - Entire UI; windows parsed with `[Windows.Markup.XamlReader]::Parse` (`Akari.ps1:103,172`)
- `System.Windows.Forms` + `System.Drawing` - Folder/file dialogs and wallpaper image manipulation in tweak scripts (e.g. `Tweaks/Windows.ps1:718,721`, `8 Advanced/10 Priority.ps1:115`, `6 Windows/6 Signout Lockscreen Wallpaper Black.ps1:22`)
- .NET Runspaces (`[runspacefactory]::CreateRunspace()` in `Akari.ps1:227`) - Background execution of tweak `Apply`/`Revert`/`Check` scriptblocks so the UI stays responsive
- `Windows.Threading.DispatcherTimer` (150 ms tick, `Akari.ps1:237`) - Drains the log queue and completes background jobs on the UI thread

**Testing:**
- None. No test runner, assertion library, or `*.test.*` / `*.spec.*` / `Pester` files detected

**Build/Dev:**
- None. No build tool, bundler, linter config (`.eslintrc`, `.prettierrc`, `PSScriptAnalyzerSettings.psd1`), or formatter. Files run directly from source: `powershell -ExecutionPolicy Bypass -File Akari.ps1`

## Key Dependencies

**Critical:**
- None (third-party). Every `Add-Type` target (`PresentationFramework`, `System.Windows.Forms`, `System.Drawing`, `System.Xaml`) is an inbox .NET Framework assembly. No `Import-Module` of external modules detected
- COM automation (inbox Windows): `WScript.Shell` (shortcut creation) and `Shell.Application` (Desktop path) used across `Tweaks/Installers.ps1` (e.g. lines 24-29, 56-67)
- CIM/WMI (inbox): `Get-CimInstance Win32_ComputerSystem` (RAM size, `Akari.ps1:347`), `Win32_Service` (TrustedInstaller hijack helper, `Akari.ps1:88`), `Get-Service` / `Get-ScheduledTask` (installer cleanup, `Tweaks/Installers.ps1:102-109`)

**Infrastructure:**
- Windows Registry (via `reg.exe`, `Set-ItemProperty`/`New-ItemProperty` helpers) - Primary configuration/tweak surface (`HKLM:\SYSTEM\CurrentControlSet\Control`, browser policy keys, PowerShell `ShellIds`)
- `Expand-Archive` / `Invoke-WebRequest` (aliased `IWR`) - Download-and-install pipeline used by every installer and driver script (e.g. `Tweaks/Installers.ps1:10`, `Tweaks/Graphics.ps1:207-213`)
- `dwmapi.dll!DwmSetWindowAttribute(attr 20)` via P/Invoke (`Akari.ps1:16,116`) - Forces dark title bar

## Configuration

**Environment:**
- No `.env` files, no secrets, no env-var-based config. Presence check only: no `.env*`, `credentials*`, `*.pem`/`*.key` files exist in repo
- Runtime state is local-only:
  - `$env:LOCALAPPDATA\Akari\state.json` - Remembers applied Toggle tweaks (`Akari.ps1:59-67`)
  - `$env:LOCALAPPDATA\Akari\akari.log` - Error log (`Akari.ps1:24`)
  - `$env:SystemRoot\Temp\` - Download staging for every `IWR ... -OutFile` call
- Execution policy is mutated on the machine (not per-project config): `AllowScripts.cmd:29-32` and `IWR.ps1:52-54` write `HKCR\Applications\powershell.exe\shell\open\command` and `HKCU/HKLM\...\ShellIds\Microsoft.PowerShell\ExecutionPolicy = Unrestricted`

**Build:**
- No build config files (`tsconfig.json`, `*.config.*`, `.nvmrc`, `Makefile`, CI YAML all absent)

## Platform Requirements

**Development:**
- Windows 10/11 machine with Windows PowerShell 5.1 and .NET Framework WPF stack; Administrator shell; edit `.ps1`/`.xaml` with any text editor — no toolchain install needed

**Production:**
- Windows 10/11 Home/Pro/LTSC/IoT/Server, x64, online access (`README.md:6-8`); Administrator + reboot required for tweaks to apply (`README.md:4`); single static asset pair `Assets/AkariLogo.png` / `Assets/AkariLogo.ico` loaded at `Akari.ps1:106-112`

---

*Stack analysis: 2026-10-08*
