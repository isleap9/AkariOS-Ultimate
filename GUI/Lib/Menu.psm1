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
    # The state object is a Hashtable, and a hashtable's keys are NOT in
    # PSObject.Properties - that only lists CLR members. Testing
    # .PSObject.Properties.Name -contains 'answer' therefore always returns
    # false, which silently sent an empty answer and made every menu loop spin
    # until the guard tripped. Keys is the correct test for a hashtable.
    if (`$__akMenuState -and (`$__akMenuState.Keys -contains 'answer')) {
        `$a = `$__akMenuState['answer']
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
        # Position=0 is required, not decoration. ValueFromRemainingArguments only
        # captures POSITIONAL arguments when a position is declared; without it
        # the parameter stays empty and every Write-Host shim call emitted a blank
        # string, which is why the footer showed nothing.
        [Parameter(Position = 0, ValueFromRemainingArguments = `$true)]
        [object[]]`$Object
    )

    # A tweak's own output IS the console. The real cmdlet writes to a console
    # host that does not exist here, so two things happen instead:
    #
    #   1. pushed onto the shared queue, which the UI drains on every tick, so
    #      the line appears while the tweak is still running
    #   2. returned to the success stream, which the dispatcher collects at the
    #      end as a complete transcript
    #
    # Both are needed. The queue alone would lose the output if the process
    # died mid-run; the success stream alone would only show it at the end,
    # which defeats the point of a live console.
    #
    # The queue is written inline, not by calling Add-AkariRunOutput, because
    # that function lives in Tracer.psm1 and no module is imported inside the
    # runspace. The state hashtable is in scope here - it arrived as this
    # script's argument - so it is written to directly.
    foreach (`$o in `$Object) {
        if (`$null -eq `$o) { continue }
        `$line = [string]`$o
        try {
            `$q = `$__akMenuState['log']
            if (`$q) { `$null = `$q.Add(`$line) }
        } catch { }
        `$line
    }
}

# The console preamble is the real blocker, and it was found by running a
# fixture rather than by reading the scripts.
#
# All 104 tweaks open with something like:
#
#     `$Host.UI.RawUI.WindowTitle = ...
#     `$Host.UI.RawUI.BackgroundColor = "Black"
#     `$Host.PrivateData.ProgressBackgroundColor = "Black"
#
# In a runspace with no console host, setting WindowTitle throws:
#
#     A command that prompts the user failed because the host program or the
#     command type does not support user interaction.
#
# That is a terminating error for the statement, so the script aborts before it
# ever reaches its menu. It affects 104 of 104 scripts, which makes it the one
# thing that has to be solved before any tweak can run.
#
# `$Host cannot be shimmed. Both obvious routes fail, and both were tried:
#
#     Set-Variable -Name Host -Scope Global -Force
#         -> Cannot overwrite variable Host because it is read-only or constant.
#     Remove-Variable -Name Host -Scope Global -Force
#         -> Cannot remove variable Host because it is constant or read-only.
#
# The throw comes from a property setter, and the only remaining lever is to make
# the pipeline tolerate it: the dispatcher runs the script with an
# ErrorActionPreference that continues, so a failed cosmetic preamble line no
# longer takes the script down with it. The preamble sets a window title and a
# background colour. Losing it costs nothing. The registry work that follows is
# what actually matters.
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

        # Applied = true means the user wants the TWEAK ON, so the answer is the
        # option that turns it on. Both of these were previously the other way
        # round, which made checking a box run the revert branch - visible in a
        # VM as 5 Theme Black opening regedit.exe when the tweak was applied.
        'ApplyRevert' { $answer = if ($Card.Applied) { 1 } else { 2 } }
        'OnOff'       { $answer = if ($Card.Applied) { 2 } else { 1 } }

        'Value' {
            # Read the selection off the dropdown, because that is what the user
            # chose. The Index is the script's own option number, not a position
            # in the list: Bloatware's real options start at 2 because its option
            # 1 is Exit.
            if ($Card.Combo -and $Card.Combo.SelectedItem) {
                $answer = [int]$Card.Combo.SelectedItem.Tag
            } else {
                # No dropdown selection - fall back to the first real option,
                # skipping Exit so a default can never be "do nothing".
                $first = @($Card.Options | Where-Object { -not $_.IsExit })
                if ($first.Count -gt 0) { $answer = [int]$first[0].Index }
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