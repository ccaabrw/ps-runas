<#
.SYNOPSIS
    Lists saved credentials from the local credential store.

.DESCRIPTION
    Get-SavedCredentialList enumerates credential files written by Save-Credential.ps1.
    By default it returns a simple list of saved credential names.

    Use -Detailed to return objects that include the stored UserName along with
    parsed User and Domain fields.

.PARAMETER StorePath
    Directory that contains credential files.
    Defaults to "$env:APPDATA\ps-cred".

.PARAMETER Detailed
    Returns verbose output with Name, UserName, User, Domain, SavedAt, and Path.

.OUTPUTS
    System.String
    or
    PSCustomObject

.EXAMPLE
    .\Get-SavedCredentialList.ps1

    Returns credential names from the default store.

.EXAMPLE
    .\Get-SavedCredentialList.ps1 -Detailed

    Returns detailed entries with split user/domain values.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string] $StorePath = (Join-Path $env:APPDATA 'ps-cred'),

    [Parameter()]
    [switch] $Detailed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $StorePath)) {
    return
}

$credentialFiles = Get-ChildItem -LiteralPath $StorePath -Filter '*.cred' -File | Sort-Object Name

foreach ($credentialFile in $credentialFiles) {
    $name = $credentialFile.BaseName

    if (-not $Detailed) {
        $name
        continue
    }

    try {
        $credData = Get-Content -LiteralPath $credentialFile.FullName -Raw | ConvertFrom-Json
    }
    catch {
        throw "Unable to read credential file '$($credentialFile.FullName)': $($_.Exception.Message)"
    }

    if (($credData.PSObject.Properties.Name -notcontains 'UserName') -or
        [string]::IsNullOrWhiteSpace([string]$credData.UserName)) {
        throw "Credential file '$($credentialFile.FullName)' has a missing or invalid 'UserName' field."
    }

    $userName = [string]$credData.UserName
    $savedAt = if ($credData.PSObject.Properties.Name -contains 'SavedAt') { $credData.SavedAt } else { $null }
    $user = $null
    $domain = $null

    if ($userName.Contains('\')) {
        $domain, $user = $userName.Split('\', 2)
    }
    elseif ($userName.Contains('@')) {
        $user, $domain = $userName.Split('@', 2)
    }
    else {
        $user = $userName
    }

    [pscustomobject]@{
        Name     = $name
        UserName = $userName
        User     = $user
        Domain   = $domain
        SavedAt  = $savedAt
        Path     = $credentialFile.FullName
    }
}
