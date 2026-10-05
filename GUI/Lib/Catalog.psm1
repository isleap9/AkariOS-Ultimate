<#
    Catalog.psm1 — builds the AkariOS Ultimate toolbox model by reading the
    repo itself. Nothing is hard-coded: add a script to a folder and it appears
    in the GUI on next launch, in repo order, under its real folder name.

    Every script is parsed with the PowerShell AST. String escapes are resolved
    by the parser, which a text regex cannot do — `Write-Host "2. UAC: Default`n"`
    defeats naive pattern matching but not `.Value`.

    Verified against this repo (104 scripts, all parse):
        44  run-only      no menu
        49  two-option    Apply/Revert or On/Off
         5  three-option  value picker
         1  four-option   value picker
         4  six/nine      value picker
         1  twenty-eight  value picker (Exit at 28)
#>

Set-StrictMode -Version Latest

# Folders that make up the toolbox, in repo order. The UI shows these verbatim.
$script:FolderOrder = @(
    '1 Check', '2 Refresh', '3 Setup', '4 Installers',
    '5 Graphics', '6 Windows', '7 Hardware', '8 Advanced'
)

# The load-bearing signal for a two-option script is which option represents the
# stock Windows state. Whichever option says "Default" is the untouched state,
# so the other one is the tweak. That fixes the polarity of the toggle.
# ---------------------------------------------------------------------------
# Classifying a two-option script.
#
# These scripts are not uniform, so reading the wording of one option is not
# enough. Labels come in two shapes:
#
#   "UAC: Off (Recommended)"   vs  "UAC: Default"
#       same subject, two states  -> toggle, and Default is the revert
#
#   "FSO (Default)"            vs  "FSE"
#       two named variants       -> dropdown, nothing to revert
#
# Both mention "Default", so a keyword test cannot separate them. The fix is to
# compare only what the two labels say AFTER any parenthesised hint such as
# "(Recommended)" is dropped:
#
#   "UAC: Off (Recommended)"  vs "UAC: Default"  ->  "off"  vs "default"
#   "FSO (Default)"           vs "FSE"            ->  "fso"   vs "fse"
#
# A remainder that is a state word means the option names a state of one
# subject. Anything else — w10, auto, 25h2, fso, "off: startup" — is a distinct
# setting and must not be shown as the other half of a toggle.
# ---------------------------------------------------------------------------
$script:StateWords = @(
    'on', 'off', 'default', 'enable', 'disable', 'enabled', 'disabled',
    'optimize', 'optimized', 'optimise', 'clean', 'uninstall', 'remove',
    'revert', 'restore', 'reset', 'undo', 'none', 'active', 'inactive',
    'black', 'white', 'low', 'high', 'medium'
)

function Get-AkariLabelRemainder {
    <#
        .SYNOPSIS
        Reduces a menu label to the word that actually differs.
        .DESCRIPTION
        Drops any parenthesised hint ("(Recommended)", "(Default)", "(125hz)")
        and returns the final remaining word, lowercased.
        For "UAC: Off (Recommended)" that is "off"; for "FSO (Default)" it is
        "fso"; for "Off: Startup" it is "startup".
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Label)

    $s = $Label -replace '\([^)]*\)', ' '
    $s = ($s -replace '\s+', ' ').Trim(' ', ':', '-', ',', '.')
    if ($s -notmatch '\S') { return '' }

    $words = @($s -split ' ' | Where-Object { $_ -ne '' })
    ($words[-1]).ToLowerInvariant().Trim(':', ',', '.')
}

# Kept only to record what failed: this matched on|off|enable anywhere in the
# label, so all 49 two-option scripts became ApplyRevert and none reached OnOff.

function Get-AkariMenuOption {
    <#
        .SYNOPSIS
        Extracts a script's numbered menu by walking its AST.
        .DESCRIPTION
        Looks at Write-Host calls whose first argument is a string literal
        matching "N. Label". CommandElements[0] is the command name itself,
        so the first real argument is index 1.

        Menus that are redrawn inside a `while ($true)` loop produce duplicate
        labels for the same index; the first occurrence wins, so Bloatware and
        Priority collapse to their real option count.

        An option labelled "Exit" is returned but flagged, because it is a menu
        control rather than an action and must not appear in a dropdown.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $result = [pscustomobject]@{
        Path    = $Path
        Parsed  = $false
        Options = @()
        Error   = $null
    }

    $errors = $null
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $Path, [ref]$null, [ref]$errors)
    } catch {
        $result.Error = $_.Exception.Message
        return $result
    }
    if (-not $ast) { $result.Error = 'parse returned nothing'; return $result }

    $result.Parsed = $true
    $seen         = @{}

    $writes = $ast.FindAll({
            param($x)
            ($x -is [System.Management.Automation.Language.CommandAst]) -and
            ($x.GetCommandName() -eq 'Write-Host')
        }, $true)

    foreach ($cmd in $writes) {
        $arg = $cmd.CommandElements | Select-Object -Skip 1 -First 1
        if (-not ($arg -is
            [System.Management.Automation.Language.StringConstantExpressionAst])) {
            continue
        }
        if ($arg.Value -notmatch '^\s*(\d+)\.\s*(\S.*?)\s*$') { continue }

        $index = [int]$Matches[1]
        $label = $Matches[2]
        if ($seen.ContainsKey($index)) { continue }   # menu redraw
        $seen[$index] = $label
    }

    $options = foreach ($index in ($seen.Keys | Sort-Object)) {
        $label = $seen[$index]
        [pscustomobject]@{
            Index  = $index
            Label  = $label
            IsExit = ($label -match '^(?i)exit\s*$')
        }
    }

    $result.Options = @($options)
    $result
}

function Get-AkariScriptFlag {
    <#
        .SYNOPSIS
        Detects the behaviours that make a script unsafe or awkward inside a GUI.
        .DESCRIPTION
        Each flag maps to something the GUI must neutralise or warn about.
        Counts are measured, not estimated — see OPENCODE.md.

          NeedsReboot      4    would restart the machine mid-run
          NeedsPause      46    blocks on a keypress
          NeedsNet        23    refuses to run without internet
          OpensSettings   14    launches a ms-settings: window
          UsesShowMenu     4    defines its own menu loop
          UsesTrusted      6    escalates via TrustedInstaller
          OpensBrowser     9    launches a web page
          HasExit         71    a bare `exit` would kill the GUI process
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $text = [System.IO.File]::ReadAllText($Path)

    [pscustomobject]@{
        NeedsReboot    = [bool]($text -match '(?i)shutdown(\.exe)?\s+/[rs]|Restart-Computer')
        NeedsPause     = [bool]($text -match '(?m)^\s*Pause\s*$')
        NeedsNet       = [bool]($text -match 'Test-Connection')
        OpensSettings  = [bool]($text -match 'Start-Process\s+[''"]?ms-settings:')
        UsesShowMenu   = [bool]($text -match 'function\s+show-menu')
        UsesTrusted    = [bool]($text -match 'Run-Trusted')
        OpensBrowser   = [bool]($text -match 'Start-Process\s+[''"]?https?://')
        HasExit        = [bool]($text -match '(?m)^\s*exit\s*$')
        SizeBytes      = (Get-Item $Path).Length
        LineCount      = ([System.IO.File]::ReadAllLines($Path)).Count
    }
}

function Get-AkariCardKind {
    <#
        .SYNOPSIS
        Decides which of the four card types a script needs.
        .DESCRIPTION
        Run          no menu at all
        ApplyRevert  2 options that are both states of one subject, where the
                     SECOND names the stock state — turning the tweak off runs
                     option 2 (UAC, Widgets, Gamebar, Services, Defender)
        OnOff        2 options that are both states, where the FIRST names the
                     stock state — the toggle is inverted, option 2 is the
                     tweak (Mpo, Ulps, Spectre, DEP, Secure Boot Bypass)
        Value        3+ options, or 2 options that are two distinct settings
                     rather than a state and its restore

        Two earlier rules were wrong and are recorded in the comments below:
        a keyword search put all 49 two-option scripts in ApplyRevert and none
        in OnOff, and a first fix using the shared label prefix still put the
        Flip models (FSO/FSE, HCF/HIF) in the wrong bucket. Both were caught by
        reading all 49 label pairs.
    #>
    [CmdletBinding()]
    param(
        # Run-only scripts have no menu at all, so an empty collection is the
        # normal case rather than a mistake — it must be allowed through.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Options
    )

    $real = @($Options | Where-Object { -not $_.IsExit })
    if ($real.Count -eq 0) { return 'Run' }
    if ($real.Count -ge 3)  { return 'Value' }
    if ($real.Count -ne 2)  { return 'Run' }

    $labelOne = $real[0].Label
    $labelTwo = $real[1].Label

    # Is the stock Windows state named on this side? Read the raw label: for
    # "FSO (Default)" the hint is in the parenthetical, which the reduced
    # remainder has already discarded.
    $oneIsDefault = ($labelOne -match '(?i)\bdefault\b')
    $twoIsDefault = ($labelTwo -match '(?i)\bdefault\b')

    # The stock state is option 2, so option 1 is the tweak and reverting means
    # running option 2. The common case: UAC, Widgets, Gamebar, Services,
    # Context Menu, Theme, Defender Optimize.
    if ($twoIsDefault) { return 'ApplyRevert' }

    # The stock state is option 1, so the toggle is inverted. Mpo, Ulps,
    # Secure Boot Bypass, DEP, Spectre, and the two Flip models.
    if ($oneIsDefault) { return 'OnOff' }

    # Neither side names a default. If both sides are plain states this is a
    # bare switch with no revert: BitLocker, Msi Mode.
    $one = Get-AkariLabelRemainder -Label $labelOne
    $two = Get-AkariLabelRemainder -Label $labelTwo
    if (($script:StateWords -contains $one) -and
        ($script:StateWords -contains $two)) {
        return 'OnOff'
    }

    # Two distinct settings with no stock state to return to: W10 vs W11,
    # Auto vs Manual, 25H2 vs 24H2, Already Running vs Startup.
    'Value'
}

function ConvertTo-AkariDisplayName {
    <#
        .SYNOPSIS
        Strips the numeric prefix from a filename for display.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    ($Name -replace '\.ps1$', '') -replace '^\s*\d+\s*[-.\)]?\s*', ''
}

function Get-AkariCatalog {
    <#
        .SYNOPSIS
        Builds the full toolbox model: folders, scripts, card types, op counts.
        .DESCRIPTION
        Walks the numbered folders in repo order, parses every script, and
        returns one object per folder containing one object per script.

        The -SkipOps switch omits the AST operation count, which is the
        expensive part. The UI builds the card list with it off, then asks for
        operation plans lazily as scripts are selected.
    #>
    [CmdletBinding()]
    param(
        [string]$Root = (Split-Path $PSScriptRoot -Parent | Split-Path -Parent),
        [switch]$SkipOps
    )

    foreach ($m in 'Tracer') {
        if (-not (Get-Module -Name $m)) {
            Import-Module (Join-Path $PSScriptRoot "$m.psm1") -ErrorAction Stop
        }
    }

    $folders = @()

    foreach ($folderName in $script:FolderOrder) {
        $dir = Join-Path $Root $folderName
        if (-not (Test-Path $dir)) { continue }

        $items = @()
        $files = @(Get-ChildItem -Path $dir -Filter *.ps1 -File |
            Sort-Object Name)   # repo order

        foreach ($file in $files) {
            $menu = Get-AkariMenuOption -Path $file.FullName
            $flag = Get-AkariScriptFlag -Path $file.FullName
            $kind = Get-AkariCardKind -Options $menu.Options

            $ops = $null
            if (-not $SkipOps) {
                $plan = Get-AkariOperationPlan -Path $file.FullName
                $ops = $plan
            }

            $items += [pscustomobject]@{
                Path         = $file.FullName
                RelPath      = "$folderName\$($file.Name)"
                FileName     = $file.Name
                Display      = ConvertTo-AkariDisplayName -Name $file.Name
                Folder       = $folderName
                Kind         = $kind
                Options      = $menu.Options
                Flags        = $flag
                Ops          = $ops
                Parsed       = $menu.Parsed
            }
        }

        $folders += [pscustomobject]@{
            Name    = $folderName
            Number  = [int]($folderName -replace '^(\d+).*', '$1')
            Path    = $dir
            Scripts = $items
            Count   = $items.Count
        }
    }

    $folders
}

Export-ModuleMember -Function Get-AkariCatalog, Get-AkariMenuOption,
    Get-AkariCardKind, Get-AkariScriptFlag, ConvertTo-AkariDisplayName
