@{

    # Script module or binary module file associated with this manifest.
    RootModule = 'posh-codeowners.psm1'

    # Version number of this module.
    ModuleVersion = '0.0.3'

    # ID used to uniquely identify this module
    GUID = 'a8b24b1a-579e-4638-9ed1-c78c1abfca4d'

    # Author of this module
    Author = 'Chris R. Donnelly'

    # Company or vendor of this module
    CompanyName = ''

    # Copyright statement for this module
    Copyright = '(c) Chris R. Donnelly. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'CODEOWNERS CLI tool'

    # Minimum version of the Windows PowerShell engine required by this module
    # PowerShellVersion = ''

    # Name of the Windows PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the Windows PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module
    # DotNetFrameworkVersion = ''

    # Minimum version of the common language runtime (CLR) required by this module
    # CLRVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        'posh-git'
    )

    # Assemblies that must be loaded prior to importin  g this module
    RequiredAssemblies = @()


    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess = @(
       # 'posh-codeowners.types.ps1xml'
    )

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess = @(
     #   'posh-codeowners.format.ps1xml'
    )

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    NestedModules      = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Get-CodeOwners', 'Read-CodeOwners'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @('codeowners')

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    FileList = @(
        'posh-codeowners.psm1'
    )

    PrivateData = @{
        PSData = @{
        }
    }
}