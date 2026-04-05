<#
.SYNOPSIS
    Removes a saved credential from the local credential store.

.DESCRIPTION
    Remove-SavedCredential deletes the credential file that was written by
    Save-Credential.ps1.  The operation is permanent and cannot be undone.

    Use -WhatIf to preview which file would be removed without actually deleting it.

.PARAMETER Name
    The short label that was used when the credential was saved (e.g. "CONTOSO-Admin").

.PARAMETER StorePath
    Directory that contains the credential files.
    Defaults to "$env:APPDATA\ps-cred".

.EXAMPLE
    .\Remove-SavedCredential.ps1 -Name "CONTOSO-Admin"

    Permanently removes the credential stored as "CONTOSO-Admin".

.EXAMPLE
    .\Remove-SavedCredential.ps1 -Name "CONTOSO-Admin" -WhatIf

    Shows what would be deleted without actually removing anything.

.NOTES
    Requires Windows PowerShell 5.1 or PowerShell 7+.
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Name,

    [Parameter()]
    [string] $StorePath = (Join-Path $env:APPDATA 'ps-cred')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region --- Remove credential -------------------------------------------------

$filePath = Join-Path $StorePath "$Name.cred"

if (-not (Test-Path -LiteralPath $filePath)) {
    throw "No saved credential found for '$Name'. Expected file: '$filePath'."
}

if ($PSCmdlet.ShouldProcess($filePath, 'Remove saved credential')) {
    Remove-Item -LiteralPath $filePath -Force
    Write-Host "Credential '$Name' removed from '$filePath'." -ForegroundColor Yellow
}

#endregion
