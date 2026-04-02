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

    Note: PowerShell 7 installed from the Microsoft Store is also an MSIX-packaged application
    and shares the same restriction.  If the currently-running PowerShell host is Store-installed,
    the script automatically falls back to a traditionally-installed PowerShell executable
    (MSI-installed pwsh.exe, then Windows PowerShell 5.1).  The MSIX check uses both the
    Windows API GetCurrentPackageFullName() and a path-based heuristic for maximum reliability.

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
    PowerShell 7 installed from the Microsoft Store is also MSIX-packaged and subject to the same
    restriction; the script will automatically fall back to an MSI-installed pwsh.exe or
    Windows PowerShell 5.1 in that case.  If Start-Process still fails with an "incorrect
    username or password" error (e.g. because the OS reported a non-standard image path for the
    MSIX process), the script will automatically retry with the non-MSIX fallback executables.
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

# CreateProcessWithLogonW (used internally by Start-Process -Credential) cannot
# launch MSIX-packaged executables – this produces an "incorrect username or
# password" error even with valid credentials.  PowerShell 7 can be installed
# from the Microsoft Store as an MSIX package, so detect that case and fall back
# to a traditionally-installed (MSI or in-box) PowerShell executable.
#
# Detection uses two complementary methods:
#   1. Windows API: GetCurrentPackageFullName() – the authoritative signal that
#      the current process is running inside an MSIX package, regardless of where
#      the image file happens to live on disk.
#   2. Path heuristic: check whether the image path falls under a known MSIX
#      installation root (belt-and-suspenders, and covers cases where the API is
#      unavailable, e.g. older OS versions).

$currentProcessIsPackaged = $false
try {
    # P/Invoke GetCurrentPackageFullName from kernel32.dll.
    # The function returns APPMODEL_ERROR_NO_PACKAGE (15700) when the calling
    # process has no package identity; any other return value means it does.
    # IntPtr is used for the optional buffer parameter because we pass a null
    # pointer (we only care about the return code, not the actual package name).
    if (-not ('PsRunAsInternal.NativeMethods' -as [type])) {
        Add-Type -Namespace 'PsRunAsInternal' -Name 'NativeMethods' -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
public static extern int GetCurrentPackageFullName(
    ref int packageFullNameLength,
    IntPtr packageFullName);
'@
    }
    $bufLen = 0
    $currentProcessIsPackaged = ([PsRunAsInternal.NativeMethods]::GetCurrentPackageFullName([ref]$bufLen, [IntPtr]::Zero) -ne 15700)
} catch {
    # Add-Type or the P/Invoke call failed (e.g. non-Windows OS or security
    # policy prevents inline compilation).  Fall through to path-based detection.
}

$msixRoots = @(
    [System.IO.Path]::Combine($env:ProgramFiles, 'WindowsApps'),
    [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft', 'WindowsApps')
)

if ($currentProcessIsPackaged -or ($msixRoots | Where-Object { $psExe -like "$_\*" })) {
    Write-Warning ("The running PowerShell host ('{0}') is an MSIX-packaged application " +
                   "and cannot be started as a different user. Searching for a " +
                   "traditionally-installed PowerShell executable...") -f $psExe

    $candidateExes = @(
        # PowerShell 7+ MSI install (default path used by all 7.x releases)
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        # Windows PowerShell is inbox and is never distributed as an MSIX package
        (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    )

    $fallbackExe = $candidateExes | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if (-not $fallbackExe) {
        throw ("No traditionally-installed PowerShell executable was found. " +
               "To run as a different user, please install PowerShell 7 via the MSI " +
               "installer from https://github.com/PowerShell/PowerShell/releases " +
               "instead of the Microsoft Store, or use Windows PowerShell 5.1.")
    }

    Write-Warning "Falling back to '$fallbackExe'."
    $psExe = $fallbackExe
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

try {
    Start-Process @startParams
} catch {
    # If the error is ERROR_LOGON_FAILURE (Win32 error 1326) the executable may
    # be an MSIX-packaged application that was not caught by the earlier detection
    # step (e.g. the OS reported a virtualized image path).  Retry with the known
    # non-MSIX PowerShell executables before surfacing the error to the user.
    # Check via the Win32 error code first (locale-independent), then fall back
    # to a message-string match for robustness across PowerShell versions.
    $win32Ex = $_.Exception.InnerException -as [System.ComponentModel.Win32Exception]
    $isLogonFailure = ($win32Ex -and $win32Ex.NativeErrorCode -eq 1326) -or
                      ($_.Exception.Message -like '*user name or password*')

    if (-not $isLogonFailure) { throw }

    $initialExe = $startParams['FilePath']
    $retryExes = @(
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    ) | Where-Object { (Test-Path -LiteralPath $_) -and ($_ -ne $initialExe) }

    $launched = $false
    foreach ($retryExe in $retryExes) {
        try {
            Write-Warning ("Could not start '$initialExe' as a different user " +
                           "(the executable may be MSIX-packaged). Retrying with '$retryExe'...")
            $startParams['FilePath'] = $retryExe
            Start-Process @startParams
            $launched = $true
            break
        } catch {
            # Only suppress logon-failure errors (Win32 1326), which may indicate
            # that this candidate is also MSIX-packaged.  Any other error is real
            # (e.g. wrong credentials, logon type not permitted) and should be
            # surfaced immediately rather than silently discarded.
            $retryWin32Ex = $_.Exception.InnerException -as [System.ComponentModel.Win32Exception]
            $isRetryLogonFailure = ($retryWin32Ex -and $retryWin32Ex.NativeErrorCode -eq 1326) -or
                                   ($_.Exception.Message -like '*user name or password*')
            if (-not $isRetryLogonFailure) { throw }
            # Logon failure on this candidate; try the next one.
        }
    }

    if (-not $launched) {
        $attempted = (@($initialExe) + @($retryExes)) -join "', '"
        throw ("Could not start a PowerShell session as '$($Credential.UserName)'. " +
               "All candidate executables failed: '$attempted'. " +
               "Verify that the credentials are correct and that the account has " +
               "permission to log on interactively on this machine.")
    }
}

#endregion
