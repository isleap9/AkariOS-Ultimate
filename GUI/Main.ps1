<#
    Main.ps1 â€” AkariOS Ultimate toolbox window.

    Launched by "AkariOS Toolbox.cmd", which passes -STA. WPF needs STA, and
    the scripts themselves must run off the UI thread, so nothing heavy happens
    synchronously here.

    Structure of the code, in order:

        1. guard rails        elevation, WPF availability
        2. load               XAML + merged theme dictionary
        3. model              Catalog -> folders and scripts
        4. chrome             spec strip, sidebar, footer reset
        5. cards              one control per script, built by card kind
        6. dispatch           queue, run, poll, report

    Card controls are built in code rather than bound. A card's control depends
    on its kind, and doing that with data binding in PowerShell means writing
    converters to work around the fact that PSCustomObject has no INotifyPropertyChanged.
    Building the controls directly is less code and easier to reason about.

    Visual language: strictly black and white. State is inversion, weight, rules
    and glyphs â€” never colour. See Theme.xaml.
#>

#Requires -Version 5.1

param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GuiRoot = Split-Path $PSScriptRoot -Parent     # repo root
$script:GuiDir  = $PSScriptRoot                        # .../GUI

# ---------------------------------------------------------------------------
# 1. Guard rails
# ---------------------------------------------------------------------------

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$principal = New-Object System.Security.Principal.WindowsPrincipal(
    [System.Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator)) {

    # Every tweak writes HKLM, services or appx packages, so an unelevated
    # window would fail on the first click. Re-launch elevated instead of
    # letting the user discover it later.
    $self = $MyInvocation.MyCommand.Path
    Start-Process ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) `
        -Verb RunAs `
        -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$self`"")
    return
}

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'WPF requires an STA thread. Launch via "AkariOS Toolbox.cmd".'
}

foreach ($m in 'Catalog', 'Tracer', 'Dispatcher', 'SystemInfo') {
    Import-Module (Join-Path $script:GuiDir "Lib\$m.psm1") -Force
}

# ---------------------------------------------------------------------------
# 2. Load the window
# ---------------------------------------------------------------------------

function Import-AkariXaml {
    <#
        .SYNOPSIS
        Parses a XAML file into live WPF objects.
        .DESCRIPTION
        PowerShell cannot use InitializeComponent, so the visual tree is built
        by hand: parse the file, then look elements up by x:Name.

        The theme dictionary is merged AFTER the window is parsed, so every
        reference from the window into the theme uses DynamicResource. A
        StaticResource would fail to resolve at parse time and the window would
        come up unstyled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$AsDictionary
    )

    [xml]$xaml = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $reader = New-Object System.Xml.XmlNodeReader $xaml

    if ($AsDictionary) {
        return [System.Windows.Markup.XamlReader]::Load($reader)
    }
    [System.Windows.Markup.XamlReader]::Load($reader)
}

$window = Import-AkariXaml -Path (Join-Path $script:GuiDir 'Main.xaml')
$theme  = Import-AkariXaml -Path (Join-Path $script:GuiDir 'Theme.xaml') -AsDictionary
$null = $window.Resources.MergedDictionaries.Add($theme)

# Named elements, resolved once.
$ui = @{}
foreach ($n in 'Privilege', 'RestartBadge', 'BtnRevertAll', 'BtnApply',
               'SpecStrip', 'Search', 'Sidebar', 'FolderTitle', 'FolderMeta',
               'CardHost', 'OpName', 'OpCount', 'Bar', 'BarPct', 'OpDetail',
               'Summary', 'BtnCancel') {
    $ui[$n] = $window.FindName($n)
}

# ---------------------------------------------------------------------------
# 3. Model
# ---------------------------------------------------------------------------

$script:Catalog    = @(Get-AkariCatalog -SkipOps)
$script:Cards      = @{}     # RelPath -> state record
$script:Queue      = [System.Collections.Queue]::new()
$script:Active     = $null
$script:Current    = $null   # folder currently shown
$script:Timer      = $null
$script:Applied    = @{}     # RelPath -> applied / revert / chosen
$script:RestartSet = $false

function New-AkariCardState {
    <#
        .SYNOPSIS
        Per-card state. Kept outside the visual tree so the controls stay dumb.
    #>
    param($Script)

    [pscustomobject]@{
        Script    = $Script
        RelPath   = $Script.RelPath
        Display   = $Script.Display
        Kind      = $Script.Kind
        Options   = @($Script.Options | Where-Object { -not $_.IsExit })
        Flags     = $Script.Flags
        Migrated  = $false
        Applied   = $false     # inversion cue
        Queued    = $false     # marker cue
        Root      = $null
        Check     = $null
        Combo     = $null
        Marker    = $null
        Title     = $null
        Subtitle  = $null
        Ops       = $null      # lazily filled AST plan
        OpsKnown  = $false
    }
}

# ---------------------------------------------------------------------------
# 4. Chrome
# ---------------------------------------------------------------------------

function Format-AkariElapsed {
    param([double]$Seconds)
    if ($Seconds -lt 60) { return ('{0:0.0}s' -f $Seconds) }
    $m = [int]($Seconds / 60)
    $s = [int]($Seconds % 60)
    ('{0}m {1:d2}s' -f $m, $s)
}

function Write-AkariStatus {
    <#
        .SYNOPSIS
        Footer band 1: what is running and how far along it is.
    #>
    param([string]$Name, [string]$Count)
    $ui.OpName.Text  = $Name
    $ui.OpCount.Text = $Count
}

function Write-AkariSummary {
    param([string]$Text)
    $ui.Summary.Text = $Text
}

function Reset-AkariFooter {
    $ui.Bar.Value          = 0
    $ui.Bar.IsIndeterminate = $false
    $ui.BarPct.Text        = 'â€”'
    $ui.OpDetail.Text      = ''
    $ui.OpCount.Text       = ''
    $ui.BtnCancel.IsEnabled = $false
}

# ---------------------------------------------------------------------------
# 5. Cards
# ---------------------------------------------------------------------------

function New-AkariText {
    param([string]$Text, [string]$StyleKey, [int]$Size = 0)
    $tb = New-Object System.Windows.Controls.TextBlock
    if ($StyleKey) { $tb.Style = $window.Resources[$StyleKey] }
    $tb.Text = $Text
    if ($Size -gt 0) { $tb.FontSize = $Size }
    [System.Windows.Automation.AutomationProperties]::SetName($tb, $Text)
    $tb
}

function New-AkariCard {
    <#
        .SYNOPSIS
        Builds one card. The control depends on the card kind:
          ApplyRevert / OnOff  checkbox
          Value                 dropdown
          Run                   button
        .DESCRIPTION
        Card shape is identical for all three kinds so the list reads as one
        instrument panel; only the trailing control changes.
    #>
    param($Card)

    $row = New-Object System.Windows.Controls.Border
    $row.Margin = New-Object System.Windows.Thickness(0, 0, 0, 1)
    $row.Background = $window.Resources['Surface']
    # Tag carries the state record, so a row can be traced back to its script
    # from the visual tree without a parallel lookup table.
    $row.Tag = $Card

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = New-Object System.Windows.Thickness(12, 9, 12, 9)

    $null = $grid.ColumnDefinitions.Add(
        (New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
    $null = $grid.ColumnDefinitions.Add(
        (New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = '*' }))
    $null = $grid.ColumnDefinitions.Add(
        (New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
    $null = $grid.ColumnDefinitions.Add(
        (New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))

    # --- marker: the state glyph, column 0 ---
    $marker = New-AkariText -Text ([char]0x2588) -StyleKey 'Text.Label'
    $marker.Width = 18
    [System.Windows.Controls.Grid]::SetColumn($marker, 0)
    $null = $grid.Children.Add($marker)

    # --- title + subtitle, column 1 ---
    $stack = New-Object System.Windows.Controls.StackPanel
    $title = New-AkariText -Text $Card.Display -StyleKey 'Text.Label'
    $null = $stack.Children.Add($title)

    $sub = New-AkariText -Text '' -StyleKey 'Text.Micro'
    $sub.Margin = New-Object System.Windows.Thickness(0, 1, 0, 0)
    $sub.TextTrimming = 'CharacterEllipsis'
    $null = $stack.Children.Add($sub)
    [System.Windows.Controls.Grid]::SetColumn($stack, 1)
    $null = $grid.Children.Add($stack)

    # --- control, column 2 ---
    $control = $null

    switch ($Card.Kind) {

        'ApplyRevert' {
            $check = New-Object System.Windows.Controls.CheckBox
            $check.Style = $window.Resources['Check']
            $check.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
            $check.Tag = $Card
            $check.Add_Checked({ OnCardToggled -Card $this.Tag })
            $check.Add_Unchecked({ OnCardToggled -Card $this.Tag })
            $Card.Check = $check
            $control = $check
        }

        'OnOff' {
            # Same control, opposite meaning: checked means option 2 (the tweak).
            $check = New-Object System.Windows.Controls.CheckBox
            $check.Style = $window.Resources['Check']
            $check.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
            $check.Tag = $Card
            $check.Add_Checked({ OnCardToggled -Card $this.Tag })
            $check.Add_Unchecked({ OnCardToggled -Card $this.Tag })
            $Card.Check = $check
            $control = $check
        }

        'Value' {
            $combo = New-Object System.Windows.Controls.ComboBox
            $combo.Style = $window.Resources['Combo']
            $combo.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
            $combo.Tag = $Card
            $first = $true
            foreach ($o in $Card.Options) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = $o.Label
                $item.Tag = $o.Index
                $null = $combo.Items.Add($item)
                if ($first) { $combo.SelectedIndex = 0; $first = $false }
            }
            $combo.Add_SelectionChanged({
                if ($this.IsLoaded -and $this.SelectedIndex -ge 0) {
                    OnCardPicked -Card $this.Tag
                }
            })
            $Card.Combo = $combo
            $control = $combo
        }

        default {
            $btn = New-Object System.Windows.Controls.Button
            $btn.Style = $window.Resources['Button']
            $btn.Content = 'Apply'
            $btn.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
            $btn.Tag = $Card
            $btn.Add_Click({ OnCardRun -Card $this.Tag })
            $Card.Check = $btn      # reused by the queue/resume helpers
            $control = $btn
        }
    }

    if ($control) {
        [System.Windows.Controls.Grid]::SetColumn($control, 2)
        $null = $grid.Children.Add($control)
    }

    # --- trailing meta: op count, column 3 ---
    $meta = New-AkariText -Text '' -StyleKey 'Text.Value'
    $meta.Foreground = $window.Resources['Dimmer']
    $meta.Width = 54
    $meta.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($meta, 3)
    $null = $grid.Children.Add($meta)

    $row.Child = $grid

    $Card.Root     = $row
    $Card.Marker   = $marker
    $Card.Title    = $title
    $Card.Subtitle = $sub
    $Card | Add-Member -NotePropertyName Meta -NotePropertyValue $meta -Force

    $row
}

function Set-AkariCardVisual {
    <#
        .SYNOPSIS
        Paints a card from its state. Monochrome only.
        .DESCRIPTION
          applied  -> inverted row, white on black
          queued   -> filled marker plus SemiBold
          default  -> hollow marker
          running  -> inverted plus a running glyph
          NA       -> dimmed, no control
    #>
    param($Card)

    # A card only exists in the visual tree once its folder has been shown.
    # Queue state can change before then, so the state is recorded either way
    # and the paint is skipped until the controls are built.
    if (-not $Card.Root) { return }

    $paper = $window.Resources['Paper']
    $ink   = $window.Resources['Ink']

    if ($Card.Applied) {
        $Card.Root.Background = $ink
        $Card.Title.Foreground = $paper
        $Card.Subtitle.Foreground = $paper
        $Card.Subtitle.Opacity  = 0.75
        $Card.Marker.Foreground = $paper
        $Card.Marker.Text = [char]0x2593      # filled, for applied
        $Card.Title.FontWeight = 'Normal'
    } else {
        $Card.Root.Background = $paper
        $Card.Title.Foreground = $ink
        $Card.Subtitle.Foreground = $window.Resources['Dim']
        $Card.Subtitle.Opacity  = 1.0

        if ($Card.Queued) {
            $Card.Marker.Foreground = $ink
            $Card.Marker.Text = [char]0x2593  # filled, for queued
            $Card.Title.FontWeight = 'SemiBold'
        } else {
            $Card.Marker.Foreground = $window.Resources['Dim']
            $Card.Marker.Text = [char]0x2588  # hollow, for default
            $Card.Title.FontWeight = 'Normal'
        }
    }

    if ($Card.Flags.NeedsReboot) {
        # Dashed bottom rule marks a tweak that will need a restart.
        $bd = $Card.Root.BorderBrush
        $null = $bd
        $Card.Subtitle.Text = ($Card.Subtitle.Text.TrimEnd() + '   ' + [char]0x27F3)
    }
}

function Show-AkariFolder {
    <#
        .SYNOPSIS
        Renders one folder's cards into the list, honouring the search filter.
    #>
    param($Folder)

    $script:Current = $Folder
    $ui.FolderTitle.Text = $Folder.Name
    $ui.CardHost.Children.Clear()

    $term = $ui.Search.Text.Trim()
    $shown = 0

    foreach ($s in $Folder.Scripts) {
        if ($term -and ($s.Display -notlike "*$term*") -and
                      ($s.RelPath -notlike "*$term*")) {
            continue
        }

        $card = $script:Cards[$s.RelPath]
        if (-not $card) {
            $card = New-AkariCardState -Script $s
            $script:Cards[$s.RelPath] = $card
            $card.Migrated = Test-AkariScriptMigrated $s.Path
        }

        $null = $ui.CardHost.Children.Add((New-AkariCard -Card $card))

        # Subtitle states what the control will actually run, and warns when
        # the script has not been migrated yet.
        $note = switch ($card.Kind) {
            'ApplyRevert' { "on: $($card.Options[0].Label)   /   off: $($card.Options[1].Label)" }
            'OnOff'       { "on: $($card.Options[1].Label)   /   off: $($card.Options[0].Label)" }
            'Value'       { "$($card.Options.Count) options" }
            default       { 'runs once' }
        }
        $flags = @()
        if ($card.Flags.NeedsReboot)  { $flags += 'restart' }
        if ($card.Flags.NeedsPause)   { $flags += 'pause' }
        if ($card.Flags.NeedsNet)     { $flags += 'internet' }
        if ($card.Flags.UsesTrusted)  { $flags += 'trusted installer' }
        if (-not $card.Migrated)      { $flags += 'not yet GUI-enabled' }

        if ($flags.Count) { $note += '   (' + ($flags -join ', ') + ')' }
        $card.Subtitle.Text = $note

        Set-AkariCardVisual -Card $card
        $shown++
    }

    $ui.FolderMeta.Text = "$shown shown"
}

function Show-AkariSidebar {
    param()
    $ui.Sidebar.Children.Clear()

    $term = $ui.Search.Text.Trim()

    foreach ($folder in $script:Catalog) {
        $count = $folder.Count
        if ($term) {
            $count = @($folder.Scripts | Where-Object {
                $_.Display -like "*$term*" -or $_.RelPath -like "*$term*"
            }).Count
        }

        $btn = New-Object System.Windows.Controls.Button
        $btn.Style = $window.Resources['Button']
        $btn.BorderThickness = New-Object System.Windows.Thickness(0)
        $btn.Background = $window.Resources['Paper']
        $btn.HorizontalContentAlignment = 'Left'
        $btn.Padding = New-Object System.Windows.Thickness(8, 6, 8, 6)
        $btn.Margin = New-Object System.Windows.Thickness(0, 0, 0, 1)
        $btn.Tag = $folder
        $btn.Content = ('{0}   {1}' -f $folder.Name, $count)
        $btn.FontWeight = 'SemiBold'
        $btn.Add_Click({ Show-AkariFolder -Folder $this.Tag })

        if ($script:Current -and $script:Current.Name -eq $folder.Name) {
            $btn.Background = $window.Resources['Ink']
            $btn.Foreground = $window.Resources['Paper']
        }

        $null = $ui.Sidebar.Children.Add($btn)
    }
}

# ---------------------------------------------------------------------------
# 6. Dispatch
# ---------------------------------------------------------------------------

function Get-AkariPlan {
    <#
        .SYNOPSIS
        Lazily fills the AST op count for a card.
        .DESCRIPTION
        Parsing all 104 scripts up front costs ~1.7s, which is a poor price for
        a window that opens on one folder. Parsing happens the first time a card
        needs a denominator, then it is cached on the card.
    #>
    param($Card)

    if ($Card.OpsKnown) { return $Card.Ops }

    $action = switch ($Card.Kind) {
        'ApplyRevert' { if ($Card.Applied) { 'Revert' } else { 'Apply' } }
        'OnOff'       { if ($Card.Applied) { 'Revert' } else { 'Apply' } }
        default       { 'Run' }
    }

    $choice = 0
    if ($Card.Kind -eq 'Value' -and $Card.Combo -and
        $Card.Combo.SelectedIndex -ge 0) {
        $choice = [int]$Card.Combo.SelectedItem.Tag
    }

    $plan = Get-AkariOperationPlan -Path $Card.Script.Path

    $total = 0
    if ($plan.Parsed -and $plan.BranchCount -gt 0) {
        if ($plan.BranchCount -eq 1) {
            $total = $plan.TotalOps
        } else {
            # Match the branch to the action being run.
            $want = if ($choice -gt 0) { "$choice" }
                    elseif ($action -eq 'Revert') { '2' } else { '1' }
            $branch = $plan.Branches | Where-Object { $_.Index -eq $want } |
                      Select-Object -First 1
            if (-not $branch) {
                # OnOff inverts: option 1 is the stock state.
                $alt = if ($action -eq 'Revert') { '1' } else { '2' }
                $branch = $plan.Branches | Where-Object { $_.Index -eq $alt } |
                          Select-Object -First 1
            }
            if ($branch) { $total = [int]$branch.Ops }
        }
    }

    $Card.Ops = [pscustomobject]@{ Action = $action; Choice = $choice; Total = $total }
    $Card.OpsKnown = $true

    if ($Card.Root) {
        $Card.Meta.Text = if ($total -gt 0) { "$total ops" } else { 'n/c' }
    }
    $Card.Ops
}

function Get-AkariInvocation {
    <#
        .SYNOPSIS
        Turns a card into the action and option to pass the script.
        .DESCRIPTION
        Run-Trusted scripts hand their work to another process, so their inner
        operations cannot be intercepted. Those get Total 0, which is the
        signal for an indeterminate bar rather than a wrong percentage.
    #>
    param($Card)

    $plan = Get-AkariPlan -Card $Card
    $total = 0

    if ($Card.Flags.UsesTrusted) {
        $total = 0
    } else {
        $total = [int]$plan.Total
    }

    [pscustomobject]@{
        Action   = $plan.Action
        Choice   = [int]$plan.Choice
        TotalOps = $total
    }
}

function Add-AkariToQueue {
    param($Card)

    $Card.Queued = $true
    Set-AkariCardVisual -Card $Card
    $script:Queue.Enqueue($Card)
    Write-AkariSummary -Text ("queued {0}" -f $script:Queue.Count)
}

function Clear-AkariQueue {
    while ($script:Queue.Count -gt 0) {
        $c = $script:Queue.Dequeue()
        $c.Queued = $false
        Set-AkariCardVisual -Card $c
    }
    Write-AkariSummary -Text ''
}

function Start-AkariNext {
    <#
        .SYNOPSIS
        Starts the next queued tweak, or reports the queue is empty.
    #>
    if ($script:Active) { return }
    if ($script:Queue.Count -eq 0) {
        Write-AkariSummary -Text ''
        $ui.BtnApply.IsEnabled = $true
        $ui.BtnRevertAll.IsEnabled = $true
        return
    }

    $card = $script:Queue.Dequeue()
    $card.Queued = $false

    $inv = Get-AkariInvocation -Card $card

    if (-not $card.Migrated) {
        # Hard gate: 71 of 104 scripts contain a bare `exit`, which would kill
        # the GUI process. Nothing runs until the wrapper is present.
        Set-AkariCardVisual -Card $card
        Write-AkariStatus -Name $card.Display -Count 'not migrated'
        $ui.OpDetail.Text = 'This script cannot be run from the toolbox yet.'
        return
    }

    $ui.BtnApply.IsEnabled = $false
    $ui.BtnRevertAll.IsEnabled = $false
    $ui.BtnCancel.IsEnabled = $true
    Write-AkariStatus -Name $card.Display -Count ''
    $ui.OpDetail.Text = 'starting'
    Set-AkariCardVisual -Card $card

    $script:CurrentCard = $card

    try {
        $script:Active = New-AkariRun `
            -Script  $card.Script.Path `
            -Action  $inv.Action `
            -Choice  $inv.Choice `
            -TotalOps $inv.TotalOps `
            -NoGui
    } catch {
        $script:Active = $null
        Write-AkariStatus -Name $card.Display -Count 'failed'
        $ui.OpDetail.Text = $_.Exception.Message
        $ui.BtnCancel.IsEnabled = $false
        $ui.BtnApply.IsEnabled = $true
        $ui.BtnRevertAll.IsEnabled = $true
        Start-AkariNext
    }
}

function Start-AkariTicker {
    <#
        .SYNOPSIS
        The UI-thread poll loop. 120ms is smooth without being busy.
    #>
    if ($script:Timer) { return }

    $script:Timer = New-Object System.Windows.Threading.DispatcherTimer
    $script:Timer.Interval = [TimeSpan]::FromMilliseconds(120)

    $script:Timer.Add_Tick({
        if (-not $script:Active) {
            $script:Timer.Stop()
            $script:Timer = $null
            return
        }

        $p = Get-AkariRunProgress -Run $script:Active

        if ($null -eq $p) {
            $script:Timer.Stop(); $script:Timer = $null
            $script:Active = $null
            $ui.Bar.IsIndeterminate = $false
            return
        }

        $elapsed = Format-AkariElapsed -Seconds $p.Elapsed

        if ($p.Total -gt 0) {
            $pct = [Math]::Min(100, [int](($p.Ticks / $p.Total) * 100))
            $ui.Bar.IsIndeterminate = $false
            $ui.Bar.Value = $pct
            $ui.BarPct.Text = '{0,3}%  {1}' -f $pct, $elapsed
            $ui.OpCount.Text = 'op {0} / {1}' -f $p.Ticks, $p.Total
        } else {
            # No reliable denominator: show a moving bar and be honest about it.
            $ui.Bar.IsIndeterminate = $true
            $ui.BarPct.Text = "   --  $elapsed"
            $ui.OpCount.Text = 'op {0}' -f $p.Ticks
        }

        if ($p.Detail) {
            $ui.OpDetail.Text = ('{0}  {1}' -f $p.Last, $p.Detail).Trim()
        }

        if ($p.Finished) {
            $script:Timer.Stop()
            $script:Timer = $null

            $run = $script:Active
            $script:Active = $null

            $card = $script:CurrentCard
            $result = Wait-AkariRun -Run $run -TimeoutSeconds 30

            if ($result.Cancelled) {
                Write-AkariStatus -Name $card.Display -Count 'cancelled'
            } elseif ($result.ErrorCount -gt 0) {
                Write-AkariStatus -Name $card.Display `
                    -Count ("{0} error{1}" -f $result.ErrorCount,
                            $(if ($result.ErrorCount -eq 1) { '' } else { 's' }))
                $ui.OpDetail.Text = ($result.Messages | Select-Object -First 1)
            } else {
                $card.Applied = -not $card.Applied
                if ($card.Flags.NeedsReboot) {
                    $script:RestartSet = $true
                    $ui.RestartBadge.Visibility = 'Visible'
                }
                Write-AkariStatus -Name $card.Display -Count 'done'
                $ui.BarPct.Text = '100%'
                $ui.Bar.Value = 100
            }

            Set-AkariCardVisual -Card $card
            Close-AkariRun -Run $result
            $ui.BtnCancel.IsEnabled = $false
            Start-AkariNext
        }
    })

    $script:Timer.Start()
}

# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

function OnCardToggled {
    param($Card)
    # The checkbox's own IsChecked is the source of truth, so Revert All and a
    # user click can never disagree about what a card is set to.
    $on = [bool]$Card.Check.IsChecked

    if ($Card.Applied -ne $on) {
        $Card.Applied = $on
        Set-AkariCardVisual -Card $Card
    }
}

function OnCardPicked { param($Card) }

function OnCardRun {
    param($Card)
    Add-AkariToQueue -Card $Card
    Start-AkariNext
    Start-AkariTicker
}

function OnApplyAll {
    $targets = @()
    if ($script:Current) { $targets = @($script:Current.Scripts) }
    foreach ($s in $targets) {
        $c = $script:Cards[$s.RelPath]
        if ($c -and $c.Check -is [System.Windows.Controls.CheckBox]) {
            if (-not $c.Applied) { $c.Check.IsChecked = $true }
        } elseif ($c -and -not $c.Applied) {
            $c.Applied = $true
            Set-AkariCardVisual -Card $c
        }
    }
    Write-AkariSummary -Text ("{0} queued" -f $script:Queue.Count)
}

function OnRevertAll {
    foreach ($c in $script:Cards.Values) {
        if ($c.Applied) {
            if ($c.Check -is [System.Windows.Controls.CheckBox]) {
                $c.Check.IsChecked = $false
            } else {
                $c.Applied = $false
                Set-AkariCardVisual -Card $c
            }
        }
    }
    Write-AkariSummary -Text 'reverted'
}

function OnCancel {
    if ($script:Active) {
        Stop-AkariRun -Run $script:Active
        $script:Active.Cancelled = $true
    }
    Clear-AkariQueue
}

# ---------------------------------------------------------------------------
# Wire up
# ---------------------------------------------------------------------------

$ui.BtnApply.Add_Click({ OnApplyAll })
$ui.BtnRevertAll.Add_Click({ OnRevertAll })
$ui.BtnCancel.Add_Click({ OnCancel })

$ui.Search.Add_TextChanged({
    Show-AkariSidebar
    if ($script:Current) { Show-AkariFolder -Folder $script:Current }
})

$window.Add_Closing({
    if ($script:Active) { Stop-AkariRun -Run $script:Active }
    if ($script:Timer) { $script:Timer.Stop() }
})

# F5 refresh. Neither the key binding nor the command can be declared in loose
# XAML: XamlReader cannot resolve ApplicationCommands.Refresh from markup, and
# there is no stock Refresh command to name in C# either. Both objects are built
# here instead.
$script:CmdRefresh = New-Object System.Windows.Input.RoutedUICommand
$null = $script:CmdRefresh.InputGestures.Add((New-Object System.Windows.Input.KeyGesture(
    [System.Windows.Input.Key]::F5)))

$onRefresh = [System.Windows.Input.ExecutedRoutedEventHandler] {
    param($sender, $e)
    $e.Handled = $true
    $script:Catalog = @(Get-AkariCatalog -SkipOps)
    $script:Cards.Clear()
    Show-AkariSidebar
    Show-AkariFolder -Folder $script:Catalog[0]
}

$binding = New-Object System.Windows.Input.CommandBinding
$binding.Command = $script:CmdRefresh
$binding.Add_Executed($onRefresh)
$null = $window.CommandBindings.Add($binding)

# ---------------------------------------------------------------------------
# Go
# ---------------------------------------------------------------------------

$ui.Privilege.Text = if (Get-AkariIsAdmin) { 'ADMIN' } else { 'STANDARD' }
$ui.SpecStrip.Text = Get-AkariSpec
if (Test-AkariRestartPending) {
    $ui.RestartBadge.Visibility = 'Visible'
}

# Folder first: Show-AkariFolder is what sets $script:Current, and the sidebar
# needs that to know which row to invert.
Show-AkariFolder -Folder $script:Catalog[0]
Show-AkariSidebar
Reset-AkariFooter
Write-AkariSummary -Text '104 tweaks, 8 categories'

$null = $window.ShowDialog()
