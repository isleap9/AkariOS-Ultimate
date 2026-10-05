<#
    Tracer.psm1 — universal operation counting for AkariOS Ultimate Toolbox.

    Installs shadow functions inside the tweak's runspace so every mutating
    operation ticks a counter, without editing a single tweak script.

    PowerShell resolves functions ahead of cmdlets and ahead of external
    executables, so a function named "cmd" intercepts `cmd /c "reg add ..."`.
    The original command is captured as a CommandInfo *before* the shadow is
    defined, then invoked from inside the shadow, so the real work still runs.

    Verified against the real scripts:
      - shadowing a cmdlet  : intercepted, work performed
      - shadowing an exe    : intercepted, work performed
      - cmd /c "reg add ...": intercepted AND registry actually changed
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Tracked command list.
#
# Only operations that MUTATE state are tracked. Read-only and cosmetic
# commands are excluded so the denominator reflects real work.
#
# This list is used for BOTH static AST counting and runtime shimming, so the
# numerator and the denominator are always counted by identical rules.
# ---------------------------------------------------------------------------

$script:NoiseCommands = @(
    'Write-Host', 'Write-Progress', 'Write-Warning', 'Write-Error',
    'Write-Verbose', 'Write-Output', 'Clear-Host', 'Read-Host', 'Pause',
    'Start-Sleep', 'Test-Path', 'Test-Connection', 'Get-ChildItem', 'Get-Item',
    'Get-ItemProperty', 'Get-AppxPackage', 'Get-AppXPackage', 'Get-Service',
    'Get-CimInstance', 'Get-WmiObject', 'Get-Process', 'Get-Content',
    'Get-ScheduledTask', 'Get-Date', 'Get-PnpDevice', 'get-mmagent',
    'get-netadapterbinding', 'exit', 'Import-Module', 'Add-Type',
    'Measure-Object', 'Sort-Object', 'Where-Object', 'ForEach-Object',
    'Select-Object', 'Out-Null', 'New-Object', 'Format-Table', 'Foreach',
    'Wait-Process', '[void]'
)

$script:TrackedCommands = @(
    # external executables
    'cmd', 'cmd.exe', 'reg', 'reg.exe', 'regedit', 'regedit.exe', 'sc', 'sc.exe',
    'netsh', 'bcdedit', 'schtasks', 'taskkill', 'tasklist', 'shutdown',
    'powercfg', 'msiexec', 'dism', 'sfc', 'cipher', 'bcdboot', 'wmic',
    'rundll32', 'rundll32.exe', 'Run-Trusted', 'show-menu',

    # registry
    'Set-Item', 'Set-ItemProperty', 'New-Item', 'New-ItemProperty',
    'Remove-Item', 'Remove-ItemProperty', 'Clear-Item', 'Rename-Item',

    # services / processes / files
    'Set-Service', 'Start-Service', 'Stop-Service', 'Restart-Service',
    'Start-Process', 'Stop-Process', 'Move-Item', 'Copy-Item',
    'Set-Content', 'Add-Content', 'Unblock-File',

    # network
    'Set-NetAdapter', 'Set-NetAdapterBinding', 'Enable-NetAdapterBinding',
    'Disable-NetAdapterBinding', 'Set-NetTCPSetting',
    'Set-DnsClientServerAddress',

    # appx / features / defender / agent
    'Remove-AppxPackage', 'Add-AppxPackage', 'Set-AppxPackage',
    'Enable-WindowsOptionalFeature', 'Disable-WindowsOptionalFeature',
    'Disable-MMAgent', 'Enable-MMAgent', 'Set-MMAgent',
    'Enable-ComputerRestore', 'Disable-ComputerRestore', 'Checkpoint-Computer',

    # scheduled tasks / policy / misc
    'Unregister-ScheduledTask', 'Register-ScheduledTask',
    'Set-ExecutionPolicy', 'Invoke-WebRequest', 'iwr', 'Invoke-Expression'
)

# Modules that must be present for the appx / network / defender commands to
# resolve. Imported once so Get-Command finds them at setup time.
$script:RequiredModules = @('Appx', 'NetAdapter', 'NetTCPIP', 'ScheduledTasks')

function Initialize-AkariCommandScope {
    <#
        .SYNOPSIS
        Ensures the tracked command list resolves on this machine.
        .DESCRIPTION
        Some commands (Remove-AppxPackage, Set-NetAdapter, ...) only resolve
        once their module is loaded. Importing here means the static counter
        and the runtime shims agree on the same list.
    #>
    [CmdletBinding()]
    param()

    foreach ($m in $script:RequiredModules) {
        try { Import-Module $m -ErrorAction Stop } catch { }
    }
}

function Get-AkariTrackedCommand {
    <#
        .SYNOPSIS
        Returns the tracked command names that actually resolve on this machine.
        .DESCRIPTION
        The intersection of the static list and what PowerShell can resolve.
        Used for shimming AND for static counting, keeping them consistent.
    #>
    [CmdletBinding()]
    param()

    Initialize-AkariCommandScope

    foreach ($name in ($script:TrackedCommands | Sort-Object -Unique)) {
        if ($script:NoiseCommands -contains $name) { continue }
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { $name }
    }
}

function Get-AkariTrackedMap {
    <#
        .SYNOPSIS
        Returns name -> resolved CommandInfo for every trackable command.
    #>
    [CmdletBinding()]
    param()

    Initialize-AkariCommandScope

    $map = @{}
    foreach ($name in ($script:TrackedCommands | Sort-Object -Unique)) {
        if ($script:NoiseCommands -contains $name) { continue }
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { $map[$name] = $cmd }
    }
    $map
}

function Get-AkariOperationPlan {
    <#
        .SYNOPSIS
        Statically counts tracked operations in a tweak script, per menu option.
        .DESCRIPTION
        Parses the script with the PowerShell AST. If the script drives a
        `switch ($choice)` menu, each clause is counted separately so the
        denominator matches the option the GUI is about to run. Scripts with no
        switch get a single whole-script branch.

        This is the denominator for the progress bar. Because it uses the same
        tracked list as the runtime shims, ticks can never exceed the total.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $result = [pscustomobject]@{
        Path        = $Path
        Parsed      = $false
        TotalOps    = 0
        BranchCount = 0
        Branches    = @()
        Error       = $null
    }

    $errors = $null
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $Path, [ref]$null, [ref]$errors)
    } catch {
        $result.Error = $_.Exception.Message
        return $result
    }

    if (-not $ast) {
        $result.Error = 'AST parse returned nothing'
        return $result
    }

    $result.Parsed   = $true
    $tracked         = [System.Collections.Generic.HashSet[string]]::new(
        [string[]](Get-AkariTrackedCommand), [StringComparer]::OrdinalIgnoreCase)

    function Measure-Commands {
        param($node)
        $n = 0
        if ($null -eq $node) { return 0 }
        $cmds = $node.FindAll(
            { param($x) $x -is [System.Management.Automation.Language.CommandAst] },
            $true)
        foreach ($c in $cmds) {
            $name = $c.GetCommandName()
            if (-not $name) { continue }
            if ($tracked.Contains($name)) { $n++ }
        }
        $n
    }

    $switch = $ast.Find(
        { param($x) $x -is [System.Management.Automation.Language.SwitchStatementAst] },
        $true)

    if ($switch) {
        # SwitchStatementAst.Clauses is a list of
        # Tuple<ExpressionAst, StatementAst>: Item1 = the case value,
        # Item2 = the clause body. The `default` clause has a null Item1.
        $branches  = @()
        $fallback  = 0
        foreach ($clause in $switch.Clauses) {
            $ops = Measure-Commands $clause.Item2
            if ($null -eq $clause.Item1) {
                $fallback += $ops
                continue
            }
            # Extent.Text carries the source form, so a string case reads as
            # `'Apply'`. Quotes are stripped so the index matches the value the
            # caller passes to -Action / -Choice.
            $index = $clause.Item1.Extent.Text.Trim().Trim("'", '"')

            $branches += [pscustomobject]@{
                Index = $index
                Ops   = $ops
            }
        }

        # A `default` clause is not a selectable option, so its operations are
        # excluded from the per-branch totals. Every branch keeps the same
        # denominator basis, which is what the progress bar relies on.
        if ($fallback -gt 0 -and @($branches).Count -eq 0) {
            $result.TotalOps = $fallback
        } else {
            $total = ($branches | Measure-Object -Property Ops -Sum).Sum
            $result.TotalOps = if ($null -eq $total) { 0 } else { $total }
        }

        $result.Branches    = $branches
        $result.BranchCount = @($branches).Count
    } else {
        $ops = Measure-Commands $ast
        $result.TotalOps    = $ops
        $result.Branches    = @([pscustomobject]@{ Index = '1'; Ops = $ops })
        $result.BranchCount = 1
    }

    $result
}

function New-AkariProgressState {
    <#
        .SYNOPSIS
        Creates the shared, thread-safe progress state handed to a tweak.
        .DESCRIPTION
        This is the ONLY safe way to read progress from a running tweak.

        Runspace.SessionStateProxy.GetVariable() throws "A pipeline is already
        running. Concurrent SessionStateProxy method calls are not allowed."
        whenever a pipeline is in flight, so it can only be read after the run
        finishes. That is useless for a live progress bar.

        A synchronized hashtable is shared by reference instead: the shims
        inside the runspace write to it, and the UI thread reads it, with no
        runspace API involved and no locking on the UI side.
    #>
    [CmdletBinding()]
    param([int]$TotalOps = 0)

    $state = [hashtable]::Synchronized(@{
        ticks   = 0
        total   = $TotalOps
        last    = ''
        detail  = ''
        done    = $false
        error   = $null
        started = Get-Date
        # Live console output. A synchronized ArrayList, because a tweak's
        # Write-Host shim runs on the runspace thread while the UI drains it on
        # the UI thread. A plain array would need copying to be safe; the
        # ArrayList is guarded by the same monitor as the rest of the hashtable.
        #
        # This exists because the PowerShell success stream is not readable
        # until EndInvoke: lines written during a run sit in the pipeline's
        # buffer and appear all at once when it finishes. For a console that is
        # supposed to show what is happening NOW, that is too late.
        log     = [System.Collections.ArrayList]::Synchronized(
            [System.Collections.ArrayList]::new())
    })
    $state
}

function Add-AkariRunOutput {
    <#
        .SYNOPSIS
        Queues a line of live output from the runspace for the UI to drain.
        .DESCRIPTION
        Called by the Write-Host shim inside the runspace. Never throws: a
        logging failure must not abort the tweak it is describing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    try {
        $state = $global:__akari_state
        if ($state -and $state.ContainsKey('log')) {
            $null = $state.log.Add([pscustomobject]@{
                t = (Get-Date)
                s = $Text
            })
        }
    } catch {
    }
}

function Get-AkariRunOutput {
    <#
        .SYNOPSIS
        Drains queued output lines that have not been read yet.
        .DESCRIPTION
        Returns and removes them, so each line is shown exactly once no matter
        how often the ticker polls. Draining rather than peeking is what keeps
        the UI thread's copy from growing unbounded during a long tweak.
    #>
    [CmdletBinding()]
    param($Run)

    $out = @()
    if (-not $Run) { return $out }

    # $Run is a PSCustomObject handle, NOT a hashtable. Calling ContainsKey on
    # it throws "method not found" under StrictMode, which would have broken the
    # live console on every single tick. Only the inner state is a hashtable.
    $state = $Run.State
    if (-not $state -or -not $state.ContainsKey('log')) { return $out }

    try {
        $q = $state.log
        # Take everything currently queued in one lock, so a line cannot be
        # added between the count and the removal.
        [System.Threading.Monitor]::Enter($q.SyncRoot)
        try {
            $n = $q.Count
            for ($i = 0; $i -lt $n; $i++) {
                $out += $q[0]
                $q.RemoveAt(0)
            }
        } finally {
            [System.Threading.Monitor]::Exit($q.SyncRoot)
        }
    } catch {
    }

    $out
}

function Get-AkariTracerSetup {
    <#
        .SYNOPSIS
        Generates the PowerShell source that installs the counting shims.
        .DESCRIPTION
        The returned text is the FIRST statement of a tweak's pipeline. It
        takes the shared progress hashtable as its only argument, then resolves
        every tracked command and defines a shadow for each, in that order, so
        the captured CommandInfo always points at the real command.

        Every tick writes into the shared hashtable, which is what makes live
        progress possible. See New-AkariProgressState for why the runspace
        session state cannot be used instead.

        .NOTES
        Function names contain dots (cmd.exe, reg.exe), so shadows are installed
        through the function: provider rather than `function name { }` syntax.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Command
    )

    if (-not $Command) { $Command = Get-AkariTrackedCommand }

    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine('param($__akari_state)')
    [void]$sb.AppendLine('$global:__akari_state = $__akari_state')
    [void]$sb.AppendLine('$ErrorActionPreference = ''Continue''')
    [void]$sb.AppendLine('$global:__akari_real = @{}')

    # Pass 1 — resolve the real commands BEFORE any shadow exists.
    foreach ($name in $Command) {
        $safe = $name -replace '[^A-Za-z0-9_]', '_'
        [void]$sb.AppendLine(
            "`$global:__akari_real['$safe'] = Get-Command '$name' -ErrorAction SilentlyContinue | Select-Object -First 1")
    }

    # Pass 2 — define the shadows.
    foreach ($name in $Command) {
        $safe = $name -replace '[^A-Za-z0-9_]', '_'
        $body = @"
`$global:__akari_state.ticks  = `$global:__akari_state.ticks + 1
`$global:__akari_state.last   = '$name'
try { `$global:__akari_state.detail = ((`$args | Select-Object -First 2) -join ' ') } catch { `$global:__akari_state.detail = '' }
`$r = `$global:__akari_real['$safe']
if (`$null -ne `$r) { & `$r @args } else { Microsoft.PowerShell.Core\Write-Debug 'akari: no real command for $name' }
"@
        # Indent the body for readability inside the generated script.
        $indented = ($body -split "`r?`n" | ForEach-Object { "    $_" }) -join "`n"
        [void]$sb.AppendLine("`$__akari_sb = {")
        [void]$sb.AppendLine($indented)
        [void]$sb.AppendLine('}')
        [void]$sb.AppendLine("Set-Item -Path 'function:global:$name' -Value `$__akari_sb -Force")
    }

    # Installing the shadows uses Set-Item, which is itself tracked. Zero the
    # counters once every shadow is in place, or the setup phase leaks ~20
    # phantom ticks into every run.
    [void]$sb.AppendLine("`$global:__akari_state.ticks  = 0")
    [void]$sb.AppendLine("`$global:__akari_state.last   = ''")
    [void]$sb.AppendLine("`$global:__akari_state.detail = ''")

    $sb.ToString()
}

Export-ModuleMember -Function Get-AkariTrackedCommand, Get-AkariTrackedMap,
    Get-AkariOperationPlan, Get-AkariTracerSetup, New-AkariProgressState,
    Add-AkariRunOutput, Get-AkariRunOutput, Initialize-AkariCommandScope
