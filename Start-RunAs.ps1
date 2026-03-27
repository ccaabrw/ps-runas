<#
.SYNOPSIS
    Starts a new PowerShell session in Windows Terminal running under a specified domain user's credentials.

.DESCRIPTION
    Start-RunAs prompts for (or accepts) a domain user credential and then launches a new Windows
    Terminal tab/window whose PowerShell process runs entirely under that identity.  This is
    equivalent to right-clicking "Run as different user" but works from the command line and is
    therefore scriptable and repeatable.

    The spawned session inherits no environment from the calling session – it is a clean,
    interactive shell owned by the target account, so you can load user-specific modules (such as
    the Active Directory module), map drives, or perform any privileged operations that require the
    target account's token.

.PARAMETER UserName
    The domain-qualified user name to run as, e.g. "CONTOSO\jdoe" or "jdoe@contoso.com".
    When omitted, Get-Credential will prompt interactively.

.PARAMETER Credential
    A pre-built PSCredential object.  Mutually exclusive with -UserName.

.PARAMETER WorkingDirectory
    The starting directory for the new session.  Defaults to the current directory.

.PARAMETER NoNewWindow
    When specified, the new session opens inside the current Windows Terminal window as a new tab
    instead of a new window.  Ignored when Windows Terminal (wt.exe) is not available.

.PARAMETER ArgumentList
    Additional arguments forwarded verbatim to the PowerShell executable inside the new session.

.EXAMPLE
    .\Start-RunAs.ps1 -UserName "CONTOSO\AdminUser"

    Prompts for the password of CONTOSO\AdminUser and opens a new Windows Terminal window running
    PowerShell as that user.

.EXAMPLE
    $cred = Get-Credential -UserName "CONTOSO\AdminUser" -Message "Enter admin credentials"
    .\Start-RunAs.ps1 -Credential $cred

    Uses a pre-built credential object to start the session without a second prompt.

.EXAMPLE
    .\Start-RunAs.ps1 -UserName "CONTOSO\AdminUser" -NoNewWindow

    Opens a new tab in the current Windows Terminal window running as CONTOSO\AdminUser.

.NOTES
    Requires Windows PowerShell 5.1 or PowerShell 7+.
    The target account must have permission to log on interactively on this machine.
    Windows Terminal (wt.exe) must be installed for the best experience; the script falls back to
    a plain powershell.exe window when wt.exe is not found on the PATH.
#>

[CmdletBinding(DefaultParameterSetName = 'ByUserName')]
param (
    [Parameter(ParameterSetName = 'ByUserName', Position = 0)]
    [string] $UserName,

    [Parameter(ParameterSetName = 'ByCredential', Mandatory)]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter()]
    [string] $WorkingDirectory = (Get-Location).Path,

    [Parameter()]
    [switch] $NoNewWindow,

    [Parameter()]
    [string[]] $ArgumentList
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region --- Resolve credential -----------------------------------------------

if ($PSCmdlet.ParameterSetName -eq 'ByUserName') {
    $promptMessage = if ($UserName) {
        "Enter the password for $UserName"
    } else {
        "Enter domain user credentials"
    }

    $credParams = @{ Message = $promptMessage }
    if ($UserName) { $credParams['UserName'] = $UserName }

    $Credential = Get-Credential @credParams
}

if (-not $Credential) {
    throw 'No credential supplied – operation cancelled.'
}

#endregion

#region --- Locate shell executable ------------------------------------------

# Prefer the same PowerShell host that is currently running so that the new
# session uses the same major version (e.g. pwsh 7 spawns pwsh 7).
$psExe = (Get-Process -Id $PID).Path

if (-not (Test-Path -LiteralPath $psExe)) {
    # Fallback: resolve from PSHOME
    $psExe = Join-Path $PSHOME (
        if ($IsCoreCLR) { 'pwsh.exe' } else { 'powershell.exe' }
    )
}

#endregion

#region --- Build argument list for the inner shell --------------------------

# Always start with -NoExit so the window stays open for interaction.
# The working directory is handled by Start-Process -WorkingDirectory, which
# sets the initial directory of the spawned process (and therefore the shell).
# Avoid mixing -Command and -File in the same argument list – when the caller
# supplies their own -File or -Command via $ArgumentList, those are used as-is.
$innerArgs = @('-NoExit')

if ($ArgumentList) {
    $innerArgs += $ArgumentList
}

#endregion

#region --- Launch -----------------------------------------------------------

# Try Windows Terminal first; fall back to a plain console window.
$wtExe = (Get-Command 'wt.exe' -ErrorAction SilentlyContinue)?.Source

$startParams = @{
    Credential          = $Credential
    WorkingDirectory    = $WorkingDirectory
    ErrorAction         = 'Stop'
}

if ($wtExe) {
    Write-Verbose "Launching via Windows Terminal: $wtExe"

    # Build the wt command line.
    # wt syntax:  wt [options] <command> [arguments]
    # We pass the PowerShell executable and its arguments as a wt subcommand.
    $wtArgs = @()
    if ($NoNewWindow) {
        # Open as a new tab in the existing window.
        $wtArgs += 'new-tab'
    }
    $wtArgs += '--'
    $wtArgs += $psExe
    $wtArgs += $innerArgs

    $startParams['FilePath']     = $wtExe
    $startParams['ArgumentList'] = $wtArgs
} else {
    Write-Warning "wt.exe not found – falling back to a plain PowerShell window."

    $startParams['FilePath']     = $psExe
    $startParams['ArgumentList'] = $innerArgs
}

Write-Host "Starting PowerShell session as '$($Credential.UserName)'..." -ForegroundColor Cyan

Start-Process @startParams

#endregion
