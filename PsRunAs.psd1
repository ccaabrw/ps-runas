@{
    RootModule        = 'PsRunAs.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '2e250088-5598-4487-bf8a-c1e7c950e6f1'
    Author            = 'ps-runas contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) ps-runas contributors. All rights reserved.'
    Description       = 'PowerShell module for starting run-as sessions and managing saved credentials.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Start-RunAs',
        'Save-Credential',
        'Get-SavedCredential',
        'Remove-SavedCredential'
    )
    CmdletsToExport   = @()
    VariablesToExport = '*'
    AliasesToExport   = @()
}
