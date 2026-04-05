<#
.SYNOPSIS
    Saves a credential securely to disk using a DPAPI-encrypted SecureString.

.DESCRIPTION
    Save-Credential prompts for (or accepts) a PSCredential and writes it to a local
    credential store.  The password is encrypted with the Windows Data Protection API
    (DPAPI) via ConvertFrom-SecureString: only the same Windows user account on the
    same machine can decrypt the stored credential.

    The credential is written as a JSON file whose name is derived from the -Name
    parameter.  Use Get-SavedCredential.ps1 to retrieve it and Remove-SavedCredential.ps1
    to delete it.

.PARAMETER Name
    A short label that identifies the stored credential (e.g. "CONTOSO-Admin").
    The file is saved as <Name>.cred inside the credential store directory.

.PARAMETER Credential
    A pre-built PSCredential object.  When omitted, Get-Credential prompts interactively.
    Mutually exclusive with -UserName.

.PARAMETER UserName
    Pre-fills the user name field of the interactive credential prompt.
    Ignored when -Credential is provided.

.PARAMETER StorePath
    Directory where the credential file is written.
    Defaults to "$env:APPDATA\ps-cred".

.EXAMPLE
    .\Save-Credential.ps1 -Name "CONTOSO-Admin" -UserName "CONTOSO\AdminUser"

    Prompts for the password and saves the credential under the name "CONTOSO-Admin".

.EXAMPLE
    $cred = Get-Credential -UserName "CONTOSO\AdminUser" -Message "Enter admin credentials"
    .\Save-Credential.ps1 -Name "CONTOSO-Admin" -Credential $cred

    Saves a pre-built credential without a second interactive prompt.

.NOTES
    Uses Windows Data Protection API (DPAPI) via ConvertFrom-SecureString.
    The saved credential can only be decrypted by the same Windows user on the same machine.
    Requires Windows PowerShell 5.1 or PowerShell 7+.
#>

[CmdletBinding(DefaultParameterSetName = 'ByUserName')]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Name,

    [Parameter(ParameterSetName = 'ByCredential', Mandatory)]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter(ParameterSetName = 'ByUserName')]
    [string] $UserName,

    [Parameter()]
    [string] $StorePath = (Join-Path $env:APPDATA 'ps-cred')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region --- Resolve credential -----------------------------------------------

if ($PSCmdlet.ParameterSetName -eq 'ByUserName') {
    $credParams = @{ Message = "Enter credentials to save as '$Name'" }
    if ($UserName) { $credParams['UserName'] = $UserName }
    $Credential = Get-Credential @credParams
}

if (-not $Credential) {
    throw 'No credential supplied – operation cancelled.'
}

#endregion

#region --- Encrypt and save --------------------------------------------------

if (-not (Test-Path -LiteralPath $StorePath)) {
    New-Item -ItemType Directory -Path $StorePath -Force | Out-Null
}

$encryptedPassword = $Credential.Password | ConvertFrom-SecureString

$credData = [ordered]@{
    UserName          = $Credential.UserName
    EncryptedPassword = $encryptedPassword
    SavedAt           = (Get-Date -Format 'o')
}

$filePath = Join-Path $StorePath "$Name.cred"
$credData | ConvertTo-Json | Set-Content -LiteralPath $filePath -Encoding UTF8

Write-Host "Credential '$Name' saved to '$filePath'." -ForegroundColor Green

#endregion
