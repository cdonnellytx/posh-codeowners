@{
    RootModule = 'posh-codeowners.psm1'
    ModuleVersion = '0.0.0'
    GUID = 'a8b24b1a-579e-4638-9ed1-c78c1abfca4d'

    Author = 'Chris R. Donnelly'
    Copyright = '(c) Chris R. Donnelly. All rights reserved.'
    Description = 'CODEOWNERS CLI tool'

    PowerShellVersion = '7.0'
    ProcessorArchitecture = 'None'

    RequiredModules = @()

    RequiredAssemblies = @(
        'posh-codeowners.dll'
    )

    FormatsToProcess = @('posh-codeowners.format.ps1xml')
    TypesToProcess = @('posh-codeowners.types.ps1xml')

    FunctionsToExport = @(
        'Find-CodeOwnersFile',
        'Get-CodeOwners',
        'Read-CodeOwners'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @('codeowners')
    FileList = @(
        'posh-codeowners.psm1'
    )

    PrivateData = @{
        PSData = @{
            Prerelease = 'alpha'
        }
    }
}

