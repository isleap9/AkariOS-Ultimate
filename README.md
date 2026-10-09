# AkariOS Ultimate
A Windows tweaking toolbox for power users. One window (`Akari.ps1`) holds about 127 tweaks in 8 categories and runs each one in the background, with a revert wherever a safe one exists.

# Home page
- Specs: Akari opens on Home and shows CPU, GPU, RAM, Disk (the Windows drive), Board (motherboard and BIOS) and Windows (edition, version, build). They are read fresh every time Home is shown. The cards fade while new values load, and anything Windows cannot report shows "Not available".
- Copy specs: one click puts every value on the clipboard as plain text, ready to paste into a forum post or a support chat.
- Health colours: Disk Free turns amber below 15% free and red below 10%. RAM Used turns amber above 80% used and red above 90%.

# Categories
- **Check**: BIOS, storage, RAM and GPU checks, plus storage, RAM, CPU and GPU stress tests.
- **Refresh**: factory reset, reinstall Windows, autounattend, local account, update and driver block, network driver, restart to BIOS.
- **Setup**: BitLocker, memory compression, Home to Pro, activation, startup and background apps, Edge and Store settings, pause updates.
- **Installers**: browsers, game launchers, Discord, Spotify, OBS Studio, 7-Zip, MSI Afterburner and other common apps.
- **Graphics**: driver clean (DDU) and install, NVIDIA/AMD/Intel settings, HDCP, P0 state, MSI mode, DirectX, C++ runtimes, HAGS.
- **Windows**: Start menu and taskbar, context menu, black theme, widgets, Copilot, bloatware, Game Bar, power plan, UAC, cleanup, restore point.
- **Hardware**: mouse scaling and polling, controller overclock and polling test, monitor optimization, bufferbloat test, PC build guide.
- **Advanced**: Defender, firewall, Spectre/Meltdown, SMT, process priority, ReBar, ULPS, services, plus the built-in Win32PrioritySeparation and SvcHost split tuners.

# Apply and revert
- Every tweak shows a risk label: Safe, Caution or Advanced.
- On/off tweaks have Optimize (apply) and Default (revert). The dot shows the current state, and Default is greyed out when there is no safe revert.
- One-shot tweaks have a single button, some have Options with extra actions, and a few open in their own console window.
- Tweaks run one at a time in the background, with progress and results in the log at the bottom of the window.

# Requirements
- Windows 10/11 Home/Pro/LTSC/IoT/Server (x64)
- Windows PowerShell 5.1 (built into Windows)
- Administrator rights
- Online access

# Install (IWR)
Paste below code into an elevated Administrator PowerShell window
```
iwr 'https://github.com/isleap9/AkariOS-Ultimate/raw/refs/heads/main/IWR.ps1' -useb | iex
```
It downloads Akari to `C:\AkariOS-Ultimate`, allows PowerShell scripts, and opens the app.

# Run from a downloaded zip
1. Download the repository zip and extract it.
2. Run `AllowScripts.cmd` and choose 1 (Scripts: On). This allows PowerShell scripts and unblocks the files.
3. Run `Akari.ps1` (double-click, or right-click and choose Run with PowerShell). It asks for Administrator rights.

# Safety
- Akari runs as Administrator and changes system settings (registry, services, drivers, apps).
- Reboot after applying tweaks so they take effect.
- Read the risk label first. Advanced tweaks can lower security or stability, so make a restore point before using them.
- `AllowScripts.cmd` option 2 (Scripts: Off) sets PowerShell back to Restricted.

# Credits
AkariOS Ultimate is a rebrand of [Ultimate](<https://github.com/FR33THYFR33THY/Ultimate>) by FR33THY, used under the MIT License.
