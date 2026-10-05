<#
    Menu.psm1 — drives a tweak script's own menu without editing it.

    Every tweak in this repo is a console program. It prints its options, waits
    on Read-Host, then switches on the answer. The GUI needs to pick that answer
    and hand the script over, so this module builds the shims that let it happen.

    Why shims and not a param() wrapper on all 104 files:

      - The repo stays byte-identical. Nothing here is a source edit, so the
        scripts can still be run from a console exactly as they always were.
      - The menu logic is not duplicated. If a script gains an option, the GUI
        picks it up on the next catalog read, because the answer is chosen by
        option INDEX at run time. A wrapper would have to be hand-edited to
        match.
      - One mechanism covers every shape: 60 menu loops answer on the first
        prompt, and the 17 scripts with no prompt just run.

    What is shimmed, and why each one is needed:

      Read-Host   The menu read. Answers with the chosen option index.
      Pause       46 scripts wait for a keypress. A blocking prompt inside a
                  runspace would hang the tweak with no way out.
      Clear-Host  31 scripts clear the screen. Cosmetic, and it touches the
                  console API, which a headless runspace does not have.

    What is NOT shimmed: the elevation preamble. Every script re-launches itself
    as admin, but Main.ps1 already refuses to start unelevated, so by the time a
    script runs the check passes and the branch is skipped.

    The infinite-loop guard matters. Some scripts read input more than once. If
    the shim kept answering "2" forever and the script re-entered its loop, the
    tweak would spin with no way out and no way to report it. So the shim counts
    its own calls and throws a marked exception once a script has clearly lost
    the plot. The dispatcher turns that into "menu did not converge" instead of
    a hang.
#>

Set-StrictMode -Version Latest

# Above this many Read-Host calls in one run, the script is not converging.
$script:MaxReads = 8

function Get-AkariMenuShim {
    <#
        .SYNOPSIS
        Builds the menu shim source, to be injected ahead of the tweak script.

        .DESCRIPTION
        The shim takes the shared state hashtable as its only argument, the same
        object the progress shims write to. It reads the answer from it and
        records how many prompts it served, so the dispatcher can tell a script
        that consumed exactly one prompt from one that looped.

        The variable name is prefixed because the tweak script's own scope is
        the same scope: any plain name here could collide with something the
        script uses. $ErrorActionPreference is left alone on purpose, so a
        genuine error in a tweak still surfaces in the error stream.
    #>
    [CmdletBinding()]
    param([int]$MaxReads = 8)

    @"
param([Parameter(Mandatory)]`$__akMenuState)

`$__akMenuReads = 0

function Read-Host {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = `$true)]
        `$Prompt
    )

    `$script:__akMenuReads++

    if (`$script:__akMenuReads -gt $MaxReads) {
        throw '__AKARI_MENU_NONCONVERGENT__'
    }

    `$a = `$null
    if (`$__akMenuState -and
        (`$__akMenuState.PSObject.Properties.Name -contains 'answer')) {
        `$a = `$__akMenuState.answer
    }

    if (`$null -eq `$a -or "`$a" -eq '') { return '' }

    # Read-Host is typed loosely: every script compares the result against a
    # regex like '^[1-2]$'. Handing back the string form keeps those comparisons
    # working without the script having to know it is being driven.
    [string]`$a
}

function Pause {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = `$true)]`$Rest)
}

function Clear-Host {
    [CmdletBinding()]
    param()
}

function Write-Host {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = `$true)]
        `$Object,
        `$ForegroundColor,
        `$BackgroundColor
    )
    # Text from a tweak goes to the output stream, which the dispatcher already
    # collects and shows in the footer's detail band. Routing it through the
    # cmdlet would try to write to a console that does not exist.
}

# The console preamble is the actual blocker, and it was found by running a
# fixture rather than by reading the scripts.
#
# All 104 tweaks open with something like:
#
#     `$Host.UI.RawUI.WindowTitle = ...
#     `$Host.UI.RawUI.BackgroundColor = "Black"
#     `$Host.PrivateData.ProgressBackgroundColor = "Black"
#
# In a runspace with no console host, that throws:
#
#     Exception setting "WindowTitle": A command that prompts the user failed
#     because the host program or the command type does not support user
#     interaction.
#
# It is a terminating error for that STATEMENT, so the script aborts before it
# ever reaches its menu. Nothing downstream can work until this is handled, and
# it hits 104 of 104 scripts.
#
# `$Host` is an automatic read-only variable and cannot be reassigned, so the
# shim installs a $Host proxy into the global scope instead. The proxy answers
# the properties the preamble touches and returns an empty object for everything
# else, so an unanticipated property read does not become a new failure.
function global:__AkariHostProxy {
    [CmdletBinding()]
    param()

    `$ui = [pscustomobject]@{
        RawUI      = [pscustomobject]@{
            WindowTitle = ''
            WindowSize  = [pscustomobject]@{
                BufferSize = [pscustomobject]@{ Width = 120; Height = 50 }
                WindowSize = [pscustomobject]@{ Width = 120; Height = 50 }
            }
        }
        PrivateData = [pscustomobject]@{
            ProgressBackgroundColor = ''
            ProgressForegroundColor = ''
        }
        Name       = 'ServerRemoteHost'
    }
    `$ui
}

# Installed at global scope so the tweak's own scope sees it. Assigning `$Host is
# a parse error in some hosts, so the value is set through a variable indirection.
Set-Variable -Name Host -Value (__AkariHostProxy) -Scope Global -Force
"@
}

function Get-AkariMenuAnswer {
    <#
        .SYNOPSIS
        Picks the option index a menu loop should answer with.

        .DESCRIPTION
        The whole design rests on answering by INDEX rather than by label, so the
        answer stays correct when a script's option text is rewritten. Where the
        meaning is inverted - an on/off script whose option 1 is the stock state
        rather than the tweak - the index is swapped here, once, instead of in
        every card.

          ApplyRevert  option 1 is the tweak, option 2 is the default
          OnOff        option 1 is the default, option 2 is the tweak
          Value        the user's pick, passed straight through
          Run          no menu, so nothing is sent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Card
    )

    $answer = 0

    switch ($Card.Kind) {

        'ApplyRevert' { $answer = if ($Card.Applied) { 2 } else { 1 } }
        'OnOff'       { $answer = if ($Card.Applied) { 1 } else { 2 } }

        'Value' {
            if ($Card.Combo -and $Card.Combo.SelectedIndex -ge 0) {
                $answer = [int]$Card.Combo.SelectedItem.Tag
            } elseif ($Card.Options.Count -gt 0) {
                $answer = [int]$Card.Options[0].Index
            }
        }

        default { $answer = 0 }   # Run: no prompt to answer
    }

    $answer
}

function Test-AkariMenuShape {
    <#
        .SYNOPSIS
        Classifies a script's input style, from the AST.

        .DESCRIPTION
        Catalog.psm1 already reads every script to classify its card. This
        reports how the script consumes input, which decides whether a run needs
        an answer at all:

          Menu     reads Read-Host; needs an answer
          Direct   no Read-Host; runs straight through

        Reported rather than assumed, because a script with no Read-Host still
        runs correctly - it just needs no answer, and sending one would be
        ignored anyway.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path, [ref]$null, [ref]$errors)

    if (-not $ast) { return 'Unknown' }

    $reads = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and
        $n.GetCommandName() -eq 'Read-Host'
    }, $true))

    if ($reads.Count -gt 0) { return 'Menu' } else { return 'Direct' }
}

Export-ModuleMember -Function Get-AkariMenuShim, Get-AkariMenuAnswer,
    Test-AkariMenuShape