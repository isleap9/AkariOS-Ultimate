# Refresh category. GENERATED from the AkariOS-Ultimate '2 Refresh' scripts.

Add-Tweak -Id 'factory-reset' -Category 'Refresh' -Kind Action -Button 'Open' -Name 'Factory reset' -Risk Safe `
    -Description 'Open the Windows recovery settings' `
    -Apply {
Start-Process "ms-settings:recovery"
    }

Add-Tweak -Id 'account-local' -Category 'Refresh' -Kind Action -Button 'Open' -Name 'Local account' -Risk Safe `
    -Description 'Open the user accounts window (netplwiz)' `
    -Apply {
Start-Process "netplwiz"
    }

Add-Tweak -Id 'reinstall' -Category 'Refresh' -Kind Group -Name 'Reinstall Windows' -Risk Caution `
    -Description 'Download the Windows media creation tool' `
    -Actions @(
        @{ Name = 'Reinstall: W10'; Description = 'Download the Windows 10 media creation tool'; Button = 'Download'; Block = {
if (-not (Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet -ErrorAction SilentlyContinue)) { Write-Log 'Internet connection required'; return }
Write-Host "Downloading: Media Creation Tool Win 10..."

# download media creation tool win 10
IWR "https://github.com/isleap9/AkariOS-Files/releases/download/Files/mediacreationtoolw10.exe" -OutFile "$env:SystemRoot\Temp\mediacreationtoolw10.exe"

# start media creation tool win 10
Start-Process "$env:SystemRoot\Temp\mediacreationtoolw10.exe"
        }},
        @{ Name = 'Reinstall: W11'; Description = 'Download the Windows 11 media creation tool'; Button = 'Download'; Block = {
if (-not (Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet -ErrorAction SilentlyContinue)) { Write-Log 'Internet connection required'; return }
Write-Host "Downloading: Media Creation Tool Win 11..."

# download media creation tool win 11
IWR "https://github.com/isleap9/AkariOS-Files/releases/download/Files/mediacreationtoolw11.exe" -OutFile "$env:SystemRoot\Temp\mediacreationtoolw11.exe"

# start media creation tool win 11
Start-Process "$env:SystemRoot\Temp\mediacreationtoolw11.exe"
        }}
    )

Add-Tweak -Id 'autounattend' -Category 'Refresh' -Kind Console -Button 'Open console' -Name 'Autounattend' -Risk Caution -Script '2 Refresh\4 Autounattend.ps1' `
    -Description 'Create an autounattend file for a bootable USB (asks questions)'

Add-Tweak -Id 'updates-drivers-block' -Category 'Refresh' -Kind Console -Button 'Open console' -Name 'Updates and drivers block' -Risk Advanced -Script '2 Refresh\5 Updates Drivers Block.ps1' `
    -Description 'Block or unblock Windows updates and driver updates (Pro/LTSC, asks questions)'

Add-Tweak -Id 'network-driver' -Category 'Refresh' -Kind Action -Button 'Open' -Name 'Network driver' -Risk Safe `
    -Description 'Search your motherboard model online for the network driver' `
    -Apply {
# get motherboard id
$instanceID = (Get-CimInstance Win32_BaseBoard).Product
$query = [uri]::EscapeDataString($instanceID)

# search motherboard id in web browser
Start-Process "https://www.google.com/search?q=$query"
    }

Add-Tweak -Id 'to-bios' -Category 'Refresh' -Kind Action -Button 'Restart' -Name 'Restart to BIOS' -Risk Caution -Confirm 'Restart now and boot into the BIOS / UEFI settings? Unsaved work will be lost.' `
    -Description 'Restart the PC straight into the BIOS or UEFI settings' `
    -Apply {
Write-Host "Press Enter to Restart to BIOS" -ForegroundColor Red
Pause

# restart to bios
cmd /c C:\Windows\System32\shutdown.exe /r /fw /t 0
    }
