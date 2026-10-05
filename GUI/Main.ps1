<#
    Main.ps1 — AkariOS Ultimate toolbox window.

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
    and glyphs — never colour. See Theme.xaml.
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

foreach ($m in 'Catalog', 'Tracer', 'Menu', 'Dispatcher', 'SystemInfo') {
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
               'Summary', 'BtnLog', 'BtnCancel',
               'LogPanel', 'LogBox', 'LogHint',
               'BtnCopyLog', 'BtnSaveLog', 'BtnClearLog', 'BtnHideLog') {
    $ui[$n] = $window.FindName($n)
}

# ---------------------------------------------------------------------------
# 2b. Diagnostic log
# ---------------------------------------------------------------------------
#
# The tweaks run on the user's machine, not mine, so when one fails the only
# route back to a fix is text they can paste. That means the log has to hold the
# whole failure, not a summary line: the exception message, the script's own
# output, and enough context to tell which of the 104 scripts it was.
#
# Two sinks, because either alone has a gap:
#
#   on screen   read immediately, but lost if the window closes
#   file        survives a crash, so a hang that killed the process still
#               leaves the last thing it was doing on disk
#
# Monochrome, so levels are marked by glyph and case, not colour: ! warn,
# x fail, - note.

$script:LogLines = New-Object System.Collections.Generic.List[string]
$script:LogLimit = 4000          # ring: an unbounded log is a memory leak
$script:LogPath  = Join-Path $script:GuiDir 'toolbox.log'

# Last intercepted command shown in the console. Held here rather than locally
# so the tick handler - which runs outside any function scope - can reach it, and
# so a repeated command is not logged twice.
$script:LastDoing = ''

function Write-AkariLog {
    <#
        .SYNOPSIS
        Appends a timestamped line to the diagnostic log.

        .PARAMETER Text
        The line. Multi-line strings are split so every line is timestamped.

        .PARAMETER Level
        info | warn | fail | cmd. Only changes the glyph, never the colour.

        .NOTES
        Wrapped in its own try/catch on purpose. A logger that can throw will
        take down the operation it was supposed to describe, and a tweak that
        ran is better than a tweak that reported a logging failure instead.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [ValidateSet('info', 'warn', 'fail', 'cmd')][string]$Level = 'info'
    )

    try {
        $glyph = switch ($Level) {
            'warn' { '!' }
            'fail' { 'x' }
            'cmd'  { '>' }
            default { '-' }
        }

        $ts = (Get-Date).ToString('HH:mm:ss.fff')
        $stamp = "[$ts] $glyph "

        foreach ($line in ($Text -split "`r?`n")) {
            $full = $stamp + $line
            $script:LogLines.Add($full)

            # Trim from the front, so the newest lines are always kept and the
            # buffer cannot grow without bound over a long session.
            while ($script:LogLines.Count -gt $script:LogLimit) {
                $script:LogLines.RemoveAt(0)
            }

            Add-Content -LiteralPath $script:LogPath -Value $full -Encoding UTF8 `
                -ErrorAction SilentlyContinue
        }

        if ($ui -and $ui.LogBox) {
            $ui.LogBox.Text = [string]::Join("`n", $script:LogLines)
            $ui.LogBox.CaretIndex = $ui.LogBox.Text.Length
            $ui.LogBox.ScrollToCaret()
        }
    } catch {
        # Deliberately silent. See .NOTES.
    }
}

function Get-AkariLogText {
    <#
        .SYNOPSIS
        The full log, prefixed with the machine context.

        .DESCRIPTION
        This is what lands on the clipboard. The header is not decoration: two
        of the failure modes seen so far are machine-specific - unelevated, and
        a console preamble that only throws when there is no console host - so
        the elevation state and OS build belong in the paste, otherwise a
        failure has to be reproduced before it can be understood.
    #>
    # Read the version straight off .NET rather than through Get-AkariSpec,
    # which returns a preformatted display string, not fields to interpolate.
    $os = [System.Environment]::OSVersion.Version
    $bits = if ([System.Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $admin = Get-AkariIsAdmin

    $head = @(
        '=== AkariOS Ultimate Toolbox diagnostic log ==='
        "generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "machine   : $env:COMPUTERNAME"
        "user      : $env:USERNAME"
        "os        : $($os.Version) $bits"
        "elevated  : $admin"
        "powershell: $($PSVersionTable.PSVersion)"
        "host proc : $([System.Diagnostics.Process]::GetCurrentProcess().ProcessName)"
        "log file  : $script:LogPath"
        ''
    ) -join "`n"

    $head + [string]::Join("`n", $script:LogLines)
}

function Clear-AkariLog {
    $script:LogLines.Clear()
    if ($ui -and $ui.LogBox) { $ui.LogBox.Clear() }
    Remove-Item -LiteralPath $script:LogPath -Force -ErrorAction SilentlyContinue
    Write-AkariLog -Text 'log cleared'
}

function Set-AkariLogVisible {
    param([bool]$Visible)
    $ui.LogPanel.Visibility = if ($Visible) { 'Visible' } else { 'Collapsed' }
    if ($Visible) { $ui.LogBox.Focus() }
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
        MenuShape = 'Unknown'  # Menu or Direct, from the AST
        Applied   = $false     # inversion cue
        Queued    = $false     # marker cue
        Root      = $null
        Check     = $null
        Combo     = $null
        Run       = $null    # Value cards only: the button beside the dropdown
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
    $ui.BarPct.Text        = '—'
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
            # Checked/Unchecked only record intent. Click is what actually runs
            # the tweak, and it has to be wired separately: without it the box
            # flips and nothing else happens, which reads as a checkbox that does
            # not work. Click fires after Checked/Unchecked, so by the time this
            # runs, Card.Applied already reflects the new state and
            # Get-AkariMenuAnswer picks the right branch.
            $check.Add_Click({ Start-AkariWithConsole $this.Tag })
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
            $check.Add_Click({ Start-AkariWithConsole $this.Tag })
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
                # Exit is never a real choice. Offering it would let the user
                # pick "Exit" from a dropdown and watch the script do nothing,
                # which is the same failure as a dead checkbox. Bloatware's Exit
                # is option 1 and Installers' is option 28, so this is not
                # hypothetical.
                if ($o.IsExit) { continue }
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

            # Choosing from the dropdown only records the selection. A button is
            # needed beside it, or a Value script has no way to be started at
            # all - there is no checkbox to click and no menu to drive.
            $run = New-Object System.Windows.Controls.Button
            $run.Style = $window.Resources['Button']
            $run.Content = 'Run'
            $run.Tag = $Card
            $run.Add_Click({ Start-AkariWithConsole $this.Tag })
            $Card.Run = $run

            $pair = New-Object System.Windows.Controls.StackPanel
            $pair.Orientation = 'Horizontal'
            $null = $pair.Children.Add($combo)
            $null = $pair.Children.Add($run)
            $control = $pair
        }

        default {
            $btn = New-Object System.Windows.Controls.Button
            $btn.Style = $window.Resources['Button']
            $btn.Content = 'Apply'
            $btn.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
            $btn.Tag = $Card
            $btn.Add_Click({ Start-AkariWithConsole $this.Tag })
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
            # Every script is runnable: none are edited, and the menu is driven
            # by a shim. The shape is recorded only to decide whether an answer
            # needs sending at all.
            $card.MenuShape = Test-AkariMenuShape -Path $s.Path
        }

        $null = $ui.CardHost.Children.Add((New-AkariCard -Card $card))

        # Subtitle states what the control will actually run.
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
        if ($card.MenuShape -eq 'Direct') { $flags += 'no prompt' }

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
        Turns a card into the option index to answer with, plus the op count.
        .DESCRIPTION
        There is no action or choice parameter here, because the tweak scripts are
        not given any. They are run unedited; the branch is selected by answering
        their own Read-Host prompt with an option index. See Menu.psm1.

        Run-Trusted scripts hand their work to a separate process, so their inner
        operations cannot be intercepted. Those get Total 0, which is the signal
        for an indeterminate bar rather than a wrong percentage.
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
        Answer   = [int](Get-AkariMenuAnswer -Card $Card)
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

    $ui.BtnApply.IsEnabled = $false
    $ui.BtnRevertAll.IsEnabled = $false
    $ui.BtnCancel.IsEnabled = $true
    Write-AkariStatus -Name $card.Display -Count ''
    $ui.OpDetail.Text = 'starting'
    Set-AkariCardVisual -Card $card

    $script:CurrentCard = $card

    # Everything needed to diagnose a failure goes in before the run starts:
    # which script, which answer, and what the state was beforehand. Answering
    # with the wrong index is the single most likely failure mode here, and it
    # is invisible unless it is written down.
    # Built with -f and an explicit [int], not string interpolation. "$inv.Answer"
    # interpolates the whole object as "@{Answer=2; TotalOps=2}.Answer", which is
    # unreadable in a bug report - and this line is exactly what gets pasted.
    $idx = [int]$inv.Answer
    $want = if ($card.Kind -eq 'Run') {
        'run once'
    } elseif ($idx -eq 0) {
        'option 0'
    } elseif ($card.Applied) {
        'option {0} (turn the tweak ON)' -f $idx
    } else {
        'option {0} (turn the tweak OFF)' -f $idx
    }
    Write-AkariLog -Text ("RUN  {0}" -f $card.RelPath) -Level 'cmd'
    Write-AkariLog -Text ("  kind      : {0}" -f $card.Kind)
    Write-AkariLog -Text ("  answer    : {0}" -f $want)
    Write-AkariLog -Text ("  menu shape: {0}" -f $card.MenuShape)
    Write-AkariLog -Text ("  ops       : {0}" -f $inv.TotalOps) -Level $(if ($inv.TotalOps -eq 0) { 'warn' } else { 'info' })
    Write-AkariLog -Text ("  path      : {0}" -f $card.Script.Path)

    try {
        $script:Active = New-AkariRun `
            -Script   $card.Script.Path `
            -Answer   $inv.Answer `
            -TotalOps $inv.TotalOps `
            -NoGui
    } catch {
        $script:Active = $null
        Write-AkariStatus -Name $card.Display -Count 'failed'
        $ui.OpDetail.Text = $_.Exception.Message

        # The full record, not the one-line message the footer can hold. A
        # dispatcher-level failure means the runspace never started, which is a
        # different class of problem from a script that ran and failed.
        Write-AkariLog -Text 'DISPATCH FAILED' -Level 'fail'
        Write-AkariLog -Text ("  " + $_.Exception.Message) -Level 'fail'
        Write-AkariLog -Text ("  at " + $_.InvocationInfo.PositionMessage) -Level 'fail'
        Write-AkariLog -Text $_.ScriptStackTrace -Level 'fail'

        $ui.BtnCancel.IsEnabled = $false
        $ui.BtnApply.IsEnabled = $true
        $ui.BtnRevertAll.IsEnabled = $true
        Start-AkariNext
    }
}

function Write-AkariConsole {
    <#
        .SYNOPSIS
        Prints the tweak's own output into the terminal pane, live.

        .DESCRIPTION
        Called on every tick with whatever the runspace has queued since the last
        tick, so lines appear as the tweak produces them rather than all at once
        when it finishes. The pane is opened automatically on the first line: a
        console that stays hidden until someone goes looking defeats the purpose.
    #>
    param([object[]]$Lines)

    if (-not $Lines -or $Lines.Count -eq 0) { return }

    if ($ui.LogPanel.Visibility -ne 'Visible') { Set-AkariLogVisible -Visible $true }

    foreach ($l in $Lines) {
        # The tweak's own text, unadorned. It arrives prefixed with the script's
        # own line breaks, so it is normalised here rather than being stamped
        # like a diagnostic line - it is output, not commentary.
        $text = [string]$l
        if ($text -match '^\s*$') { continue }
        Write-AkariLog -Text $text -Level 'info'
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

    # Every tick runs inside a try/catch. A DispatcherTimer handler that throws,
    # with no DispatcherUnhandledException hook attached, takes the whole process
    # down: no dialog, nothing after the last log line, and the run it was
    # reporting on is lost. A bug in the progress display must never be able to
    # cost the user a tweak that has already been applied.
    $script:Timer.Add_Tick({
        if (-not $script:Active) {
            $script:Timer.Stop()
            $script:Timer = $null
            return
        }

        try {
            $p = Get-AkariRunProgress -Run $script:Active

            # Drain first, and independently of whether progress came back. If a
            # run has produced output but no counter movement yet, the output
            # still belongs on screen.
            try { Write-AkariConsole -Lines (Get-AkariRunOutput -Run $script:Active) } catch { }

            if ($null -eq $p) {
                $script:Timer.Stop(); $script:Timer = $null
                $script:Active = $null
                $ui.Bar.IsIndeterminate = $false
                return
            }

            # The intercepted command IS "what it is doing", and it is the only
            # signal for the ~40% of scripts whose Write-Host output is thin.
            # Logged only when it changes, or a loop repeating one command
            # floods the pane.
            $nowDoing = ('{0}  {1}' -f $p.Last, $p.Detail).Trim()
            if ($nowDoing -and $nowDoing -ne $script:LastDoing) {
                $script:LastDoing = $nowDoing
                Write-AkariLog -Text ('  > ' + $nowDoing) -Level 'cmd'
            }

            $elapsed = Format-AkariElapsed -Seconds $p.Elapsed

            if ($p.Total -gt 0) {
                $pct = [Math]::Min(100, [int](($p.Ticks / $p.Total) * 100))
                $ui.Bar.IsIndeterminate = $false
                $ui.Bar.Value = $pct
                $ui.BarPct.Text = '{0,3}%  {1}' -f $pct, $elapsed
                $ui.OpCount.Text = 'op {0} / {1}' -f $p.Ticks, $p.Total
            } else {
                # No reliable denominator: show a moving bar and be honest.
                $ui.Bar.IsIndeterminate = $true
                $ui.BarPct.Text = "   --  $elapsed"
                $ui.OpCount.Text = 'op {0}' -f $p.Ticks
            }

            if ($p.Detail) {
                $ui.OpDetail.Text = ('{0}  {1}' -f $p.Last, $p.Detail).Trim()
            }

            if ($p.Finished) {
                $run = $script:Active
                $script:Active = $null

                $card = $script:CurrentCard

                # The completion path carries its own guard, separate from the
                # one around the whole tick, because by this point it has already
                # taken ownership of the run: $script:Active is null. A throw
                # here would otherwise leave the window displaying a run that
                # nothing is polling, with Cancel still live and the queue frozen.
                #
                # Everything below is best-effort REPORTING - the tweak itself has
                # already finished and its effects are already on the machine - so
                # failures are logged and the release still happens in finally.
                try {
                    $result = Wait-AkariRun -Run $run -TimeoutSeconds 30

                    # Final drain. Lines can be written between the last tick and
                    # the run ending, and a console that silently drops them is
                    # worse than one that duplicates them.
                    try { Write-AkariConsole -Lines (Get-AkariRunOutput -Run $run) } catch { }

                    # The console preamble throws in a headless runspace and
                    # cannot be shimmed, because $Host is a constant. It sets a
                    # window title and a background colour, so it is tolerated -
                    # but only that one message, and it is filtered rather than
                    # counted, because letting it decide whether a tweak
                    # succeeded would be wrong in the other direction: a cosmetic
                    # error would mark every run as failed.
                    $real = @($result.Messages | Where-Object {
                        $_ -notmatch 'WindowTitle' -and
                        $_ -notmatch 'does not support user interaction'
                    })

                    # Everything about the finished run is written out verbatim
                    # before any interpretation. The script's own output is
                    # included because a tweak that prints an error and carries
                    # on will report success here while having done nothing - the
                    # text is the only sign of that.
                    Write-AkariLog -Text ("END  {0}  ops={1}/{2}  elapsed={3:N1}s  cancelled={4}" -f
                        $card.RelPath, $result.State.ticks, $result.TotalOps,
                        $result.Elapsed, [bool]$result.Cancelled) `
                        -Level $(if ($result.Cancelled) { 'warn' } else { 'info' })

                    $out = @($result.Output)
                    if ($out.Count -gt 0) {
                        # Parentheses are REQUIRED here. Written as
                        #   Write-AkariLog -Text "..." -f $a, $b
                        # the -f is parsed as a PARAMETER NAME in command
                        # argument mode, not as the format operator, and the call
                        # dies with "a parameter cannot be found that matches
                        # parameter name 'f'". That throw used to land on the
                        # line immediately after a tweak finished, which closed
                        # the window outright, seconds after a successful apply.
                        Write-AkariLog -Text ("  output ({0} line{1}):" -f
                            $out.Count, $(if ($out.Count -eq 1) { '' } else { 's' }))
                        foreach ($line in $out) { Write-AkariLog -Text "    $line" }
                    } else {
                        Write-AkariLog -Text '  output: (none)' -Level 'warn'
                    }

                    if ($result.Messages.Count -gt 0) {
                        Write-AkariLog -Text ("  errors ({0}):" -f $result.Messages.Count)
                        foreach ($m in $result.Messages) { Write-AkariLog -Text "    $m" }
                    }

                    if ($real.Count -gt 0) {
                        Write-AkariLog -Text ("FAILED with {0} real error{1}" -f $real.Count,
                            $(if ($real.Count -eq 1) { '' } else { 's' })) -Level 'fail'
                    } else {
                        Write-AkariLog -Text 'completed with no real errors'
                    }

                    if ($result.Cancelled) {
                        Write-AkariStatus -Name $card.Display -Count 'cancelled'
                        $ui.OpDetail.Text = 'stopped before finishing'
                        Write-AkariLog -Text 'cancelled by user before finishing' -Level 'warn'
                    } elseif ($real.Count -gt 0) {
                        Write-AkariStatus -Name $card.Display `
                            -Count ("{0} error{1}" -f $real.Count,
                                    $(if ($real.Count -eq 1) { '' } else { 's' }))
                        $ui.OpDetail.Text = ($real | Select-Object -First 1)
                    } else {
                        # The state is NOT flipped here. The checkbox already set
                        # it to the target value before the run started, and that
                        # value is what was actually executed. Flipping it again
                        # would land on the opposite state from the one the
                        # machine is now in - the row would show "off" straight
                        # after a successful apply.
                        #
                        # The checkbox is resynced from Applied instead, because a
                        # Run card has no checkbox and its own row must not
                        # invert: there is no on/off state for it to represent.
                        if ($card.Check -is [System.Windows.Controls.CheckBox]) {
                            $card.Check.IsChecked = $card.Applied
                        }
                        if ($card.Flags.NeedsReboot) {
                            $script:RestartSet = $true
                            $ui.RestartBadge.Visibility = 'Visible'
                        }
                        Write-AkariStatus -Name $card.Display -Count 'done'
                        $ui.OpDetail.Text = ($result.Output | Select-Object -Last 1)
                        $ui.BarPct.Text = '100%'
                        $ui.Bar.Value = 100
                    }

                    Set-AkariCardVisual -Card $card
                } catch {
                    # Reported rather than swallowed: this is a bug in the UI, and
                    # the log is the only way the user can hand it over.
                    Write-AkariLog -Text ('reporting the finished run failed: ' +
                        $_.Exception.Message) -Level 'fail'
                    try {
                        Write-AkariLog -Text ('  ' + $_.Exception.GetType().FullName) `
                            -Level 'fail'
                        Write-AkariLog -Text ('  at Main.ps1 line ' +
                            $_.InvocationInfo.ScriptLineNumber) -Level 'fail'
                    } catch { }
                    try {
                        Write-AkariStatus -Name $card.Display -Count 'report failed'
                        $ui.OpDetail.Text = 'the tweak ran; reporting it failed'
                    } catch { }
                } finally {
                    # The release is unconditional. Whatever went wrong above, the
                    # runspace must be disposed and the next queued tweak must be
                    # allowed to start.
                    try { Close-AkariRun -Run $run } catch { }
                    $ui.BtnCancel.IsEnabled = $false

                    # Start-AkariNext hands off to the next queued tweak, which may
                    # be this same tick or the next one. Either way the ticker has
                    # to keep running: it is the only thing polling the run, so
                    # stopping it here would leave the next tweak running with
                    # nobody watching. It gets torn down by the guard at the top of
                    # this handler, on the tick where nothing is active.
                    try { Start-AkariNext } catch { }
                }
            }
        } catch {
            # Only the progress display can reach here. The running tweak is
            # deliberately left alone: stopping it would abandon a pipeline that
            # may be mid-registry-write, and the next tick retries in 120ms.
            Write-AkariLog -Text ('tick handler failed: ' + $_.Exception.Message) `
                -Level 'fail'
            try {
                Write-AkariLog -Text ('  ' + $_.Exception.GetType().FullName) -Level 'fail'
                Write-AkariLog -Text ('  at Main.ps1 line ' +
                    $_.InvocationInfo.ScriptLineNumber) -Level 'fail'
            } catch { }
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

# Starts a run with the console already open. Called from the apply/revert paths
# rather than on every click, so a user browsing cards does not get the pane
# shoved in their face.
function Start-AkariWithConsole {
    Set-AkariLogVisible -Visible $true
    $script:LastDoing = ''
    OnCardRun -Card $args[0]
}

# ---------------------------------------------------------------------------
# Log pane handlers
# ---------------------------------------------------------------------------

function OnLogToggle {
    $open = $ui.LogPanel.Visibility -ne 'Visible'
    Set-AkariLogVisible -Visible $open
    if ($open) { Write-AkariLog -Text 'log opened' }
}

function OnLogCopy {
    <#
        .DESCRIPTION
        Clipboard access is the one part that can fail on its own, because
        another process may hold the clipboard open. It is caught separately and
        reported in the pane, rather than surfacing as an unhandled WPF
        exception that would take the window down mid-tweak.
    #>
    try {
        [System.Windows.Clipboard]::SetText((Get-AkariLogText))
        Write-AkariLog -Text 'log copied to clipboard' -Level 'cmd'
        $ui.LogHint.Text = 'copied - paste it into the chat'
    } catch {
        $ui.LogHint.Text = 'clipboard busy, try again'
        Write-AkariLog -Text ("clipboard unavailable: " + $_.Exception.Message) `
            -Level 'fail'
    }
}

function OnLogSave {
    <#
        .DESCRIPTION
        Saves to a file rather than only to the clipboard, for the case where
        the log is long enough that pasting it is impractical. Defaults to the
        desktop so it is easy to find from a VM console.
    #>
    try {
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Title = 'Save diagnostic log'
        $dlg.FileName = 'akari-toolbox-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
        $dlg.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
        $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')

        if ($dlg.ShowDialog() -ne $true) {
            Write-AkariLog -Text 'log save cancelled'
            return
        }

        # UTF8 with a BOM, because Notepad on a VM will otherwise render it as
        # mojibake and the pasted text becomes unreadable.
        [System.IO.File]::WriteAllText(
            $dlg.FileName, (Get-AkariLogText), [System.Text.UTF8Encoding]::new($true))

        $ui.LogHint.Text = "saved to $($dlg.FileName)"
        Write-AkariLog -Text "log saved to $($dlg.FileName)" -Level 'cmd'
    } catch {
        $ui.LogHint.Text = 'save failed'
        Write-AkariLog -Text ("log save failed: " + $_.Exception.Message) -Level 'fail'
    }
}

function OnApplyAll {
    <#
        .SYNOPSIS
        Queues every tweak in the current folder for application.

        .DESCRIPTION
        Toggling the checkboxes is only half of it. The checkbox records intent;
        the run is what changes the machine, so each card is queued explicitly
        rather than relying on the click handler, which does not fire when
        IsChecked is set from code.

        Only cards not already applied are queued, so a second press of Apply is
        a no-op instead of re-running everything.
    #>
    $targets = @()
    if ($script:Current) { $targets = @($script:Current.Scripts) }

    $added = 0
    foreach ($s in $targets) {
        $c = $script:Cards[$s.RelPath]
        if (-not $c) { continue }

        if ($c.Applied -or $c.Queued) { continue }

        if ($c.Check -is [System.Windows.Controls.CheckBox]) {
            $c.Check.IsChecked = $true
        }
        $c.Applied = $true
        Set-AkariCardVisual -Card $c
        Add-AkariToQueue -Card $c
        $added++
    }

    Write-AkariSummary -Text ("{0} queued" -f $added)
    if ($added -gt 0) {
        Set-AkariLogVisible -Visible $true
        $script:LastDoing = ''
        Start-AkariNext; Start-AkariTicker
    }
}

function OnRevertAll {
    <#
        .SYNOPSIS
        Queues every applied tweak for revert, across all folders.

        .DESCRIPTION
        Runs the same way as Apply All: the checkbox is cleared to record the
        target state, then the card is queued so the inverse branch actually
        executes. Reverting is done by answering the script's menu with the other
        option, not by editing state.

        Scoped to cards that are currently applied, so a press with nothing
        applied does nothing rather than running all 104 scripts.
    #>
    $added = 0
    foreach ($c in @($script:Cards.Values)) {
        if (-not $c.Applied -or $c.Queued) { continue }
        if ($c.Kind -eq 'Run') { continue }   # nothing to invert

        if ($c.Check -is [System.Windows.Controls.CheckBox]) {
            $c.Check.IsChecked = $false
        }
        $c.Applied = $false
        Set-AkariCardVisual -Card $c
        Add-AkariToQueue -Card $c
        $added++
    }

    Write-AkariSummary -Text ("{0} reverting" -f $added)
    if ($added -gt 0) {
        Set-AkariLogVisible -Visible $true
        $script:LastDoing = ''
        Start-AkariNext; Start-AkariTicker
    }
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

$ui.BtnLog.Add_Click({ OnLogToggle })
$ui.BtnHideLog.Add_Click({ Set-AkariLogVisible -Visible $false })
$ui.BtnCopyLog.Add_Click({ OnLogCopy })
$ui.BtnSaveLog.Add_Click({ OnLogSave })
$ui.BtnClearLog.Add_Click({ Clear-AkariLog })

# Ctrl+L, so the pane can be reached without leaving the keyboard. Ctrl+A inside
# the box is left alone: the TextBox handles it, and selecting the log by
# accident mid-tweak would be a nuisance.
#
# Two things are required and neither is optional:
#
#   a KeyBinding needs an ICommand, so a delegate cannot be passed directly -
#     it throws "Cannot convert ... ExecutedRoutedEventHandler to ICommand"
#   a RoutedCommand has no Add_Executed method, so the handler cannot be attached
#     to the command either - it needs a CommandBinding on the window
#
# Same shape as the F5 refresh below.
$script:CmdLog = New-Object System.Windows.Input.RoutedUICommand
$null = $script:CmdLog.InputGestures.Add((New-Object System.Windows.Input.KeyGesture(
    [System.Windows.Input.Key]::L,
    [System.Windows.Input.ModifierKeys]::Control)))

$logBinding = New-Object System.Windows.Input.CommandBinding
$logBinding.Command = $script:CmdLog
$logBinding.Add_Executed([System.Windows.Input.ExecutedRoutedEventHandler] {
    param($sender, $e)
    $e.Handled = $true
    OnLogToggle
})
$null = $window.CommandBindings.Add($logBinding)

# Startup banner. Written last so it carries the script count and the elevation
# state, which are known by this point.
Write-AkariLog -Text '=== AkariOS Ultimate Toolbox ===' -Level 'cmd'
Write-AkariLog -Text ("scripts : {0} in {1} folders" -f
    (@($script:Catalog | ForEach-Object { $_.Scripts })).Count, $script:Catalog.Count)
Write-AkariLog -Text ("elevated: {0}" -f (Get-AkariIsAdmin))
Write-AkariLog -Text ("spec    : {0}" -f (Get-AkariSpec))
Write-AkariLog -Text ("log file: {0}" -f $script:LogPath)
Write-AkariLog -Text 'open this pane and press Copy to report a failure'

$ui.Search.Add_TextChanged({
    Show-AkariSidebar
    if ($script:Current) { Show-AkariFolder -Folder $script:Current }
})

$window.Add_Closing({
    if ($script:Active) { Stop-AkariRun -Run $script:Active }
    if ($script:Timer) { $script:Timer.Stop() }
    Write-AkariLog -Text 'window closing'
})

# Last-resort net. A Dispatcher event handler that throws is swallowed by WPF
# and the window keeps looking alive while doing nothing, which is the hardest
# kind of bug to report. Routing it into the log means a silent failure becomes
# a pasteable one.
#
# Deliberately defensive. There is no PowerShell event syntax for this event,
# it has to be attached through reflection, and the reflection is not reliable
# across hosts - [Dispatcher].GetEvent('DispatcherUnhandledException') returns
# null here. A net that cannot be attached must not become the reason the tool
# will not start, so a failure to attach is logged and ignored.
#
# e.Handled is left false so the default handler still runs: this records the
# problem, it does not swallow it.
try {
    $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    $handler = [System.Windows.Threading.DispatcherUnhandledExceptionEventHandler] {
        param($s, $e)

        Write-AkariLog -Text 'UNHANDLED UI EXCEPTION' -Level 'fail'
        Write-AkariLog -Text ("  " + $e.Exception.Message) -Level 'fail'
        Write-AkariLog -Text ("  " + $e.Exception.GetType().FullName) -Level 'fail'
        try { Write-AkariLog -Text ("  at " + $e.Exception.StackTrace) -Level 'fail' } catch { }
        $e.Handled = $false
    }

    # Attached by invoking the add_ accessor on the live dispatcher. Reflection
    # on the Dispatcher type is not reliable here - GetType().GetEvent() returns
    # null for this event - and the hook is the last line of defence between a
    # bad log line and a dead window, so every route is tried in turn rather than
    # settling for the first one.
    $attached = $false

    try {
        $dispatcher.add_DispatcherUnhandledException($handler)
        $attached = $true
    } catch { }

    if (-not $attached) {
        $ev = [System.Windows.Threading.Dispatcher].GetEvent(
            'DispatcherUnhandledException',
            [System.Reflection.BindingFlags]'Public,NonPublic,Instance')
        if ($ev) {
            try {
                $null = $ev.AddEventHandler($dispatcher, $handler)
                $attached = $true
            } catch { }
        }
    }

    if ($attached) {
        Write-AkariLog -Text 'note: dispatcher exception hook attached' -Level 'info'
    } else {
        Write-AkariLog `
            -Text 'warning: dispatcher exception hook unavailable - handler try/catch is the only guard' `
            -Level 'warn'
    }
} catch {
    Write-AkariLog -Text ("note: dispatcher exception hook failed: " + $_.Exception.Message) `
        -Level 'warn'
}

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
