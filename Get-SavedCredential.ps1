<#
.SYNOPSIS
    Retrieves a saved credential from disk and returns it as a PSCredential object.

.DESCRIPTION
    Get-SavedCredential reads a credential file that was previously written by
    Save-Credential.ps1, decrypts the stored password with the Windows Data Protection
    API (DPAPI) via ConvertTo-SecureString, and returns a ready-to-use PSCredential
    object.

    Because DPAPI encryption is scoped to the current Windows user account and machine,
    the credential can only be retrieved by the same user that saved it, on the same
    machine.

.PARAMETER Name
    The short label that was used when the credential was saved with Save-Credential.ps1
    (e.g. "CONTOSO-Admin").

.PARAMETER StorePath
    Directory that contains the credential files.
    Defaults to "$env:APPDATA\ps-cred".

.OUTPUTS
    System.Management.Automation.PSCredential

.EXAMPLE
    $cred = .\Get-SavedCredential.ps1 -Name "CONTOSO-Admin"
    .\Start-RunAs.ps1 -Credential $cred

    Retrieves the saved credential and passes it directly to Start-RunAs.ps1.

.EXAMPLE
    .\Get-SavedCredential.ps1 -Name "CONTOSO-Admin" | Select-Object -ExpandProperty UserName

    Retrieves the saved credential and displays the stored user name.

.NOTES
    Uses Windows Data Protection API (DPAPI) via ConvertTo-SecureString.
    The credential can only be decrypted by the same Windows user on the same machine.
    Requires Windows PowerShell 5.1 or PowerShell 7+.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Name,

    [Parameter()]
    [string] $StorePath = (Join-Path $env:APPDATA 'ps-cred')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region --- Load and decrypt --------------------------------------------------

$filePath = Join-Path $StorePath "$Name.cred"

if (-not (Test-Path -LiteralPath $filePath)) {
    throw "No saved credential found for '$Name'. Expected file: '$filePath'."
}

$credData = Get-Content -LiteralPath $filePath -Raw | ConvertFrom-Json

if (-not $credData.UserName -or -not $credData.EncryptedPassword) {
    throw "The credential file '$filePath' is missing required fields (UserName, EncryptedPassword)."
}

$securePassword = $credData.EncryptedPassword | ConvertTo-SecureString

$credential = [System.Management.Automation.PSCredential]::new(
    $credData.UserName,
    $securePassword
)

#endregion

return $credential
