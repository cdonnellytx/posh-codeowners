# PSScriptAnalyzerSettings.psd1
# Settings for PSScriptAnalyzer invocation.
#
# For more information on PSScriptAnalyzer settings see:
# https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules-recommendations?view=ps-modules
# https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/readme?view=ps-modules
#
# You can see the predefined PSScriptAnalyzer settings here:
# https://github.com/PowerShell/PSScriptAnalyzer/tree/master/Engine/Settings
@{
    Severity = @('ParseError', 'Error', 'Warning', 'Information')
    ExcludeRules = @(
        # Does not fit.
        'PSUseSingularNouns'
    )
    Rules = @{
        PSUseCompatibleSyntax = @{
            # This turns the rule on (setting it to false will turn it off)
            Enable = $true

            # Simply list the targeted versions of PowerShell here
            TargetVersions = @(
                '5.1',
                '7.2'
            )
        }
    }
}
