<#
    SystemInfo.psm1 — the one-line spec strip under the title bar.

    Everything here is a read-only query, cached on first use because none of it
    changes while the window is open (except the pending-restart flag, which is
    re-read on demand).
#>

Set-StrictMode -Version Latest

$script:Cache = $null

function Get-AkariSpec {
    <#
        .SYNOPSIS
        Builds the spec strip string. Black and white, monospace, fixed columns.
    #>
    [CmdletBinding()]
    param([switch]$Refresh)

    if ($script:Cache -and -not $Refresh) { return $script:Cache }

    $os  = [System.Environment]::OSVersion.Version
    $cpu = 'unknown'
    $gpu = 'unknown'
    $ram = 'unknown'

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $ram = '{0:N0} GB' -f ($cs.TotalPhysicalMemory / 1GB)

        $cpuPart = (Get-CimInstance Win32_Processor -ErrorAction Stop |
            Select-Object -First 1).Name
        if ($cpuPart) {
            $cpuPart = ($cpuPart -replace '\(R\)|\(TM\)|CPU|Processor', '').Trim()
            $cpuPart = ($cpuPart -replace '\s+', ' ')
            if ($cpuPart.Length -gt 26) { $cpuPart = $cpuPart.Substring(0, 26) }
            $cpu = $cpuPart
        }

        $gpuPart = (Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -and $_.Name -notmatch 'Remote|Basic' } |
            Select-Object -First 1).Name
        if ($gpuPart) {
            $gpuPart = ($gpuPart -replace '\(R\)|\(TM\)', '').Trim() -replace '\s+', ' '
            if ($gpuPart.Length -gt 26) { $gpuPart = $gpuPart.Substring(0, 26) }
            $gpu = $gpuPart
        }
    } catch {
        # A missing WMI class must not stop the window opening.
    }

    $bits = if ([System.Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }

    $spec = @(
        "OS   $($os.Major).$($os.Minor).$($os.Build) $bits"
        "CPU  $cpu"
        "RAM  $ram"
        "GPU  $gpu"
    ) -join '   |   '

    $script:Cache = $spec
    $script:Cache
}

function Get-AkariIsAdmin {
    <#
        .SYNOPSIS
        True when the host process is elevated. Every tweak writes HKLM, so the
        GUI is useless without it and Main.ps1 refuses to start otherwise.
    #>
    [CmdletBinding()]
    param()

    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-AkariRestartPending {
    <#
        .SYNOPSIS
        Detects the two Windows pending-restart markers.
        .DESCRIPTION
        Returns $true if either CBS has queued a restart or the PendingFileRename
        list is non-empty. Used for the restart badge in the title bar.
    #>
    [CmdletBinding()]
    param()

    $pending = $false

    try {
        $keys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        )
        foreach ($k in $keys) {
            if (Test-Path $k) { $pending = $true; break }
        }
    } catch { }

    if (-not $pending) {
        try {
            $sm = Get-ItemProperty `
                'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
                -Name PendingFileRenameOperations -ErrorAction Stop
            if ($sm.PendingFileRenameOperations) { $pending = $true }
        } catch { }
    }

    $pending
}

function Get-AkariFolderSignature {
    <#
        .SYNOPSIS
        Fingerprint of the tweak folders, for the F5 refresh check.
        .DESCRIPTION
        Compares name, size and last-write time of every tweak script. Adding,
        removing or editing any script changes the signature, so Main.ps1 can
        rebuild the catalog only when something actually moved.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Catalog)

    $parts = foreach ($folder in $Catalog) {
        foreach ($s in $folder.Scripts) {
            $f = Get-Item $s.Path
            '{0}|{1}|{2}' -f $s.RelPath, $f.Length, $f.LastWriteTimeUtc.Ticks
        }
    }
    $joined = $parts -join "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($joined)))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

Export-ModuleMember -Function Get-AkariSpec, Get-AkariIsAdmin,
    Test-AkariRestartPending, Get-AkariFolderSignature
