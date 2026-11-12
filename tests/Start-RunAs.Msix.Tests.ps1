$ErrorActionPreference = 'Stop'

$originalProgramFiles = $env:ProgramFiles
$originalLocalAppData = $env:LOCALAPPDATA
$originalSystemRoot = $env:SystemRoot

try {
    $env:ProgramFiles = Join-Path ([System.IO.Path]::GetTempPath()) 'PsRunAsProgramFiles'
    $env:LOCALAPPDATA = Join-Path ([System.IO.Path]::GetTempPath()) 'PsRunAsLocalAppData'
    $env:SystemRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'PsRunAsSystemRoot'
    $global:PsRunAsMsixTestState = @{
        HostPath = [System.IO.Path]::Combine($env:ProgramFiles, 'WindowsApps') + '\pwsh.exe'
        FallbackPath = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
        FallbackExists = $true
        StartedPath = $null
    }

    function Get-Process {
        param ([int] $Id)
        [pscustomobject]@{ Path = $global:PsRunAsMsixTestState.HostPath }
    }

    function Test-Path {
        param ([string] $LiteralPath)
        return ($LiteralPath -eq $global:PsRunAsMsixTestState.HostPath) -or
            ($global:PsRunAsMsixTestState.FallbackExists -and $LiteralPath -eq $global:PsRunAsMsixTestState.FallbackPath)
    }

    function Start-Process {
        [CmdletBinding()]
        param (
            [string] $FilePath,
            [string[]] $ArgumentList,
            [System.Management.Automation.PSCredential] $Credential,
            [string] $WorkingDirectory
        )
        $global:PsRunAsMsixTestState.StartedPath = $FilePath
    }

    $credential = [System.Management.Automation.PSCredential]::new(
        'test-user', (ConvertTo-SecureString 'test-password' -AsPlainText -Force))
    $scriptPath = Join-Path $PSScriptRoot '..\Start-RunAs.ps1'
    $warnings = @(& $scriptPath -Credential $credential 3>&1)

    if ($global:PsRunAsMsixTestState.StartedPath -ne $global:PsRunAsMsixTestState.FallbackPath) {
        throw "Expected fallback '$($global:PsRunAsMsixTestState.FallbackPath)', got '$($global:PsRunAsMsixTestState.StartedPath)'."
    }
    if (-not ($warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -and $_.Message.Contains($global:PsRunAsMsixTestState.HostPath) })) {
        throw 'Expected a warning containing the packaged host path.'
    }

    $global:PsRunAsMsixTestState.FallbackExists = $false
    $global:PsRunAsMsixTestState.StartedPath = $null
    $failure = $null
    try {
        & $scriptPath -Credential $credential 3>$null
    } catch {
        $failure = $_
    }
    if (-not $failure -or $failure.Exception.Message -notlike '*No traditionally-installed PowerShell executable was found*') {
        throw "Expected the missing-fallback error; got '$failure'."
    }
    if ($global:PsRunAsMsixTestState.StartedPath) {
        throw 'Start-Process should not be called when no fallback exists.'
    }
} finally {
    $env:ProgramFiles = $originalProgramFiles
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:SystemRoot = $originalSystemRoot
    Remove-Variable -Name PsRunAsMsixTestState -Scope Global -ErrorAction SilentlyContinue
}
