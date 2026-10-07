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
trap { [void][Windows.MessageBox]::Show("Akari hit an error:`n`n$($_.Exception.Message)`n`n$($_.InvocationInfo.PositionMessage)", 'Akari'); exit }
# remove 'downloaded from the internet' marks so Windows never nags about these files
Get-ChildItem $Root -Filter *.ps1 -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
foreach ($sub in 'Tweaks', 'UI') { Get-ChildItem "$Root\$sub" -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue }
$script:Tweaks = [System.Collections.Generic.List[object]]::new()
$script:RowCache   = @{}
$script:Cat    = 'Windows'
$script:Busy   = $false
$script:Job    = $null
$script:Queue  = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
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

# ---- window
$window = [Windows.Markup.XamlReader]::Parse((Get-Content "$Root\UI\MainWindow.xaml" -Raw))
foreach ($n in 'Nav', 'Search', 'Heading', 'Tuner', 'SvcTuner', 'SvcCur', 'Rows', 'Page', 'Log', 'Hex', 'Dec', 'Logo') { Set-Variable $n $window.FindName($n) }

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
    foreach ($t in $list) {
        if (-not $script:RowCache.ContainsKey($t.Id)) { $script:RowCache[$t.Id] = New-Row $t }
        [void]$Rows.Children.Add($script:RowCache[$t.Id])
        Update-Row $t
    }
    if (-not $list.Count -and -not $adv) {
        $msg = [Windows.Controls.TextBlock]::new()
        $msg.Text = if ($q) { 'No scripts match.' } else { 'Nothing here yet.' }
        $msg.Foreground = $window.FindResource('Mu')
        [void]$Rows.Children.Add($msg)
    }
}

# ---- running actions in a background runspace
function Set-Busy([bool]$b) { $script:Busy = $b; $Page.IsEnabled = -not $b }

function Invoke-Code([string]$code, [string]$label, $meta = $null) {
    if ($script:Busy) { return }
    Set-Busy $true
    Add-Log $label
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('LogQueue', $script:Queue)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $wrapped = $Helpers + "`ntry {`n& {`n" + $code + "`n} *>&1 | Out-String -Stream | ForEach-Object { if (`$_.Trim()) { Write-Log `$_ } }`n} catch { Write-Log ('Error: ' + `$_.Exception.Message) }"
    [void]$ps.AddScript($wrapped)
    $script:Job = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke(); Label = $label; Meta = $meta }
}

$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    $m = $null
    while ($script:Queue.TryDequeue([ref]$m)) { Add-Log $m }
    $j = $script:Job
    if ($j -and $j.Handle.IsCompleted) {
        try { [void]$j.Ps.EndInvoke($j.Handle) } catch { Add-Log "Error: $($_.Exception.Message)" }
        foreach ($err in $j.Ps.Streams.Error) { Add-Log "Error: $($err.ToString())" }
        while ($script:Queue.TryDequeue([ref]$m)) { Add-Log $m }
        $j.Ps.Dispose(); $j.Rs.Dispose()
        if ($j.Meta) { $script:State[$j.Meta.Id] = ($j.Meta.Kind -eq 'Apply'); Save-State }
        Add-Log "Done: $($j.Label)"
        $script:Job = $null
        Set-Busy $false
        Read-Svc
        Show-Page
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
foreach ($c in 'Check', 'Refresh', 'Setup', 'Installers', 'Graphics', 'Windows', 'Hardware', 'Advanced') {
    $rb = [Windows.Controls.RadioButton]::new()
    $rb.Content = $c; $rb.Tag = $c; $rb.GroupName = 'nav'
    $rb.Style = $window.FindResource('Nav')
    [void]$Nav.Children.Add($rb)
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
$window.Add_Closing({ $timer.Stop() })
[void]$window.ShowDialog()
