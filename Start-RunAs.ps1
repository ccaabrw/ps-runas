<#
.SYNOPSIS
    Starts a new PowerShell session running under a specified domain user's credentials.

.DESCRIPTION
    Start-RunAs prompts for (or accepts) a domain user credential and then launches a new
    PowerShell console window whose process runs entirely under that identity.  This is equivalent
    to right-clicking "Run as different user" but works from the command line and is therefore
    scriptable and repeatable.

    The spawned session inherits no environment from the calling session – it is a clean,
    interactive shell owned by the target account, so you can load user-specific modules (such as
    the Active Directory module), map drives, or perform any privileged operations that require the
    target account's token.

    Note: Windows Terminal (wt.exe) is an MSIX-packaged application and cannot be started as a
    different user via CreateProcessWithLogonW (the API used by Start-Process -Credential).
    The script therefore always launches the PowerShell executable directly in a plain console
    window, regardless of whether wt.exe is installed.

.PARAMETER UserName
    The domain-qualified user name to run as, e.g. "CONTOSO\jdoe" or "jdoe@contoso.com".
    When omitted, Get-Credential will prompt interactively.

.PARAMETER Credential
    A pre-built PSCredential object.  Mutually exclusive with -UserName.

.PARAMETER WorkingDirectory
    The starting directory for the new session.  Defaults to the current directory.

.PARAMETER NoNewWindow
    This parameter is accepted for backwards compatibility but has no effect.
    Windows Terminal (wt.exe) cannot be launched as a different user (MSIX packaging
    restriction), so the session always opens in a plain PowerShell console window.

.PARAMETER ArgumentList
    Additional arguments forwarded verbatim to the PowerShell executable inside the new session.

.EXAMPLE
    .\Start-RunAs.ps1 -UserName "CONTOSO\AdminUser"

    Prompts for the password of CONTOSO\AdminUser and opens a new PowerShell console window
    running as that user.

.EXAMPLE
    $cred = Get-Credential -UserName "CONTOSO\AdminUser" -Message "Enter admin credentials"
    .\Start-RunAs.ps1 -Credential $cred

    Uses a pre-built credential object to start the session without a second prompt.

.EXAMPLE
    .\Start-RunAs.ps1 -UserName "CONTOSO\AdminUser" -WorkingDirectory "C:\AdminTools"

    Opens a PowerShell console window running as CONTOSO\AdminUser with C:\AdminTools as the
    starting directory.

.NOTES
    Requires Windows PowerShell 5.1 or PowerShell 7+.
    The target account must have permission to log on interactively on this machine.
    Windows Terminal (wt.exe) is not supported when running as a different user due to MSIX
    packaging restrictions; the session will always open in a plain PowerShell console window.
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

# Windows Terminal (wt.exe) is an MSIX-packaged application.
# CreateProcessWithLogonW (used internally by Start-Process -Credential) cannot
# launch MSIX-packaged applications, which would cause an "incorrect username or
# password" error even when the supplied credentials are correct.
# Therefore the script always launches the PowerShell executable directly with
# -Credential, regardless of whether wt.exe is present on the system.
$wtExe = (Get-Command 'wt.exe' -ErrorAction SilentlyContinue)?.Source

if ($wtExe) {
    Write-Warning "Windows Terminal (wt.exe) cannot be started as a different user because it is an MSIX-packaged application. Falling back to a plain PowerShell window."
}

$startParams = @{
    FilePath            = $psExe
    ArgumentList        = $innerArgs
    Credential          = $Credential
    WorkingDirectory    = $WorkingDirectory
    ErrorAction         = 'Stop'
}

Write-Host "Starting PowerShell session as '$($Credential.UserName)'..." -ForegroundColor Cyan

Start-Process @startParams

#endregion
