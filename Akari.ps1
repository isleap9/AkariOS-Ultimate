#requires -Version 5.1
param([switch]$ShowConsole)
# Akari (Ink UI, vertical slice). Run:  powershell -ExecutionPolicy Bypass -File Akari.ps1

# ---- elevate once, and make sure we are STA (WPF needs it)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')
$isSta = [Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA'
if (-not $isAdmin -or -not $isSta) {
    $style = if ($ShowConsole) { 'Normal' } else { 'Hidden' }
    $extra = if ($ShowConsole) { ' -ShowConsole' } else { '' }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"$extra" -Verb RunAs -WindowStyle $style
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
Add-Type -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);' -Name Dwm -Namespace Akari

$Root = $PSScriptRoot
if (-not $Root) { $Root = Split-Path -Parent $PSCommandPath }
# find the folder that really holds UI\ and Tweaks\ (handles a copy that ended up one level too deep or too high)
foreach ($c in @($Root, (Split-Path -Parent $Root), "$Root\Tweaks")) {
    if ($c -and (Test-Path "$c\UI\MainWindow.xaml") -and (Test-Path "$c\Tweaks")) { $Root = $c; break }
}
$LogFile = "$env:LOCALAPPDATA\Akari\akari.log"
function Write-ErrLog([string]$m) {
    try { New-Item (Split-Path $LogFile) -ItemType Directory -Force | Out-Null; Add-Content $LogFile ("[{0}] {1}" -f (Get-Date -Format s), $m) } catch { }
}
trap { Write-ErrLog "$($_.Exception.Message) $($_.InvocationInfo.PositionMessage)"; [void][Windows.MessageBox]::Show("Akari hit an error:`n`n$($_.Exception.Message)`n`n$($_.InvocationInfo.PositionMessage)", 'Akari'); exit }
# remove 'downloaded from the internet' marks so Windows never nags about these files
Get-ChildItem $Root -Filter *.ps1 -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
foreach ($sub in 'Tweaks', 'UI') { Get-ChildItem "$Root\$sub" -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue }
$script:Tweaks = [System.Collections.Generic.List[object]]::new()
$script:RowCache   = @{}
$script:Cat    = 'Home'
$script:Busy   = $false
$script:Job    = $null
$script:Queue  = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$script:SpecData = $null
$script:SpecJob = $null
$script:SpecPending = $false
$PrioKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'

function Add-Tweak {
    param([string]$Id, [string]$Category, [string]$Name, [string]$Description,
          [ValidateSet('Safe', 'Caution', 'Advanced')][string]$Risk = 'Safe',
          [ValidateSet('Toggle', 'Action', 'Group', 'Console')][string]$Kind = 'Toggle',
          [string]$Button = 'Run', [object[]]$Actions, [string]$Confirm, [string]$Script,
          [scriptblock]$Apply, [scriptblock]$Revert, [scriptblock]$Detect, [scriptblock]$Check)
    $script:Tweaks.Add([pscustomobject]@{ Id = $Id; Category = $Category; Name = $Name; Description = $Description
            Risk = $Risk; Kind = $Kind; Button = $Button; Actions = $Actions; Confirm = $Confirm; Script = $Script
            Apply = $Apply; Revert = $Revert; Detect = $Detect; Check = $Check })
}
foreach ($need in 'UI\MainWindow.xaml', 'Tweaks') {
    if (-not (Test-Path "$Root\$need")) {
        [void][Windows.MessageBox]::Show("Missing: $Root\$need`n`nAkari.ps1 needs UI, Tweaks and Assets folders next to it.", 'Akari')
        exit
    }
}
foreach ($f in Get-ChildItem "$Root\Tweaks" -Filter *.ps1 | Sort-Object Name) { . $f.FullName }

# ---- remembers what Akari last applied (used for the state dot when a tweak has no Detect)
$StateDir = "$env:LOCALAPPDATA\Akari"; $StatePath = "$StateDir\state.json"
$script:State = @{}
if (Test-Path $StatePath) {
    try { (Get-Content $StatePath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:State[$_.Name] = [bool]$_.Value } } catch { }
}
function Save-State {
    New-Item $StateDir -ItemType Directory -Force | Out-Null
    ($script:State | ConvertTo-Json) | Set-Content $StatePath
}

# ---- helpers that tweak scripts can use inside the background runspace
$Helpers = @'
$ProgressPreference = 'SilentlyContinue'
function Write-Log([string]$m) { if ($m -and $m.Trim()) { [void]$LogQueue.Enqueue($m.TrimEnd()) } }
function Write-Host {
    param([Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object, $ForegroundColor, $BackgroundColor, [switch]$NoNewline, $Separator = ' ')
    Write-Log (($Object | ForEach-Object { "$_" }) -join $Separator)
}
function Clear-Host { }
function show-menu { }
function Pause { }
function Set-Reg($Path, $Name, $Value, $Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}
function Remove-Reg($Path, $Name) { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue }
function Run-Trusted([String]$command) {
    try { Stop-Service -Name TrustedInstaller -Force -ErrorAction Stop -WarningAction Stop }
    catch { taskkill /im trustedinstaller.exe /f >$null }
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='TrustedInstaller'"
    $DefaultBinPath = $service.PathName
    $trustedInstallerPath = "$env:SystemRoot\servicing\TrustedInstaller.exe"
    if ($DefaultBinPath -ne $trustedInstallerPath) { $DefaultBinPath = $trustedInstallerPath }
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
    $base64Command = [Convert]::ToBase64String($bytes)
    sc.exe config TrustedInstaller binPath= "cmd.exe /c powershell.exe -encodedcommand $base64Command" | Out-Null
    sc.exe start TrustedInstaller | Out-Null
    sc.exe config TrustedInstaller binpath= "`"$DefaultBinPath`"" | Out-Null
    try { Stop-Service -Name TrustedInstaller -Force -ErrorAction Stop -WarningAction Stop }
    catch { taskkill /im trustedinstaller.exe /f >$null }
}
'@

$GetSpecsFunc = @'
function Test-SmbiosValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    # common smbios placeholder strings
    $fillers = @(
        'To Be Filled By O.E.M.',
        'Default string',
        'None',
        'N/A',
        'Not Specified',
        'Not Available',
        'System Product Name',
        'System Manufacturer',
        'System Version',
        'System Serial Number',
        'Base Board Version',
        'Base Board Product',
        'Base Board Manufacturer',
        'BIOS Version',
        'BIOS Date',
        'x.x',
        '0'
    )
    $trimmed = $Value.Trim()
    if ($fillers -contains $trimmed) { return $false }
    return $true
}

function Get-Specs {
    $result = @{
        CPU = @{ _Status = 'OK' }
        RAM = @{ _Status = 'OK' }
        Windows = @{ _Status = 'OK' }
        GPU = @{ _Status = 'OK'; Adapters = @() }
        Disk = @{ _Status = 'OK'; Volumes = @() }
        Motherboard = @{ _Status = 'OK' }
    }

    # --- CPU ---
    $cpuModel = "Not available"
    $cpuCores = "Not available"
    $cpuThreads = "Not available"
    $cpuSpeedMHz = "Not available"
    $cpuFields = 4
    $cpuSuccess = 0
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu) {
            if ($cpu.Name) { $cpuModel = $cpu.Name.Trim(); $cpuSuccess++ }
            if ($cpu.NumberOfCores -gt 0) { $cpuCores = $cpu.NumberOfCores; $cpuSuccess++ }
            elseif ($cpu.NumberOfLogicalProcessors -gt 0) { $cpuCores = $cpu.NumberOfLogicalProcessors; $cpuSuccess++ }
            if ($cpu.NumberOfLogicalProcessors -gt 0) { $cpuThreads = $cpu.NumberOfLogicalProcessors; $cpuSuccess++ }
            if ($cpu.MaxClockSpeed -gt 0) { $cpuSpeedMHz = $cpu.MaxClockSpeed; $cpuSuccess++ }
        }
    } catch { }
    $result.CPU.Model = $cpuModel
    $result.CPU.Cores = $cpuCores
    $result.CPU.Threads = $cpuThreads
    $result.CPU.SpeedMHz = $cpuSpeedMHz
    if ($cpuSuccess -eq 0) { $result.CPU._Status = 'Failed' }
    elseif ($cpuSuccess -lt $cpuFields) { $result.CPU._Status = 'Partial' }

    # --- RAM ---
    $ramTotalGB = "Not available"
    $ramUsedGB = "Not available"
    $ramFreeGB = "Not available"
    $ramFields = 3
    $ramSuccess = 0
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($os -and $os.TotalVisibleMemorySize -gt 0) {
            $totalKB = $os.TotalVisibleMemorySize
            $freeKB = $os.FreePhysicalMemory
            $usedKB = $totalKB - $freeKB
            $ramTotalGB = [math]::Round($totalKB / 1MB, 1); $ramSuccess++
            $ramUsedGB = [math]::Round($usedKB / 1MB, 1); $ramSuccess++
            $ramFreeGB = [math]::Round($freeKB / 1MB, 1); $ramSuccess++
        }
    } catch { }
    $result.RAM.TotalGB = $ramTotalGB
    $result.RAM.UsedGB = $ramUsedGB
    $result.RAM.FreeGB = $ramFreeGB
    if ($ramSuccess -eq 0) { $result.RAM._Status = 'Failed' }
    elseif ($ramSuccess -lt $ramFields) { $result.RAM._Status = 'Partial' }

    # --- Windows ---
    $winEdition = "Not available"
    $winVersion = "Not available"
    $winBuild = "Not available"
    $winFields = 3
    $winSuccess = 0
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($os) {
            if ($os.Caption) { $winEdition = $os.Caption; $winSuccess++ }
            if ($os.BuildNumber) { $winBuild = $os.BuildNumber; $winSuccess++ }
        }
    } catch { }
    try {
        $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        if ($reg) {
            if ($reg.UBR -and $winBuild -ne "Not available") { $winBuild = "$($winBuild).$($reg.UBR)"; $winSuccess++ }
            if ($reg.DisplayVersion) { $winVersion = $reg.DisplayVersion; $winSuccess++ }
            elseif ($reg.ReleaseId) { $winVersion = $reg.ReleaseId; $winSuccess++ }
        }
    } catch { }
    $result.Windows.Edition = $winEdition
    $result.Windows.Version = $winVersion
    $result.Windows.Build = $winBuild
    if ($winSuccess -eq 0) { $result.Windows._Status = 'Failed' }
    elseif ($winSuccess -lt $winFields) { $result.Windows._Status = 'Partial' }

    # --- GPU ---
    $gpuAdapters = @()
    $gpuFields = 3
    $gpuSuccess = 0
    $gpuTotal = 0
    try {
        $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
        if ($gpus.Count -eq 0) {
            $result.GPU._Status = 'Failed'
        } else {
            # read real vram from display class registry (adapterram is uint32 and caps near 4gb)
            $regVram = @{}
            $regMatch = @()
            try {
                $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
                $regKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | Sort-Object PSChildName
                foreach ($key in $regKeys) {
                    $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                    if (-not $props) { continue }
                    # windows writes qwMemorySize; qwSize kept as legacy name
                    $qw = $props.'HardwareInformation.qwMemorySize'
                    if ($null -eq $qw) { $qw = $props.'HardwareInformation.qwSize' }
                    # some drivers store the size as reg_binary
                    if ($qw -is [byte[]]) {
                        if ($qw.Length -ge 8) { $qw = [BitConverter]::ToInt64($qw, 0) } else { $qw = $null }
                    }
                    if ($null -ne $qw -and $qw -gt 0) {
                        $regVram[$key.PSChildName] = $qw
                        if ($props.MatchingDeviceId) { $regMatch += ,@{ Id = [string]$props.MatchingDeviceId; Bytes = $qw } }
                    }
                }
            } catch { }

            for ($i = 0; $i -lt $gpus.Count; $i++) {
                $gpu = $gpus[$i]
                $adapter = @{ Model = 'Not available'; VRAM_GB = 'Not available'; DriverVersion = 'Not available'; Status = 'OK' }
                $gpuTotal += $gpuFields

                if ($gpu.Name) { $adapter.Model = $gpu.Name.Trim(); $gpuSuccess++ }

                $vramBytes = $gpu.AdapterRAM
                # 4294967295 (0xFFFFFFFF) or 4293918720 (0xFFF00000) mean the real size did not fit
                $vramCapped = ($vramBytes -eq 4294967295 -or $vramBytes -ge 4GB -or $vramBytes -ge 4293918720)
                if ($vramCapped) {
                    $regBytes = $null
                    # match registry key by pnp device id first, then by index
                    if ($gpu.PNPDeviceID) {
                        foreach ($m in $regMatch) {
                            if ($gpu.PNPDeviceID.StartsWith($m.Id, [StringComparison]::OrdinalIgnoreCase)) { $regBytes = $m.Bytes; break }
                        }
                    }
                    if ($null -eq $regBytes) {
                        $regKey = '{0:D4}' -f $i
                        if ($regVram.ContainsKey($regKey)) { $regBytes = $regVram[$regKey] }
                    }
                    if ($null -ne $regBytes) { $vramBytes = $regBytes; $vramCapped = $false }
                }
                if (-not $vramCapped -and $vramBytes -gt 0) {
                    $adapter.VRAM_GB = [math]::Round($vramBytes / 1GB, 1)
                    $gpuSuccess++
                }

                if ($gpu.DriverVersion) { $adapter.DriverVersion = $gpu.DriverVersion; $gpuSuccess++ }

                if ($gpu.Status -and $gpu.Status -ne 'OK') { $adapter.Status = $gpu.Status }

                $gpuAdapters += ,$adapter
            }
        }
    } catch {
        $result.GPU._Status = 'Failed'
    }
    $result.GPU.Adapters = $gpuAdapters
    if ($gpuSuccess -eq 0 -and $gpuTotal -gt 0) { $result.GPU._Status = 'Failed' }
    elseif ($gpuSuccess -lt $gpuTotal) { $result.GPU._Status = 'Partial' }

    # --- Disk ---
    $diskVolumes = @()
    # drive, filesystem, totalgb, freegb (label is descriptive and not counted)
    $diskFields = 4
    $diskSuccess = 0
    $diskTotal = 0
    try {
        # fixed drives only (drivetype 3)
        $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DriveType -eq 3 })
        if ($disks.Count -eq 0) {
            $result.Disk._Status = 'Failed'
        } else {
            foreach ($disk in $disks) {
                $vol = @{ Drive = 'Not available'; Label = ''; FileSystem = 'Not available'; TotalGB = 'Not available'; FreeGB = 'Not available' }
                $diskTotal += $diskFields

                if ($disk.DeviceID) { $vol.Drive = $disk.DeviceID; $diskSuccess++ }
                # empty label is a valid reading, not a failed field
                if ($disk.VolumeName) { $vol.Label = $disk.VolumeName }
                if ($disk.FileSystem) { $vol.FileSystem = $disk.FileSystem; $diskSuccess++ }
                if ($disk.Size -gt 0) { $vol.TotalGB = [math]::Round($disk.Size / 1GB, 1); $diskSuccess++ }
                # 0 bytes free is a real reading (full disk); only null means not reported
                if ($null -ne $disk.FreeSpace) { $vol.FreeGB = [math]::Round($disk.FreeSpace / 1GB, 1); $diskSuccess++ }

                $diskVolumes += ,$vol
            }
        }
    } catch {
        $result.Disk._Status = 'Failed'
    }
    $result.Disk.Volumes = $diskVolumes
    if ($diskSuccess -eq 0 -and $diskTotal -gt 0) { $result.Disk._Status = 'Failed' }
    elseif ($diskSuccess -lt $diskTotal) { $result.Disk._Status = 'Partial' }

    # --- Motherboard / BIOS ---
    $mbManufacturer = 'Not available'
    $mbProduct = 'Not available'
    $biosVersion = 'Not available'
    $biosDate = 'Not available'
    $mbFields = 4
    $mbSuccess = 0
    try {
        $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
        if ($board) {
            if (Test-SmbiosValue $board.Manufacturer) { $mbManufacturer = $board.Manufacturer.Trim(); $mbSuccess++ }
            if (Test-SmbiosValue $board.Product) { $mbProduct = $board.Product.Trim(); $mbSuccess++ }
        }
    } catch { }
    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop | Select-Object -First 1
        if ($bios) {
            if (Test-SmbiosValue $bios.SMBIOSBIOSVersion) { $biosVersion = $bios.SMBIOSBIOSVersion.Trim(); $mbSuccess++ }
            # smbios date is midnight utc; format in utc with invariant culture so the day and calendar never shift
            if ($bios.ReleaseDate) { $biosDate = $bios.ReleaseDate.ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture); $mbSuccess++ }
        }
    } catch { }
    $result.Motherboard.Manufacturer = $mbManufacturer
    $result.Motherboard.Product = $mbProduct
    $result.Motherboard.BIOSVersion = $biosVersion
    $result.Motherboard.ReleaseDate = $biosDate
    if ($mbSuccess -eq 0) { $result.Motherboard._Status = 'Failed' }
    elseif ($mbSuccess -lt $mbFields) { $result.Motherboard._Status = 'Partial' }

    return $result
}
'@

$HostIdentityFunc = @'
function Get-HostIdentity {
    $m = 'Not available'
    $mdl = 'Not available'
    try {
        # computer maker and model for the home header
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1
        if ($cs) {
            if (Test-SmbiosValue $cs.Manufacturer) { $m = $cs.Manufacturer.Trim() }
            if (Test-SmbiosValue $cs.Model) { $mdl = $cs.Model.Trim() }
        }
    } catch { }
    return @{ Manufacturer = $m; Model = $mdl }
}
'@

# composite read run by the home page: a good read emits a hashtable with a Specs key, a throwing read emits a string
$SpecReadCode = $GetSpecsFunc + "`n" + $HostIdentityFunc + "`n" + @'
try { @{ Specs = Get-Specs; Host = Get-HostIdentity } } catch { $_.Exception.Message }
'@

# ---- window
$window = [Windows.Markup.XamlReader]::Parse((Get-Content "$Root\UI\MainWindow.xaml" -Raw))
foreach ($n in 'Nav', 'Search', 'Heading', 'Tuner', 'SvcTuner', 'SvcCur', 'Rows', 'Page', 'Log', 'Hex', 'Dec', 'Logo', 'HomePanel', 'HostName', 'HostSub', 'Cards') { Set-Variable $n $window.FindName($n) }

$logoPath = "$Root\Assets\AkariLogo.png"
if (Test-Path $logoPath) {
    $bmp = [Windows.Media.Imaging.BitmapImage]::new()
    $bmp.BeginInit(); $bmp.UriSource = [Uri]$logoPath; $bmp.CacheOption = 'OnLoad'; $bmp.EndInit()
    $Logo.Source = $bmp
    $window.Icon = $bmp
}
$window.Add_SourceInitialized({   # dark title bar
    $h = [Windows.Interop.WindowInteropHelper]::new($window).Handle
    $v = 1
    [void][Akari.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)
})

function Add-Log([string]$m) {
    $Log.AppendText(("[{0}] {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $m))
    $Log.ScrollToEnd()
}

# ---- rows
function New-Row($t) {
    $e = { param($s) [Security.SecurityElement]::Escape([string]$s) }
    $riskKey = @{ Safe = 'Mu'; Caution = 'Warn'; Advanced = 'Bad' }[$t.Risk]
    $id = $t.Id
    if ($t.Kind -eq 'Action' -or $t.Kind -eq 'Console') {
        $btns = "<Button Tag=`"$id|Run`" Content=`"$(& $e $t.Button)`" Style=`"{DynamicResource Btn}`"/>"
    } elseif ($t.Kind -eq 'Group') {
        $main = if ($t.Apply) { "<Button Tag=`"$id|Apply`" Content=`"$(& $e $t.Button)`" Style=`"{DynamicResource Btn}`"/>" } else { '' }
        $btns = "$main<Button x:Name=`"Exp`" Tag=`"$id|Expand`" Content=`"Options`" Style=`"{DynamicResource Btn}`"/>"
    } else {
        $defOff = if ($t.Revert) { '' } else { ' IsEnabled="False" ToolTip="No safe revert for this script"' }
        $btns = "<Button x:Name=`"Opt`" Tag=`"$id|Apply`" Content=`"Optimize`" Style=`"{DynamicResource Btn}`"/><Button x:Name=`"Def`" Tag=`"$id|Revert`" Content=`"Default`" Style=`"{DynamicResource Btn}`"$defOff/>"
        if ($t.Check) { $btns += "<Button Tag=`"$id|Check`" Content=`"Check`" Style=`"{DynamicResource Btn}`"/>" }
    }
    $sub = ''
    if ($t.Kind -eq 'Group') {
        $i = 0
        foreach ($a in $t.Actions) {
            $sub += @"
<Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
<StackPanel VerticalAlignment="Center"><TextBlock Text="$(& $e $a.Name)"/><TextBlock Text="$(& $e $a.Description)" Foreground="{DynamicResource Mu}" FontSize="12.5" TextWrapping="Wrap"/></StackPanel>
<Button Grid.Column="1" Tag="$id|Sub|$i" Content="$(& $e $a.Button)" Style="{DynamicResource Btn}"/></Grid>
"@
            $i++
        }
        $sub = "<StackPanel x:Name=`"Sub`" Visibility=`"Collapsed`" Margin=`"22,12,0,0`"><Border BorderBrush=`"{DynamicResource Bd}`" BorderThickness=`"0,1,0,0`" Margin=`"0,0,0,10`"/>$sub</StackPanel>"
    }
    $dotVis = if ($t.Kind -eq 'Toggle') { 'Visible' } else { 'Hidden' }
    $xaml = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Background="{DynamicResource S1}" BorderBrush="{DynamicResource Bd}" BorderThickness="1" CornerRadius="5" Padding="12,9" Margin="0,0,0,6">
  <StackPanel>
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="22"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <Ellipse x:Name="Dot" Visibility="$dotVis" Width="9" Height="9" Stroke="{DynamicResource Mu}" StrokeThickness="1.5" HorizontalAlignment="Left" VerticalAlignment="Center"/>
    <StackPanel Grid.Column="1" VerticalAlignment="Center">
      <TextBlock Text="$(& $e $t.Name)" FontWeight="Medium"/>
      <TextBlock Text="$(& $e $t.Description)" Foreground="{DynamicResource Mu}" FontSize="12.5" TextWrapping="Wrap"/>
    </StackPanel>
    <Border Grid.Column="2" BorderThickness="1" CornerRadius="3" Padding="7,1" Margin="12,0" VerticalAlignment="Center"
            BorderBrush="{DynamicResource $riskKey}"><TextBlock Text="$($t.Risk)" FontSize="12" Foreground="{DynamicResource $riskKey}"/></Border>
    <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">$btns</StackPanel>
  </Grid>
  $sub
  </StackPanel>
</Border>
"@
    [Windows.Markup.XamlReader]::Parse($xaml)
}

function Get-State($t) {
    if ($t.Detect) {
        try { $r = & $t.Detect; if ($r -is [bool]) { return $r } } catch { }
    }
    if ($script:State.ContainsKey($t.Id)) { return [bool]$script:State[$t.Id] }
    return $null
}

function Update-Row($t) {
    if ($t.Kind -ne 'Toggle') { return }
    $row = $script:RowCache[$t.Id]
    $s = Get-State $t
    $dot = $row.FindName('Dot')
    $dot.Fill = if ($s -eq $true) { $window.FindResource('Inv') } else { [Windows.Media.Brushes]::Transparent }
    $dot.Opacity = if ($null -eq $s) { 0.35 } else { 1 }
    $row.FindName('Opt').Style = $window.FindResource($(if ($s -eq $true) { 'BtnP' } else { 'Btn' }))
    $row.FindName('Def').Style = $window.FindResource('Btn')
}

function Show-Page {
    $q = $Search.Text.Trim()
    $onHome = (-not $q -and $script:Cat -eq 'Home')
    $Rows.Children.Clear()
    if ($q) {
        $Heading.Text = "Results for `"$q`""
        $list = @($script:Tweaks | Where-Object { "$($_.Name) $($_.Description)" -like "*$q*" })
    } else {
        $Heading.Text = $script:Cat
        $list = @($script:Tweaks | Where-Object { $_.Category -eq $script:Cat })
    }
    $adv = (-not $q -and $script:Cat -eq 'Advanced')
    $Tuner.Visibility = if ($adv) { 'Visible' } else { 'Collapsed' }
    $SvcTuner.Visibility = $Tuner.Visibility
    $HomePanel.Visibility = if ($onHome) { 'Visible' } else { 'Collapsed' }
    $Heading.Visibility = if ($onHome) { 'Collapsed' } else { 'Visible' }
    foreach ($t in $list) {
        if (-not $script:RowCache.ContainsKey($t.Id)) { $script:RowCache[$t.Id] = New-Row $t }
        [void]$Rows.Children.Add($script:RowCache[$t.Id])
        Update-Row $t
    }
    if (-not $list.Count -and -not $adv -and -not $onHome) {
        $msg = [Windows.Controls.TextBlock]::new()
        $msg.Text = if ($q) { 'No scripts match.' } else { 'Nothing here yet.' }
        $msg.Foreground = $window.FindResource('Mu')
        [void]$Rows.Children.Add($msg)
    }
    # render the last values (or loading) first, then read fresh specs in the background
    if ($onHome) { Update-Home; Start-SpecRead }
}

# ---- running actions in a background runspace
function Set-Busy([bool]$b) { $script:Busy = $b; $Page.IsEnabled = -not $b }

function Invoke-Code([string]$code, [string]$label, $meta = $null, [string]$ResultVar = $null) {
    if ($script:Busy) { return }
    Set-Busy $true
    Add-Log $label
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('LogQueue', $script:Queue)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    if ($ResultVar) {
        $resultCollection = [System.Management.Automation.PSDataCollection[object]]::new()
        $wrapped = $Helpers + "`ntry {`n`$__result = & {`n" + $code + "`n}`n`$__result`n} catch { Write-Log ('Error: ' + `$_.Exception.Message); `$__result = `$null }"
        [void]$ps.AddScript($wrapped)
        # ps 5.1 cannot bind the generic BeginInvoke overload with $null input, pass an empty completed collection
        $inputCollection = [System.Management.Automation.PSDataCollection[object]]::new()
        $inputCollection.Complete()
        $script:Job = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke($inputCollection, $resultCollection); Label = $label; Meta = $meta; ResultVar = $ResultVar; ResultCollection = $resultCollection }
    } else {
        $wrapped = $Helpers + "`ntry {`n& {`n" + $code + "`n} *>&1 | Out-String -Stream | ForEach-Object { if (`$_.Trim()) { Write-Log `$_ } }`n} catch { Write-Log ('Error: ' + `$_.Exception.Message) }"
        [void]$ps.AddScript($wrapped)
        $script:Job = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke(); Label = $label; Meta = $meta }
    }
}

# ---- home page (spec cards)
function Fmt-Num($v, [string]$fmt, [string]$unit, [double]$scale = 1) {
    # the 'Not available' sentinel is a string: pass it through with no unit
    if ($null -eq $v -or $v -is [string]) { return $v }
    return ($v / $scale).ToString($fmt, [Globalization.CultureInfo]::InvariantCulture) + " $unit"
}

function New-Card([string]$title) {
    $card = [Windows.Controls.Border]::new()
    $card.Width = 240
    $card.Background = $window.FindResource('S1')
    $card.BorderBrush = $window.FindResource('Bd')
    $card.BorderThickness = [Windows.Thickness]::new(1)
    $card.CornerRadius = [Windows.CornerRadius]::new(5)
    $card.Padding = [Windows.Thickness]::new(16, 12, 16, 12)
    $card.Margin = [Windows.Thickness]::new(0, 0, 8, 8)
    $sp = [Windows.Controls.StackPanel]::new()
    $tb = [Windows.Controls.TextBlock]::new()
    $tb.Text = $title
    $tb.FontSize = 12
    $tb.FontWeight = [Windows.FontWeights]::SemiBold
    $tb.Foreground = $window.FindResource('Mu')
    $tb.Margin = [Windows.Thickness]::new(0, 0, 0, 4)
    [void]$sp.Children.Add($tb)
    $card.Child = $sp
    return $card
}

function Add-Loading($card) {
    $tb = [Windows.Controls.TextBlock]::new()
    $tb.Text = 'Loading' + [string][char]0x2026
    $tb.FontSize = 13
    $tb.Foreground = $window.FindResource('Mu')
    [void]$card.Child.Children.Add($tb)
}

function Add-Headline($card, [string]$text) {
    $tb = [Windows.Controls.TextBlock]::new()
    $tb.Text = $text
    $tb.FontSize = 15
    $tb.FontWeight = [Windows.FontWeights]::SemiBold
    $tb.Foreground = $window.FindResource($(if ($text -eq 'Not available') { 'Mu' } else { 'Tx' }))
    $tb.TextWrapping = [Windows.TextWrapping]::Wrap
    $tb.Margin = [Windows.Thickness]::new(0, 0, 0, 8)
    [void]$card.Child.Children.Add($tb)
}

function Add-Row($card, [string]$label, [string]$value) {
    $sp = $card.Child
    $first = (@($sp.Children | Where-Object { $_ -is [Windows.Controls.Grid] }).Count -eq 0)
    $g = [Windows.Controls.Grid]::new()
    $g.Margin = [Windows.Thickness]::new(0, $(if ($first) { 0 } else { 4 }), 0, 0)
    $c0 = [Windows.Controls.ColumnDefinition]::new(); $c0.Width = [Windows.GridLength]::new(72)
    $c1 = [Windows.Controls.ColumnDefinition]::new(); $c1.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
    [void]$g.ColumnDefinitions.Add($c0); [void]$g.ColumnDefinitions.Add($c1)
    $l = [Windows.Controls.TextBlock]::new()
    $l.Text = $label
    $l.Width = 72
    $l.FontSize = 12
    $l.Foreground = $window.FindResource('Mu')
    $l.VerticalAlignment = [Windows.VerticalAlignment]::Top
    $v = [Windows.Controls.TextBlock]::new()
    $v.Text = $value
    $v.FontSize = 13
    $v.Foreground = $window.FindResource($(if ($value -eq 'Not available') { 'Mu' } else { 'Tx' }))
    $v.TextWrapping = [Windows.TextWrapping]::Wrap
    [Windows.Controls.Grid]::SetColumn($v, 1)
    [void]$g.Children.Add($l); [void]$g.Children.Add($v)
    [void]$sp.Children.Add($g)
}

function Add-Divider($card) {
    $d = [Windows.Controls.Border]::new()
    $d.Height = 1
    $d.Background = $window.FindResource('Bd')
    $d.Margin = [Windows.Thickness]::new(0, 12, 0, 12)
    [void]$card.Child.Children.Add($d)
}

function New-FailedSpecs {
    $na = 'Not available'
    return @{
        CPU = @{ _Status = 'Failed'; Model = $na; Cores = $na; Threads = $na; SpeedMHz = $na }
        RAM = @{ _Status = 'Failed'; TotalGB = $na; UsedGB = $na; FreeGB = $na }
        Windows = @{ _Status = 'Failed'; Edition = $na; Version = $na; Build = $na }
        GPU = @{ _Status = 'Failed'; Adapters = @() }
        Disk = @{ _Status = 'Failed'; Volumes = @() }
        Motherboard = @{ _Status = 'Failed'; Manufacturer = $na; Product = $na; BIOSVersion = $na; ReleaseDate = $na }
    }
}

function Update-Home {
    $HostName.Text = $env:COMPUTERNAME
    $Cards.Children.Clear()
    if ($null -eq $script:SpecData) {
        # first read of the session has not finished yet
        $card = New-Card 'CPU'; Add-Loading $card
        [void]$Cards.Children.Add($card)
        return
    }
    $na = 'Not available'
    $s = $script:SpecData.Specs

    # cpu card: model, cores / threads, clock
    $cpu = $s.CPU
    $card = New-Card 'CPU'
    Add-Headline $card $cpu.Model
    $hasC = ($null -ne $cpu.Cores -and [string]$cpu.Cores -ne $na)
    $hasT = ($null -ne $cpu.Threads -and [string]$cpu.Threads -ne $na)
    $cores = if ($hasC -and $hasT) { "$($cpu.Cores) / $($cpu.Threads) threads" } elseif ($hasC) { "$($cpu.Cores)" } elseif ($hasT) { "$($cpu.Threads) threads" } else { $na }
    Add-Row $card 'Cores' $cores
    Add-Row $card 'Speed' (Fmt-Num $cpu.SpeedMHz '0.00' 'GHz' 1000)
    [void]$Cards.Children.Add($card)

    # gpu card: one block per adapter, divider between blocks
    $card = New-Card 'GPU'
    $list = @($s.GPU.Adapters)
    if (-not $list.Count) { Add-Headline $card $na }
    for ($i = 0; $i -lt $list.Count; $i++) {
        $a = $list[$i]
        if ($i -gt 0) { Add-Divider $card }
        Add-Headline $card $a.Model
        Add-Row $card 'VRAM' (Fmt-Num $a.VRAM_GB '0.0' 'GB')
        Add-Row $card 'Driver' $a.DriverVersion
        if ([string]$a.Status -ne 'OK') { Add-Row $card 'Status' $a.Status }
    }
    [void]$Cards.Children.Add($card)

    # ram card: total, used, free
    $ram = $s.RAM
    $card = New-Card 'RAM'
    Add-Headline $card (Fmt-Num $ram.TotalGB '0.0' 'GB')
    Add-Row $card 'Used' (Fmt-Num $ram.UsedGB '0.0' 'GB')
    Add-Row $card 'Free' (Fmt-Num $ram.FreeGB '0.0' 'GB')
    [void]$Cards.Children.Add($card)

    # disk card: one block per fixed volume, divider between blocks
    $card = New-Card 'Disk'
    $list = @($s.Disk.Volumes)
    if (-not $list.Count) { Add-Headline $card $na }
    for ($i = 0; $i -lt $list.Count; $i++) {
        $v = $list[$i]
        if ($i -gt 0) { Add-Divider $card }
        $head = [string]$v.Drive
        if ($v.Label -is [string] -and -not [string]::IsNullOrWhiteSpace($v.Label)) { $head += '  ' + $v.Label }
        Add-Headline $card $head
        Add-Row $card 'Free' (Fmt-Num $v.FreeGB '0.0' 'GB')
        Add-Row $card 'Total' (Fmt-Num $v.TotalGB '0.0' 'GB')
        Add-Row $card 'File system' $v.FileSystem
    }
    [void]$Cards.Children.Add($card)

    # board card: maker + product, bios version and date
    $mb = $s.Motherboard
    $card = New-Card 'Board'
    $parts = @(@($mb.Manufacturer, $mb.Product) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and [string]$_ -ne $na })
    Add-Headline $card $(if ($parts.Count) { $parts -join ' ' } else { $na })
    Add-Row $card 'BIOS' $mb.BIOSVersion
    Add-Row $card 'Released' $mb.ReleaseDate
    [void]$Cards.Children.Add($card)

    # windows card: edition (without the leading Microsoft), version, build
    $win = $s.Windows
    $card = New-Card 'Windows'
    Add-Headline $card ([string]$win.Edition -replace '^Microsoft\s+', '')
    Add-Row $card 'Version' $win.Version
    Add-Row $card 'Build' $win.Build
    [void]$Cards.Children.Add($card)
}

function Start-SpecRead {
    # one read in flight at a time
    if ($script:SpecJob) { return }
    # a tweak is running: defer the read until it finishes
    if ($script:Busy) { $script:SpecPending = $true; return }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $resultCollection = [System.Management.Automation.PSDataCollection[object]]::new()
    [void]$ps.AddScript($SpecReadCode)
    # ps 5.1 cannot bind the generic BeginInvoke overload with $null input, pass an empty completed collection
    $inputCollection = [System.Management.Automation.PSDataCollection[object]]::new()
    $inputCollection.Complete()
    $script:SpecJob = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke($inputCollection, $resultCollection); ResultCollection = $resultCollection }
    $script:SpecPending = $false
}

$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    $m = $null
    while ($script:Queue.TryDequeue([ref]$m)) { Add-Log $m }
    # home spec read finished: store the composite and redraw only the cards
    $sj = $script:SpecJob
    if ($sj -and $sj.Handle.IsCompleted) {
        $had = ($null -ne $script:SpecData)
        $ok = $false
        $msg = $null
        try {
            [void]$sj.Ps.EndInvoke($sj.Handle)
            $result = $sj.ResultCollection
            if ($null -ne $result -and $result.Count -gt 0) {
                $last = $result[$result.Count - 1]
                if ($last -is [hashtable] -and $last.ContainsKey('Specs')) { $script:SpecData = $last; $ok = $true }
                else { $msg = [string]$last }
            } else { $msg = 'no result returned' }
        } catch { $msg = $_.Exception.Message }
        foreach ($err in $sj.Ps.Streams.Error) { Add-Log "Error: $($err.ToString())" }
        $sj.Ps.Dispose(); $sj.Rs.Dispose()
        $script:SpecJob = $null
        if (-not $ok) {
            if (-not $msg) { $msg = 'no result returned' }
            if (-not $had) { $script:SpecData = @{ Specs = New-FailedSpecs; Host = @{ Manufacturer = 'Not available'; Model = 'Not available' } } }
            $tail = if ($had) { ' Showing last known values.' } else { ' Switch to another page and back to Home to try again.' }
            Add-Log "Specs: Read failed ($msg).$tail"
        }
        Update-Home
    }
    $j = $script:Job
    if ($j -and $j.Handle.IsCompleted) {
        try {
            if ($j.ResultVar) {
                [void]$j.Ps.EndInvoke($j.Handle)
                # output lands in the caller-supplied collection, endinvoke returns nothing
                $result = $j.ResultCollection
                if ($result -and $result.Count -gt 0) { $script:SpecData = $result[$result.Count - 1] } else { $script:SpecData = $null }
            } else { [void]$j.Ps.EndInvoke($j.Handle) }
        } catch { Add-Log "Error: $($_.Exception.Message)" }
        foreach ($err in $j.Ps.Streams.Error) { Add-Log "Error: $($err.ToString())" }
        while ($script:Queue.TryDequeue([ref]$m)) { Add-Log $m }
        $j.Ps.Dispose(); $j.Rs.Dispose()
        if ($j.Meta) { $script:State[$j.Meta.Id] = ($j.Meta.Kind -eq 'Apply'); Save-State }
        Add-Log "Done: $($j.Label)"
        $script:Job = $null
        Set-Busy $false
        Read-Svc
        Show-Page
        # a home read was requested while the tweak ran: start it now
        if ($script:SpecPending) { Start-SpecRead }
    }
})
$timer.Start()

function Confirm-Run([string]$text) {
    if (-not $text) { return $true }
    return ([Windows.MessageBox]::Show($text, 'Akari', 'YesNo', 'Warning') -eq 'Yes')
}

# ---- row buttons (one handler for every Optimize / Default button)
$Rows.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler] {
    param($s, $ev)
    $b = $ev.OriginalSource -as [Windows.Controls.Button]
    if (-not $b -or -not $b.Tag) { return }
    $id, $kind, $arg = ([string]$b.Tag).Split('|')
    $t = $script:Tweaks | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    if (-not $t) { return }
    $meta = if ($t.Kind -eq 'Toggle') { @{ Id = $id; Kind = $kind } } else { $null }
    switch ($kind) {
        'Apply'  { if ($t.Apply -and (Confirm-Run $t.Confirm)) { Invoke-Code $t.Apply.ToString() "$($t.Name): $(if ($t.Kind -eq 'Toggle') { 'optimize' } else { $t.Button.ToLower() })" $meta } }
        'Revert' { if ($t.Revert) { Invoke-Code $t.Revert.ToString() "$($t.Name): default" $meta } }
        'Check'  { if ($t.Check)  { Invoke-Code $t.Check.ToString() "$($t.Name): check" } }
        'Run'    {
            if ($t.Kind -eq 'Console') {
                $path = Join-Path $Root $t.Script
                Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$path`""
                Add-Log "$($t.Name): opened in its own console window"
            } elseif ($t.Apply -and (Confirm-Run $t.Confirm)) { Invoke-Code $t.Apply.ToString() "$($t.Name): $($t.Button.ToLower())" }
        }
        'Sub'    { $a = $t.Actions[[int]$arg]; if (Confirm-Run $a.Confirm) { Invoke-Code $a.Block.ToString() "$($t.Name): $($a.Name)" } }
        'Expand' {
            $row = $script:RowCache[$id]; $sub = $row.FindName('Sub'); $exp = $row.FindName('Exp')
            if ($sub.Visibility -eq 'Visible') { $sub.Visibility = 'Collapsed'; $exp.Content = 'Options' }
            else { $sub.Visibility = 'Visible'; $exp.Content = 'Hide' }
        }
    }
})

# ---- sidebar
foreach ($c in 'Home', 'Check', 'Refresh', 'Setup', 'Installers', 'Graphics', 'Windows', 'Hardware', 'Advanced') {
    $rb = [Windows.Controls.RadioButton]::new()
    $rb.Content = $c; $rb.Tag = $c; $rb.GroupName = 'nav'
    $rb.Style = $window.FindResource('Nav')
    [void]$Nav.Children.Add($rb)
    if ($c -eq 'Home') {
        # thin divider under home (not a nav item)
        $dv = [Windows.Controls.Border]::new()
        $dv.Height = 1
        $dv.Margin = [Windows.Thickness]::new(8, 8, 8, 8)
        $dv.Background = $window.FindResource('Bd')
        $dv.IsHitTestVisible = $false
        $dv.Focusable = $false
        [void]$Nav.Children.Add($dv)
    }
}
$Nav.AddHandler([Windows.Controls.Primitives.ToggleButton]::CheckedEvent, [Windows.RoutedEventHandler] {
    param($s, $ev)
    $script:Cat = [string]$ev.OriginalSource.Tag
    if ($Search.Text) { $Search.Text = '' }
    Show-Page
})
$Search.Add_TextChanged({ Show-Page })

# ---- Win32PrioritySeparation tuner
function Get-Chip([string]$g) {
    foreach ($i in 0..2) { if ($window.FindName("${g}_$i").IsChecked) { return $i } }
    return 0
}
function Update-Tuner {
    $v = ((Get-Chip QL) -shl 4) -bor ((Get-Chip QT) -shl 2) -bor (Get-Chip FB)
    $Hex.Text = '0x{0:X2}' -f $v
    $Dec.Text = "$v decimal"
    return $v
}
function Set-Chips([int]$v) {
    $want = @{ QL = ($v -shr 4) -band 3; QT = ($v -shr 2) -band 3; FB = $v -band 3 }
    foreach ($g in 'QL', 'QT', 'FB') {
        foreach ($i in 0..2) { $window.FindName("${g}_$i").IsChecked = ($i -eq $want[$g]) }
    }
    [void](Update-Tuner)
}
function Read-Prio {
    $cur = (Get-ItemProperty $PrioKey -Name Win32PrioritySeparation -ErrorAction SilentlyContinue).Win32PrioritySeparation
    if ($null -ne $cur) { Set-Chips ([int]$cur) } else { Set-Chips 2 }
}
function Set-Prio([int]$v) {
    $hex = '0x{0:X2}' -f $v
    Invoke-Code "Set-Reg '$PrioKey' 'Win32PrioritySeparation' $v`nWrite-Log 'Win32PrioritySeparation = $hex'" "Win32PrioritySeparation: setting $hex"
}
$Tuner.AddHandler([Windows.Controls.Primitives.ToggleButton]::CheckedEvent, [Windows.RoutedEventHandler] { [void](Update-Tuner) })
$Tuner.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler] {
    param($s, $ev)
    $b = $ev.OriginalSource -as [Windows.Controls.Button]
    if (-not $b) { return }
    switch ([string]$b.Tag) {
        'read'  { Read-Prio; Add-Log "Current Win32PrioritySeparation: $($Hex.Text)" }
        'def'   { Set-Chips 2; Set-Prio 2 }
        'apply' { Set-Prio (Update-Tuner) }
    }
})
Read-Prio

# ---- SvcHost split threshold tuner
$SvcKey = 'HKLM:\SYSTEM\CurrentControlSet\Control'
function Get-RamKB { [math]::Ceiling((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) * 1048576 }
function Get-SvcTarget {
    $i = 0; foreach ($k in 0..2) { if ($window.FindName("SV_$k").IsChecked) { $i = $k } }
    switch ($i) { 0 { [uint32]3670016 } 1 { [uint32](Get-RamKB) } 2 { [uint32]4294967295 } }
}
function Read-Svc {
    $cur = (Get-ItemProperty $SvcKey -Name SvcHostSplitThresholdInKB -ErrorAction SilentlyContinue).SvcHostSplitThresholdInKB
    $ramGB = [math]::Round((Get-RamKB) / 1048576)
    $txt = if ($null -ne $cur) { [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$cur), 0).ToString('N0') + ' KB' } else { 'not set' }
    $SvcCur.Text = "Current: $txt   |   RAM: $ramGB GB"
}
function Set-Svc([uint32]$v) {
    Invoke-Code "Set-Reg '$SvcKey' 'SvcHostSplitThresholdInKB' ([uint32]$v)`nWrite-Log 'SvcHostSplitThresholdInKB = $v (restart to apply)'" "SvcHost split threshold: setting $v KB"
}
$SvcTuner.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler] {
    param($s, $ev)
    $b = $ev.OriginalSource -as [Windows.Controls.Button]
    if (-not $b) { return }
    switch ([string]$b.Tag) {
        'read'  { Read-Svc }
        'def'   { $window.FindName('SV_0').IsChecked = $true; Set-Svc 3670016 }
        'apply' { Set-Svc (Get-SvcTarget) }
    }
})
$window.FindName('SV_0').IsChecked = $true
Read-Svc

# ---- go
$window.Add_Loaded({
    ($Nav.Children | Where-Object { $_.Tag -eq $script:Cat } | Select-Object -First 1).IsChecked = $true
    Add-Log 'Ready.'
    $script:Busy = $false
})
# errors inside button handlers: show them in the log drawer (and akari.log) instead of losing them
$window.Dispatcher.Add_UnhandledException({
    param($s, $ev)
    $ev.Handled = $true
    Write-ErrLog "UI error: $($ev.Exception.Message)"
    Add-Log "Error: $($ev.Exception.Message)"
    Set-Busy $false
})
$window.Add_Closing({ $timer.Stop() })
[void]$window.ShowDialog()
