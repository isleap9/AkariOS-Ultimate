# ============================================================
#  IWR.ps1 - download, extract and launch AkariOS Ultimate.
#
#  Same one-liner delivery as before: paste the URL, get the
#  toolbox. Two changes from the original:
#
#    - the destination is C:\ rather than the Desktop
#    - the toolbox GUI is launched instead of Explorer
#
#  The GUI needs admin: every tweak writes HKLM, services or
#  appx packages, so it re-launches itself elevated if it is
#  not already. That check happens before the download so the
#  user is prompted once, not after a large transfer.
# ============================================================

# admin
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
{Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
Exit}

# silent
$progresspreference = 'silentlycontinue'

$root    = "C:\AkariOS-Ultimate"
$zip     = "$env:SystemRoot\Temp\AkariOS-Ultimate.zip"
$staging = "$env:SystemRoot\Temp\AkariOS-Ultimate"

# clear any previous copy, so a re-run is clean rather than
# merging new files over an old tree
Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $zip -Force -ErrorAction SilentlyContinue

# download
iwr "https://github.com/isleap9/AkariOS-Ultimate/archive/refs/heads/main.zip" -OutFile $zip

# extract
Expand-Archive -Path $zip -DestinationPath $staging -Force

# rename
Rename-Item -Path "$staging\AkariOS-Ultimate-main" -NewName "AkariOS-Ultimate" -Force

# move to C:\ rather than the Desktop
Move-Item -Path "$staging\AkariOS-Ultimate" -Destination $root -Force

# allow
cmd /c "reg add `"HKCR\Applications\powershell.exe\shell\open\command`" /ve /t REG_SZ /d `"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -ExecutionPolicy unrestricted -File \`"`"%1\`"`"`" /f >nul 2>&1"
cmd /c "reg add `"HKCU\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell`" /v `"ExecutionPolicy`" /t REG_SZ /d `"Unrestricted`" /f >nul 2>&1"
cmd /c "reg add `"HKLM\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell`" /v `"ExecutionPolicy`" /t REG_SZ /d `"Unrestricted`" /f >nul 2>&1"

# unblock: files fetched over the wire carry a zone identifier, and a
# blocked file is refused before it can be read
Get-ChildItem -Path $root -Recurse | Unblock-File

# open the toolbox
Start-Process "$root\AkariOS Toolbox.cmd"

# exit
exit