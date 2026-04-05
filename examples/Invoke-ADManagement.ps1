<#
.SYNOPSIS
    Example: open a Windows Terminal session as a domain admin and work with
    the Active Directory PowerShell module.

.DESCRIPTION
    This script demonstrates the typical workflow for a helpdesk engineer or
    system administrator who needs to perform Active Directory tasks under a
    privileged domain account without signing out of their regular session.

    Steps performed:
      1.  Prompt for domain admin credentials.
      2.  Open a new Windows Terminal / PowerShell window running under those
          credentials via Start-RunAs.ps1.
      3.  Inside the elevated session, import the RSAT Active Directory module
          and run a handful of illustrative AD queries / changes.

    Note: this file is an *example template*.  The AD commands inside the
    $adScript here-string are what will execute in the new privileged session.
    Adapt them to your environment as needed.

.PARAMETER DomainAdmin
    Domain-qualified username of the AD administrator account, e.g.
    "CONTOSO\ADAdmin" or "adadmin@contoso.com".

.PARAMETER Domain
    DNS name of the Active Directory domain (used only inside the example
    queries).  Defaults to the domain of the current machine.

.PARAMETER NetOnly
    Passes the -NetOnly switch through to Start-RunAs.ps1, which causes
    the new PowerShell window to run locally under your own account while
    routing all network access (LDAP, UNC paths, etc.) through the specified
    domain admin credentials.

    Use this when the target account does not have the "Log on locally"
    (interactive logon) user right on this machine — which is common for
    privileged domain admin accounts in many organisations.

.EXAMPLE
    .\examples\Invoke-ADManagement.ps1 -DomainAdmin "CONTOSO\ADAdmin"

    Prompts for the password of CONTOSO\ADAdmin, then opens a Windows Terminal
    tab that imports the AD module and is ready for interactive AD management.

.EXAMPLE
    .\examples\Invoke-ADManagement.ps1 -DomainAdmin "CONTOSO\ADAdmin" -Domain "contoso.com"

    Same as above but targets the contoso.com domain explicitly.

.EXAMPLE
    .\examples\Invoke-ADManagement.ps1 -DomainAdmin "CONTOSO\ADAdmin" -NetOnly

    Use when the domain admin account does not have interactive logon rights on
    this machine.  The new window runs locally as your own account but all AD
    queries and network access use the specified credentials.

.NOTES
    Prerequisites:
      • RSAT: Active Directory Domain Services and Lightweight Directory
        Services Tools must be installed on the workstation.
        Install with:
            Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
      • The Start-RunAs.ps1 script must exist in the parent directory
        (..\ relative to this file).
      • -NetOnly does not require the target account to have interactive logon
        rights on this machine; it is equivalent to "runas /netonly".
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $DomainAdmin,

    [Parameter()]
    [string] $Domain = $env:USERDNSDOMAIN,

    [Parameter()]
    [switch] $NetOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region --- Collect credentials ----------------------------------------------

$credential = Get-Credential -UserName $DomainAdmin `
                             -Message  "Enter password for $DomainAdmin (AD management session)"

#endregion

#region --- AD commands to run in the new session ----------------------------

# Everything in this here-string will be executed inside the privileged
# PowerShell window that Start-RunAs.ps1 opens.  Edit freely.
$adScript = @"
# ── Active Directory Management Session ─────────────────────────────────────
# Running as: $($credential.UserName)
# Domain    : $Domain
# ─────────────────────────────────────────────────────────────────────────────

# Set the default -Server for all AD cmdlets and -ComputerName for DNS Server
# cmdlets so interactive commands do not need to specify them explicitly.
`$PSDefaultParameterValues['*-AD*:Server'] = '$Domain'
`$PSDefaultParameterValues['*-Dns*:ComputerName'] = '$Domain'

# 1. Import the ActiveDirectory module (requires RSAT to be installed)
Import-Module ActiveDirectory -ErrorAction Stop
Write-Host 'ActiveDirectory module loaded.' -ForegroundColor Green

# 2. Confirm which domain we are connected to
`$adDomain = Get-ADDomain -Server '$Domain'
Write-Host "Connected to domain : `$(`$adDomain.DNSRoot)" -ForegroundColor Cyan
Write-Host "Domain controller   : `$(`$adDomain.PDCEmulator)"

# 3. List the first 10 enabled user accounts (sorted by name)
Write-Host ''
Write-Host '--- First 10 enabled user accounts ---' -ForegroundColor Yellow
Get-ADUser -Filter { Enabled -eq `$true } -Server '$Domain' |
    Select-Object -First 10 Name, SamAccountName, DistinguishedName |
    Format-Table -AutoSize

# 4. List all members of the Domain Admins group
Write-Host '--- Members of Domain Admins ---' -ForegroundColor Yellow
Get-ADGroupMember -Identity 'Domain Admins' -Server '$Domain' |
    Select-Object Name, SamAccountName, objectClass |
    Format-Table -AutoSize

# 5. Show computers in the domain (first 10)
Write-Host '--- First 10 domain computers ---' -ForegroundColor Yellow
Get-ADComputer -Filter * -Server '$Domain' |
    Select-Object -First 10 Name, DNSHostName, OperatingSystem |
    Format-Table -AutoSize

# The session remains open (-NoExit) so you can run further AD commands.
Write-Host ''
Write-Host 'AD management session ready.  Type your AD commands below.' -ForegroundColor Green
"@

#endregion

#region --- Launch privileged Windows Terminal session -----------------------

$startRunAs = Join-Path $PSScriptRoot '..\Start-RunAs.ps1'

if (-not (Test-Path -LiteralPath $startRunAs)) {
    throw "Cannot find Start-RunAs.ps1 at expected path: $startRunAs"
}

# Write the AD script to a temporary file so it can be passed as -File to
# the inner PowerShell session (avoids quoting headaches on the command line).
$tempScript = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'

try {
    $adScript | Set-Content -LiteralPath $tempScript -Encoding UTF8

    $netOnlySuffix = if ($NetOnly) { ' (NetOnly - network credentials only)' } else { '' }
    Write-Host "Opening Windows Terminal as '$DomainAdmin' for AD management$netOnlySuffix..." `
               -ForegroundColor Cyan

    & $startRunAs `
        -Credential      $credential `
        -ArgumentList    @('-File', $tempScript) `
        -NetOnly:$NetOnly `
        -Verbose:($VerbosePreference -eq 'Continue')
}
finally {
    # Give the spawned process a moment to read the temp file before we remove it.
    Start-Sleep -Seconds 3
    Remove-Item -LiteralPath $tempScript -ErrorAction SilentlyContinue
}

#endregion
