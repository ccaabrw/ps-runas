Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-PsRunAsScript {
    param (
        [Parameter(Mandatory)]
        [string] $ScriptName,

        [Parameter()]
        [hashtable] $BoundParameters = @{}
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Unable to locate script '$ScriptName' in module path '$PSScriptRoot'."
    }

    & $scriptPath @BoundParameters
}

function Start-RunAs {
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
        [switch] $Diagnostic,

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

    Invoke-PsRunAsScript -ScriptName 'Start-RunAs.ps1' -BoundParameters $PSBoundParameters
}

function Save-Credential {
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

    Invoke-PsRunAsScript -ScriptName 'Save-Credential.ps1' -BoundParameters $PSBoundParameters
}

function Get-SavedCredential {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCredential])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [string] $StorePath = (Join-Path $env:APPDATA 'ps-cred')
    )

    Invoke-PsRunAsScript -ScriptName 'Get-SavedCredential.ps1' -BoundParameters $PSBoundParameters
}

function Remove-SavedCredential {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [string] $StorePath = (Join-Path $env:APPDATA 'ps-cred')
    )

    Invoke-PsRunAsScript -ScriptName 'Remove-SavedCredential.ps1' -BoundParameters $PSBoundParameters
}

Export-ModuleMember -Function Start-RunAs, Save-Credential, Get-SavedCredential, Remove-SavedCredential
