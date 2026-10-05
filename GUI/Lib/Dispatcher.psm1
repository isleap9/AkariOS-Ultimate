<#
    Dispatcher.psm1 — runs tweak scripts off the UI thread and reports progress.

    A tweak is executed as a three-stage pipeline inside its own runspace:

        stage 1   the counting shims from Tracer.psm1 are installed
        stage 2   the menu shims from Menu.psm1, which answer the script's
                  Read-Host prompt
        stage 3   the tweak script itself, invoked with NO parameters

    The shims have to be separate statements ahead of the script so the shadows
    are in place before it resolves any command names. That ordering was verified
    by test.

    The script is invoked with no parameters, and this is the important part: the
    104 tweaks are NOT edited to accept -Action / -Choice / -NoGui. They are run
    exactly as they ship. What selects the branch is the Read-Host shim answering
    the menu with the right option index, and -NoGui's work (skipping Pause,
    internet checks and ms-settings windows) is done by the same shim layer.

    Consequence: the repo stays untouched, and a script that gains or renames an
    option keeps working, because the answer is an index computed at run time.

    The UI thread is never blocked. A DispatcherTimer samples the runspace
    counters and marshals the values to the UI, so a 1900-line script cannot
    freeze the window.
#>

Set-StrictMode -Version Latest

function New-AkariRun {
    <#
        .SYNOPSIS
        Starts a tweak script in a background runspace with counting shims.
        .DESCRIPTION
        .PARAMETER Script
        Full path to the tweak script.
        .PARAMETER Answer
        Option index the Read-Host shim answers with. 0 means the script has no
        menu, so nothing is sent.
        .PARAMETER TotalOps
        Static operation count for the chosen branch. Drives the determinate
        bar; 0 means the bar runs indeterminate.
        .PARAMETER NoGui
        Shims out the console-only behaviour a tweak would otherwise do: Pause
        prompts, internet reachability checks, ms-settings windows and forced
        reboots. Meaningful even though the script is passed no parameters.

        Returns a handle exposing Ticks, Total, Running and Stop().
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Script,
        [int]$Answer = 0,
        [int]$TotalOps = 0,
        [switch]$NoGui
    )

    $setup = Get-AkariTracerSetup
    $state = New-AkariProgressState -TotalOps $TotalOps

    # The menu answer rides in the shared state object, the same one the
    # progress shims write to, so nothing extra has to be marshalled into the
    # runspace. answer / noGui are plain keys on it.
    $state.answer = $Answer
    $state.noGui  = [bool]$NoGui

    $menuShim = Get-AkariMenuShim

    # ThreadOptions is deliberately left at its default. Setting it to
    # 'ReuseThread' makes BeginInvoke's pipeline never complete: the run stays
    # in the Opened state forever and no output is ever produced. Verified by
    # isolating that one property against the same script.
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'MTA'
    $runspace.Open()

    $shell = [powershell]::Create()
    $shell.Runspace = $runspace

    # The shared progress hashtable is passed as the setup script's only
    # argument, so the shims write to the same object the UI reads.
    $null = $shell.AddScript($setup).AddArgument($state).AddStatement()

    # Menu shims next. Installed before the script runs so its Read-Host
    # resolves to the shim rather than the cmdlet.
    $null = $shell.AddScript($menuShim).AddArgument($state).AddStatement()

    # The script itself, with NO parameters. This is the whole point: the tweak
    # files are never modified, so a parameter that none of them declare would
    # be a hard error.
    $null = $shell.AddCommand($Script)

    # Every property is declared up front. Under Set-StrictMode a PSCustomObject
    # created without a given property cannot have one added later, so a handle
    # missing AsyncResult here would fail the moment Wait-AkariRun sets it.
    $handle = [pscustomobject]@{
        Script      = $Script
        Answer      = $Answer
        NoGui       = [bool]$NoGui
        TotalOps    = $TotalOps
        Runspace    = $runspace
        Shell       = $shell
        State       = $state
        AsyncResult = $null
        Output      = $null
        Error       = $null
        ErrorCount  = 0
        Messages    = @()
        StartedAt   = Get-Date
        FinishedAt  = $null
        Cancelled   = $false
    }

    # BeginInvoke returns immediately; the timer in Main.ps1 polls the handle.
    $handle.AsyncResult = $shell.BeginInvoke()

    $handle
}

function Get-AkariRunProgress {
    <#
        .SYNOPSIS
        Samples a running tweak. Safe to call from the UI thread.
        .DESCRIPTION
        Reads the shim counters out of the runspace. Returns $null if the
        runspace is gone, which is how a finished or aborted run is detected.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)

    # Progress is read from the SHARED hashtable, never from the runspace.
    # Runspace.SessionStateProxy.GetVariable throws "A pipeline is already
    # running" while a tweak is in flight, which would make a live progress bar
    # impossible. The synchronized hashtable needs no runspace call at all.
    $s = $Run.State
    if ($null -eq $s) { return $null }

    # A completed pipeline is detected from the runspace state, which is safe
    # to read while running. 'Opened' is normal immediately after BeginInvoke.
    $rsState = 'Unknown'
    if ($Run.Runspace) {
        $rsState = $Run.Runspace.RunspaceStateInfo.State
    }

    $isRunning = ($rsState -in 'Opened', 'Running') -and
                 (-not $Run.AsyncResult -or -not $Run.AsyncResult.IsCompleted)

    [pscustomobject]@{
        Ticks   = [int]$s.ticks
        Total   = [int]$Run.TotalOps
        Last    = [string]$s.last
        Detail  = [string]$s.detail
        Elapsed = (New-TimeSpan -Start $Run.StartedAt -End (Get-Date)).TotalSeconds
        Running = $isRunning
        Finished = (-not $isRunning)
    }
}

function Wait-AkariRun {
    <#
        .SYNOPSIS
        Blocks until the tweak finishes and collects its output.
        .DESCRIPTION
        Used by Revert All and by headless verification, not by the UI loop.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Run,
        [int]$TimeoutSeconds = 0
    )

    # WaitOne returns a bool. Letting it reach the output stream would turn this
    # function's result into an array, so callers would get the bool instead of
    # the run handle.
    if ($Run.AsyncResult) {
        $null = $Run.AsyncResult.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)
    }

    try {
        $Run.Output = @($Run.Shell.EndInvoke($Run.AsyncResult))
    } catch {
        $Run.Error = $_.Exception.Message
    }

    $Run.FinishedAt = Get-Date
    $Run.ErrorCount = $Run.Shell.Streams.Error.Count
    $Run.Messages   = @($Run.Shell.Streams.Error | ForEach-Object { $_.ToString() })

    # Flag the shared state so the UI's last poll sees the run as complete.
    if ($Run.State) { $Run.State.done = $true }

    $Run
}

function Stop-AkariRun {
    <#
        .SYNOPSIS
        Cancels a running tweak.
        .DESCRIPTION
        PowerShell.Stop() tears down the pipeline. That halts the script at its
        next statement boundary — it does not roll back registry writes that
        already happened, so the caller must journal state before starting.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)

    try {
        if ($Run.Shell) { $Run.Shell.Stop() }
    } catch {
        # A run that finished between the poll and the click is not an error.
    }
    $Run.FinishedAt = Get-Date
    $Run
}

function Close-AkariRun {
    <#
        .SYNOPSIS
        Releases a run's runspace. Always call this or the process leaks them.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)

    foreach ($obj in @($Run.Shell, $Run.Runspace)) {
        if ($obj) {
            try { $obj.Dispose() } catch { }
        }
    }
    $Run.Runspace = $null
    $Run.Shell    = $null
}

Export-ModuleMember -Function New-AkariRun, Get-AkariRunProgress, Wait-AkariRun,
    Stop-AkariRun, Close-AkariRun
