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

.PARAMETER Domain
    The Active Directory domain (DNS name or domain controller host name) to set as the default
    target for Active Directory and DNS Server cmdlets in the new session.  When this parameter
    is supplied, the spawned PowerShell window will have:

        $PSDefaultParameterValues['*-AD*:Server']       = '<Domain>'
        $PSDefaultParameterValues['*-Dns*:ComputerName'] = '<Domain>'

    pre-configured, so you can run Get-ADUser, Get-ADGroup, Get-DnsServerResourceRecord, etc.
    without having to specify -Server or -ComputerName on every call.

    When -ArgumentList contains -File, a temporary wrapper script is created that applies the
    settings before executing the specified script file.  When -ArgumentList contains -Command,
    the settings are prepended to the supplied command string.  When neither is present, the
    settings are injected via -Command so the interactive session starts with them already active.

    When -Domain is specified and -NetOnly is not explicitly provided, -NetOnly is automatically
    enabled.  Domain admin accounts typically lack interactive logon rights on local machines, so
    NetOnly mode (network credentials only, local token unchanged) is the safer default.  Pass
    -NetOnly:$false to override this behaviour and require a full interactive logon instead.

.PARAMETER WindowTitle
    The title to display in the title bar of the spawned PowerShell window.  When omitted, the
    window title is left at the default (the path of the executable).  To automatically show the
    domain and user name of the credential, pass the credential's UserName:

        .\Start-RunAs.ps1 -UserName "CONTOSO\AdminUser" -WindowTitle "CONTOSO\AdminUser"

    Or, when using a pre-built credential:

        .\Start-RunAs.ps1 -Credential $cred -WindowTitle $cred.UserName

.PARAMETER ForegroundColor
    The foreground (text) colour of the spawned PowerShell console window.  Accepts any named
    value from the System.ConsoleColor enumeration, e.g. 'White', 'Green', or 'Cyan'.  When
    omitted, the console keeps its default foreground colour.

.PARAMETER BackgroundColor
    The background colour of the spawned PowerShell console window.  Accepts any named value from
    the System.ConsoleColor enumeration, e.g. 'DarkBlue', 'Black', or 'DarkGray'.  When omitted,
    the console keeps its default background colour.

    When specified, Clear-Host is called after the colour is applied so that the entire console
    buffer is repainted with the new background.

.PARAMETER TitleBarColor
    The background colour of the window title bar, expressed as a six-digit hex RGB colour code
    with an optional leading '#', e.g. '#1E3A5F' or '1E3A5F'.

    This feature uses the DwmSetWindowAttribute API (DWMWA_CAPTION_COLOR) which is available on
    Windows 11 (build 22000) and later.  On earlier Windows versions the parameter is silently
    ignored.

.PARAMETER ArgumentList
    Additional arguments forwarded verbatim to the PowerShell executable inside the new session.

.PARAMETER TranscriptPath
    Path to a file where a transcript of the spawned session will be recorded.
    When specified, Start-Transcript is called at the very start of the new session
    and records all input and output to the given file for the lifetime of the
    session.  The file is created if it does not exist; if it already exists the
    transcript is appended to it.

    The path is resolved relative to the working directory of the spawned session
    (i.e. -WorkingDirectory), so an absolute path is recommended.  Parent
    directories must already exist.

.PARAMETER NetOnly
    Uses the LOGON_NETONLY logon flag (equivalent to "runas /netonly").

    When this switch is specified the new PowerShell window runs locally under your own
    account's token, but any network access (LDAP/Active Directory queries, UNC paths,
    etc.) performed inside that window will use the credentials you provided.

    Use this switch when the target account does not have the "Log on locally"
    (interactive logon) user right on this machine — which is common for privileged
    domain admin accounts in many organisations.  The standard Start-Process -Credential
    path requires that right; -NetOnly does not.

    When -Domain is specified, -NetOnly is enabled automatically unless -NetOnly:$false is
    passed explicitly.

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

.EXAMPLE
    .\Start-RunAs.ps1 -UserName "CONTOSO\AdminUser" -Domain "contoso.com"

    Opens a PowerShell console window running as CONTOSO\AdminUser with $PSDefaultParameterValues
    pre-set so that all Active Directory cmdlets target contoso.com without requiring -Server on
    every call.  Because -Domain is specified, -NetOnly is automatically enabled so the account
    does not need interactive logon rights on this machine.

.EXAMPLE
    $cred = Get-Credential -UserName "CONTOSO\AdminUser" -Message "Enter admin credentials"
    .\Start-RunAs.ps1 -Credential $cred -ForegroundColor White -BackgroundColor DarkBlue -TitleBarColor '#003366' -WindowTitle $cred.UserName

    Opens a PowerShell console window with a dark-blue background, white text, and a navy-blue
    title bar (Windows 11 only), making it easy to distinguish the elevated session at a glance.

.EXAMPLE
    .\Start-RunAs.ps1 -UserName "CONTOSO\AdminUser" -TranscriptPath "C:\Logs\admin-session.log"

    Opens a PowerShell console window running as CONTOSO\AdminUser and automatically starts
    recording a full transcript of the session to C:\Logs\admin-session.log.  If the file
    already exists the new transcript is appended to it.

.NOTES
    Requires Windows PowerShell 5.1 or PowerShell 7+.
    The target account must have permission to log on interactively on this machine unless
    -NetOnly is used (see -NetOnly for details).  When -Domain is specified, -NetOnly is
    automatically enabled, so interactive logon rights are not required in that case.
    Windows Terminal (wt.exe) is not supported when running as a different user due to MSIX
    packaging restrictions; the session will always open in a plain PowerShell console window.
    PowerShell 7 installed from the Microsoft Store is also MSIX-packaged and subject to the same
    restriction; the script will automatically fall back to an MSI-installed pwsh.exe or
    Windows PowerShell 5.1 in that case.  If Start-Process still fails with an "incorrect
    username or password" error (e.g. because the OS reported a non-standard image path for the
    MSIX process), the script will automatically retry with the non-MSIX fallback executables.
    If all retries fail and the credentials are known to be correct, re-run with -NetOnly.
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
    [switch] $NetOnly,

    [Parameter()]
    [string] $Domain,

    [Parameter()]
    [string] $WindowTitle,

    [Parameter()]
    [ValidateSet('Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta',
                 'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan', 'Red',
                 'Magenta', 'Yellow', 'White')]
    [string] $ForegroundColor,

    [Parameter()]
    [ValidateSet('Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta',
                 'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan', 'Red',
                 'Magenta', 'Yellow', 'White')]
    [string] $BackgroundColor,

    [Parameter()]
    [ValidatePattern('^#?[0-9A-Fa-f]{6}$')]
    [string] $TitleBarColor,

    [Parameter()]
    [string[]] $ArgumentList,

    [Parameter()]
    [string] $TranscriptPath
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

#region --- Apply defaults ---------------------------------------------------

# When -Domain is specified, NetOnly is the safer default: privileged domain
# accounts commonly lack interactive logon rights on local machines, so
# LOGON_NETONLY (network credentials only, local token unchanged) avoids that
# restriction.  The caller can opt out by passing -NetOnly:$false explicitly.
if ($Domain -and -not $PSBoundParameters.ContainsKey('NetOnly')) {
    $NetOnly = $true
}

#endregion

#region --- Derive credential components ------------------------------------

# Split the credential username into the parts expected by
# CreateProcessWithLogonW.  Done early so the values are available when
# building $setupParts (for spawned-session credential registration) as
# well as in the NetOnly launch block.
# For UPN format (user@domain) pass the full UPN as lpUsername with a null
# lpDomain, as documented by the API; for DOMAIN\user format split into the
# two components.
$credUser   = $Credential.UserName
$credDomain = $null
if ($credUser -match '^([^\\]+)\\(.+)$') {
    $credDomain = $Matches[1]
    $credUser   = $Matches[2]
}

# Derive the Windows Credential Manager target for the domain.
# For DOMAIN\user the target is the NETBIOS domain name; for UPN the
# target is the DNS domain portion (everything after the '@').
$credMgrTarget = if ($credDomain) {
    $credDomain
} elseif ($credUser -match '@(.+)$') {
    $Matches[1]
} else {
    $credUser
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

# When -WindowTitle, -ForegroundColor, -BackgroundColor, -TitleBarColor, and/or -Domain are
# supplied, build a combined setup line that is injected into the inner shell's startup command.
# All features use the same injection paths (-Command prepend, -File wrapper, or interactive
# -Command), so they are always applied together in a single pass.
$setupParts = [System.Collections.Generic.List[string]]::new()

if ($BackgroundColor) {
    $setupParts.Add("`$host.UI.RawUI.BackgroundColor = [System.ConsoleColor]::$BackgroundColor")
}

if ($ForegroundColor) {
    $setupParts.Add("`$host.UI.RawUI.ForegroundColor = [System.ConsoleColor]::$ForegroundColor")
}

# Repaint the full console buffer so the new background fills the entire window.
if ($BackgroundColor) {
    $setupParts.Add('Clear-Host')
}

if ($WindowTitle) {
    $titleEscaped = $WindowTitle.Replace("'", "''")
    $setupParts.Add("`$host.UI.RawUI.WindowTitle = '$titleEscaped'")
}

if ($TitleBarColor) {
    # Convert the six-digit hex RGB string to a Win32 COLORREF integer.
    # COLORREF is a 32-bit value laid out as 0x00BBGGRR (little-endian BGR),
    # so the red channel occupies bits 0-7, green bits 8-15, and blue bits 16-23.
    $hex      = $TitleBarColor.TrimStart('#')
    $r        = [System.Convert]::ToInt32($hex.Substring(0, 2), 16)  # chars 0-1 → R
    $g        = [System.Convert]::ToInt32($hex.Substring(2, 2), 16)  # chars 2-3 → G
    $b        = [System.Convert]::ToInt32($hex.Substring(4, 2), 16)  # chars 4-5 → B
    $colorRef = ($b -shl 16) -bor ($g -shl 8) -bor $r               # pack as BGR

    # Inject a DwmSetWindowAttribute call (DWMWA_CAPTION_COLOR = 35) into the spawned session.
    # This API requires Windows 11 (build 22000+); the try/catch ensures silent failure on
    # older systems.  Single-quoted literals inside the generated code avoid further escaping.
    $dwmCode = 'try { ' +
               'if (-not (''PsRunAsInternal.DwmHelper'' -as [type])) { ' +
               'Add-Type -Name DwmHelper -Namespace PsRunAsInternal ' +
               '-MemberDefinition ''[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int pvAttr, int cbAttr);'' ' +
               '}; ' +
               ('$_tbColor = {0}; ' -f $colorRef) +
               '[PsRunAsInternal.DwmHelper]::DwmSetWindowAttribute((Get-Process -Id $PID).MainWindowHandle, 35, [ref]$_tbColor, 4) | Out-Null ' +
               '} catch { }'
    $setupParts.Add($dwmCode)
}

if ($Domain) {
    $domainEscaped = $Domain.Replace("'", "''")
    $setupParts.Add("`$PSDefaultParameterValues['*-AD*:Server'] = '$domainEscaped'")
    $setupParts.Add("`$PSDefaultParameterValues['*-Dns*:ComputerName'] = '$domainEscaped'")
}

if ($TranscriptPath) {
    $transcriptEscaped = $TranscriptPath.Replace("'", "''")
    $setupParts.Add("Start-Transcript -Path '$transcriptEscaped' -Append")
}

if ($NetOnly) {
    # Register the domain credential in the SPAWNED session's Windows Credential
    # Manager so that SSPI finds it via the standard fallback lookup path.
    # LOGON_NETONLY creates a separate network logon session (managed by the
    # Secondary Logon service) whose credential cache is distinct from the calling
    # session; recent Windows security updates broke that cache, but SSPI's
    # Credential Manager fallback still works when an entry is written from within
    # the spawned process (which runs in the new network logon session context).
    # The password is protected with DPAPI so no plaintext appears on disk; the
    # spawned session inherits the same local user token and decrypts with the
    # same DPAPI key.
    try {
        $encryptedPassword   = ConvertFrom-SecureString $Credential.Password
        $credUserForScript   = $Credential.UserName.Replace("'", "''")
        $credTargetForScript = $credMgrTarget.Replace("'", "''")
        $netOnlyCredScript   = Join-Path ([System.IO.Path]::GetTempPath()) `
                                   ([System.IO.Path]::ChangeExtension(
                                       [System.IO.Path]::GetRandomFileName(), 'ps1'))
        @"
try {
    if (-not ('PsRunAsInternal.CredMgr' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PsRunAsInternal {
    public static class CredMgr {
        public const uint CRED_TYPE_DOMAIN_PASSWORD = 2;
        public const uint CRED_PERSIST_SESSION      = 1;
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct CREDENTIAL {
            public uint   Flags;
            public uint   Type;
            public string TargetName;
            public string Comment;
            public long   LastWritten;
            public uint   CredentialBlobSize;
            public IntPtr CredentialBlob;
            public uint   Persist;
            public uint   AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CredWrite(ref CREDENTIAL c, uint flags);
    }
}
'@
    }
    `$_sec = ConvertTo-SecureString '$encryptedPassword'
    `$_ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode(`$_sec)
    try {
        `$_ce = New-Object PsRunAsInternal.CredMgr+CREDENTIAL
        `$_ce.Type              = [PsRunAsInternal.CredMgr]::CRED_TYPE_DOMAIN_PASSWORD
        `$_ce.TargetName        = '$credTargetForScript'
        `$_ce.UserName          = '$credUserForScript'
        `$_ce.Persist           = [PsRunAsInternal.CredMgr]::CRED_PERSIST_SESSION
        `$_ce.CredentialBlobSize = [uint32](`$_sec.Length * 2)
        `$_ce.CredentialBlob    = `$_ptr
        [PsRunAsInternal.CredMgr]::CredWrite([ref]`$_ce, 0) | Out-Null
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode(`$_ptr)
        Remove-Variable -Name '_ptr','_ce','_sec' -ErrorAction SilentlyContinue
    }
} catch {} finally {
    Remove-Item -LiteralPath `$PSCommandPath -Force -ErrorAction SilentlyContinue
}
"@ | Set-Content -LiteralPath $netOnlyCredScript -Encoding UTF8
        $netOnlyCredScriptEscaped = $netOnlyCredScript.Replace("'", "''")
        $setupParts.Insert(0, "& '$netOnlyCredScriptEscaped'")
    } catch {
        Write-Warning ("Could not prepare credential registration script for the spawned " +
                       "session: $($_.Exception.Message). Network authentication (LDAP, " +
                       "AD queries) may fail on systems with recent Windows security " +
                       "updates that changed Secondary Logon service credential handling.")
    }
}

$setupLine = $setupParts -join '; '

if ($setupLine) {
    $argArray   = [string[]] $innerArgs
    $commandIdx = [Array]::IndexOf($argArray, '-Command')
    $fileIdx    = [Array]::IndexOf($argArray, '-File')

    if ($commandIdx -ge 0 -and ($commandIdx + 1) -lt $argArray.Length) {
        # Prepend the setup to the existing -Command value.
        $argArray[$commandIdx + 1] = "$setupLine; " + $argArray[$commandIdx + 1]
        $innerArgs = $argArray
    } elseif ($fileIdx -ge 0) {
        if (($fileIdx + 1) -ge $argArray.Length) {
            # -File is present but has no following script path – this is a malformed
            # invocation that would fail regardless.  Skip injection and leave $innerArgs
            # as-is so PowerShell surfaces the real error to the user.
            Write-Warning ("'-File' was found in -ArgumentList but has no following script " +
                           "path.  The setup commands (console colours / window title / domain defaults) cannot " +
                           "be injected.  Verify that -ArgumentList is well-formed.")
        } else {
        # -File mode: replace the target script with a temporary wrapper that applies
        # setup commands first, then calls the original script.  The wrapper removes
        # itself in a finally block (the file has been fully parsed into memory before
        # execution begins, so self-deletion is safe).
        $origScript  = $argArray[$fileIdx + 1]
        $scriptArgs  = if ($argArray.Length -gt $fileIdx + 2) {
            $argArray[($fileIdx + 2)..($argArray.Length - 1)]
        } else { @() }

        # Build the forwarded call line, quoting each token individually.
        $quotedOrig       = "'" + $origScript.Replace("'", "''") + "'"
        $quotedScriptArgs = $scriptArgs | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }
        $callLine         = ('& ' + ((@($quotedOrig) + @($quotedScriptArgs)) -join ' ')).TrimEnd()

        # Use GetRandomFileName to avoid the orphaned .tmp file left by GetTempFileName.
        $wrapperPath    = Join-Path ([System.IO.Path]::GetTempPath()) `
                              ([System.IO.Path]::ChangeExtension([System.IO.Path]::GetRandomFileName(), 'ps1'))
        $wrapperContent = @(
            $setupLine,
            'try {',
            "    $callLine",
            '} finally {',
            '    Remove-Item -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue',
            '}'
        )
        $wrapperContent | Set-Content -LiteralPath $wrapperPath -Encoding UTF8

        # Rebuild inner args: keep everything before -File, then add -File <wrapper>.
        # Any forwarded script args are baked into the wrapper; drop them here.
        # When $fileIdx is 0 there are no arguments before -File, so use an empty
        # array to avoid the 0..-1 PowerShell range producing unexpected results.
        $prefix    = if ($fileIdx -gt 0) { $argArray[0..($fileIdx - 1)] } else { @() }
        $innerArgs = $prefix + @('-File', $wrapperPath)
        }
    } else {
        # Interactive mode (no -File or -Command in $ArgumentList): append the
        # setup via -Command.  -NoExit placed before -Command keeps the window
        # open after the one-liner executes, leaving a ready-to-use session.
        # Preserve any other flags (e.g. -NoProfile) that were already in $argArray.
        $innerArgs = $argArray + @('-Command', $setupLine)
    }
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

Write-Host "Starting PowerShell session as '$($Credential.UserName)'..." -ForegroundColor Cyan

if ($NetOnly) {
    # -NetOnly mode: call CreateProcessWithLogonW directly with LOGON_NETONLY.
    # This is equivalent to "runas /netonly": the spawned process runs locally
    # under the current user's token, but any network access (LDAP, UNC paths,
    # etc.) uses the specified credentials.  No interactive logon right is
    # required for the target account on this machine.
    if (-not ('PsRunAsInternal.Win32' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace PsRunAsInternal {
    public static class Win32 {
        public const uint LOGON_NETONLY     = 2;
        public const uint CREATE_NEW_CONSOLE = 0x00000010;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct STARTUPINFO {
            public int    cb;
            public IntPtr lpReserved;
            public IntPtr lpDesktop;
            public IntPtr lpTitle;
            public int    dwX, dwY, dwXSize, dwYSize;
            public int    dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
            public short  wShowWindow, cbReserved2;
            public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct PROCESS_INFORMATION {
            public IntPtr hProcess, hThread;
            public int    dwProcessId, dwThreadId;
        }

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool CreateProcessWithLogonW(
            string lpUsername,
            string lpDomain,
            IntPtr lpPassword,
            uint   dwLogonFlags,
            string lpApplicationName,
            string lpCommandLine,
            uint   dwCreationFlags,
            IntPtr lpEnvironment,
            string lpCurrentDirectory,
            ref STARTUPINFO       lpStartupInfo,
            out PROCESS_INFORMATION lpProcessInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);
    }
}
'@
    }

    # $credUser, $credDomain, and $credMgrTarget were derived before $setupParts
    # was built so the values are shared with the spawned-session credential
    # registration script injected into $setupParts above.

    # Build a properly-quoted command line string for lpCommandLine.
    $quotedExe = '"' + $psExe.Replace('"', '""') + '"'
    if ($innerArgs) {
        $quotedArgs = $innerArgs | ForEach-Object { '"' + $_.Replace('"', '""') + '"' }
        $cmdLine = $quotedExe + ' ' + ($quotedArgs -join ' ')
    } else {
        $cmdLine = $quotedExe
    }

    # Keep the plaintext password in memory as briefly as possible.
    $passwordPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode(
                       $Credential.Password)
    try {
        $si    = New-Object PsRunAsInternal.Win32+STARTUPINFO
        $si.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($si)
        $pi    = New-Object PsRunAsInternal.Win32+PROCESS_INFORMATION

        # Register the credential in Windows Credential Manager (best-effort).
        # Recent Windows security updates changed how LOGON_NETONLY stores
        # network credentials in the Secondary Logon service, causing
        # "Authentication failed, see inner exception." for any operation that
        # requires network authentication in the spawned session (e.g. LDAP /
        # Active Directory queries).  Storing a CRED_TYPE_DOMAIN_PASSWORD entry
        # with CRED_PERSIST_SESSION persistence makes the credential available
        # via the standard SSPI credential-lookup path so that both Kerberos and
        # NTLM authentication succeed in the new window.  The entry is scoped to
        # the current Windows logon session and is removed automatically when the
        # user signs out.
        try {
            if (-not ('PsRunAsInternal.CredMgr' -as [type])) {
                Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace PsRunAsInternal {
    public static class CredMgr {
        public const uint CRED_TYPE_DOMAIN_PASSWORD = 2;
        public const uint CRED_PERSIST_SESSION      = 1;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct CREDENTIAL {
            public uint   Flags;
            public uint   Type;
            public string TargetName;
            public string Comment;
            public long   LastWritten;
            public uint   CredentialBlobSize;
            public IntPtr CredentialBlob;
            public uint   Persist;
            public uint   AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CredWrite(ref CREDENTIAL userCredential, uint flags);
    }
}
'@
            }
            $credEntry = New-Object PsRunAsInternal.CredMgr+CREDENTIAL
            $credEntry.Type = [PsRunAsInternal.CredMgr]::CRED_TYPE_DOMAIN_PASSWORD
            $credEntry.TargetName = $credMgrTarget
            $credEntry.UserName = $Credential.UserName
            $credEntry.Persist = [PsRunAsInternal.CredMgr]::CRED_PERSIST_SESSION
            # CredentialBlob must be the password encoded as UTF-16LE bytes without a
            # null terminator.  $passwordPtr was obtained from SecureStringToGlobalAllocUnicode,
            # which produces exactly that layout followed by a null terminator; the
            # null is excluded by limiting CredentialBlobSize to Password.Length * 2.
            $credEntry.CredentialBlobSize = [uint32]($Credential.Password.Length * 2)
            $credEntry.CredentialBlob = $passwordPtr
            if (-not ([PsRunAsInternal.CredMgr]::CredWrite([ref]$credEntry, 0))) {
                $credWriteErr = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Warning ("Could not register credentials in Windows Credential Manager " +
                               "(Win32 error $credWriteErr). Network authentication in the new " +
                               "session may fail on systems with recent Windows security updates " +
                               "that changed Secondary Logon service credential handling.")
            }
        } catch {
            Write-Warning ("Could not register credentials in Windows Credential Manager: " +
                           "$($_.Exception.Message). Network authentication in the new session " +
                           "may fail on systems with recent Windows security updates that changed " +
                           "Secondary Logon service credential handling.")
        }

        $ok = [PsRunAsInternal.Win32]::CreateProcessWithLogonW(
            $credUser, $credDomain, $passwordPtr,
            [PsRunAsInternal.Win32]::LOGON_NETONLY,
            $psExe, $cmdLine,
            [PsRunAsInternal.Win32]::CREATE_NEW_CONSOLE,
            [IntPtr]::Zero,
            $WorkingDirectory,
            [ref]$si,
            [ref]$pi)

        if (-not $ok) {
            $errCode  = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            $win32err = [System.ComponentModel.Win32Exception]::new($errCode)
            throw ("Could not start a PowerShell session as '$($Credential.UserName)' " +
                   "with -NetOnly. The underlying error was: $($win32err.Message) " +
                   "(Win32 error $errCode). Verify that the credentials are correct.")
        }

        # We don't need to track the child process; close the handles.
        if ($pi.hProcess -ne [IntPtr]::Zero) {
            [PsRunAsInternal.Win32]::CloseHandle($pi.hProcess) | Out-Null
        }
        if ($pi.hThread -ne [IntPtr]::Zero) {
            [PsRunAsInternal.Win32]::CloseHandle($pi.hThread) | Out-Null
        }
    } finally {
        # Zero and free the plaintext password regardless of success or failure.
        [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($passwordPtr)
    }
} else {
    $startParams = @{
        FilePath            = $psExe
        ArgumentList        = $innerArgs
        Credential          = $Credential
        WorkingDirectory    = $WorkingDirectory
        ErrorAction         = 'Stop'
    }

    try {
        Start-Process @startParams
    } catch {
        # If the error is ERROR_LOGON_FAILURE (Win32 error 1326) the executable may
        # be an MSIX-packaged application that was not caught by the earlier detection
        # step (e.g. the OS reported a virtualized image path).  Retry with the known
        # non-MSIX PowerShell executables before surfacing the error to the user.
        # Recent Windows security updates can also cause Start-Process -Credential to
        # throw System.Security.Authentication.AuthenticationException ("Authentication
        # failed, see inner exception.") instead of Win32Exception 1326 for the same
        # failure.  That exception may be nested several levels deep in the chain
        # (e.g. MethodInvocationException → InvalidOperationException →
        # AuthenticationException), so walk the entire InnerException chain.
        $isLogonFailure = $false
        $searchEx = $_.Exception
        while ($searchEx -and -not $isLogonFailure) {
            $win32Ex = $searchEx -as [System.ComponentModel.Win32Exception]
            $isLogonFailure = ($win32Ex -and $win32Ex.NativeErrorCode -eq 1326) -or
                              ($searchEx.Message -like '*user name or password*') -or
                              ($searchEx -is [System.Security.Authentication.AuthenticationException])
            $searchEx = $searchEx.InnerException
        }

        if (-not $isLogonFailure) { throw }

        $initialExe = $startParams['FilePath']
        $retryExes = @(
            (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
            (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        ) | Where-Object { (Test-Path -LiteralPath $_) -and ($_ -ne $initialExe) }

        $launched = $false
        # Capture the most recent logon-failure exception so it can be included in
        # the final error message when all candidates are exhausted.  Initialized to
        # the failure of the initial executable as a fallback for the (unlikely) case
        # where $retryExes is empty.
        $lastCaughtError = $_
        foreach ($retryExe in $retryExes) {
            try {
                Write-Warning ("Could not start '$initialExe' as a different user " +
                               "(the executable may be MSIX-packaged). Retrying with '$retryExe'...")
                $startParams['FilePath'] = $retryExe
                Start-Process @startParams
                $launched = $true
                break
            } catch {
                # Only suppress logon-failure errors (Win32 1326 or AuthenticationException at
                # any nesting depth), which may indicate that this candidate is also
                # MSIX-packaged.  Any other error is real (e.g. wrong credentials, logon type
                # not permitted) and should be surfaced immediately rather than silently discarded.
                $isRetryLogonFailure = $false
                $searchEx = $_.Exception
                while ($searchEx -and -not $isRetryLogonFailure) {
                    $retryWin32Ex = $searchEx -as [System.ComponentModel.Win32Exception]
                    $isRetryLogonFailure = ($retryWin32Ex -and $retryWin32Ex.NativeErrorCode -eq 1326) -or
                                           ($searchEx.Message -like '*user name or password*') -or
                                           ($searchEx -is [System.Security.Authentication.AuthenticationException])
                    $searchEx = $searchEx.InnerException
                }
                if (-not $isRetryLogonFailure) { throw }
                $lastCaughtError = $_
                # Logon failure on this candidate; try the next one.
            }
        }

        if (-not $launched) {
            $attempted = (@($initialExe) + @($retryExes)) -join "', '"
            # Surface the underlying Win32 error so the user can diagnose the real
            # cause (e.g. wrong password, account locked, domain unreachable, missing
            # interactive logon right) rather than seeing only the generic message.
            # Walk the full exception chain to find the deepest Win32Exception.
            $lcWin32 = $null
            $searchEx = $lastCaughtError.Exception
            while ($searchEx -and -not $lcWin32) {
                $lcWin32 = $searchEx -as [System.ComponentModel.Win32Exception]
                $searchEx = $searchEx.InnerException
            }
            $errDetail = if ($lcWin32) {
                " The underlying error was: $($lcWin32.Message) (Win32 error $($lcWin32.NativeErrorCode))."
            } else {
                " The underlying error was: $($lastCaughtError.Exception.Message)."
            }
            throw ("Could not start a PowerShell session as '$($Credential.UserName)'. " +
                   "All candidate executables failed: '$attempted'.$errDetail " +
                   "Verify that the credentials are correct and that the account has " +
                   "permission to log on interactively on this machine. " +
                   "If the credentials are correct but the account lacks interactive logon " +
                   "rights on this machine, re-run with the -NetOnly switch.")
        }
    }
}

#endregion
