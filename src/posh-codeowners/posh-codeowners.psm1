#requires -Version 5
using namespace System
using namespace System.Collections.Generic
using namespace System.IO

param
(
)

Set-StrictMode -Version Latest

$DefaultRelativePaths = @(
    'CODEOWNERS',
    '.github/CODEOWNERS',
    '.gitlab/CODEOWNERS'
)


class CodeownerEntry
{
    [string] $Path
    [string] $Expression
    [string[]] $Owners
}

function Read-CodeOwners
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param
    (
        # Specifies a path to one or more locations. Wildcards are permitted.
        [Parameter(Mandatory,
            Position = 0,
            ParameterSetName = "Path",
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            HelpMessage = "Path to one or more locations.")]
        [ValidateNotNullOrEmpty()]
        [SupportsWildcards()]
        [string[]] $Path,

        # Specifies a path to one or more locations. Unlike the Path parameter, the value of the LiteralPath parameter is
        # used exactly as it is typed. No characters are interpreted as wildcards. If the path includes escape characters,
        # enclose it in single quotation marks. Single quotation marks tell Windows PowerShell not to interpret any
        # characters as escape sequences.
        [Parameter(Mandatory,
            Position = 0,
            ParameterSetName = "LiteralPath",
            ValueFromPipelineByPropertyName,
            HelpMessage = "Literal path to one or more locations.")]
        [Alias("PSPath")]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath
    )

    process
    {
        $Items = switch ($PSCmdlet.ParameterSetName)
        {
            'Path' { Get-Item -Path:$Path }
            'LiteralPath' { Get-Item -LiteralPath:$LiteralPath }
        }

        $Items | ForEach-Object {
            switch -regex (($_ | Get-Content) -creplace '(?<!\\)#.*', '') {
                '(?<Path>[\S^#].*?)\s+(?<Owners>(?<Owner>@\w\S*)(?:\s+(?<Owner>@\w\S*))*)'
                {
                    $path = $Matches.Path
                    $owners =  ($Matches.Owners -split '\s+')
                    $expression = switch -regex ($Matches.Path) {
                        '\*' { $_ } # explicit wildcard
                        default { "${_}*" } # implicit trailing wildcard
                    }
                    [CodeownerEntry] @{
                        Path = $path
                        Expression = $expression
                        Owners = $owners
                    }
                }
            }
        }
    }
}

class CodeownerResult
{
    [Alias('PSPath')]
    [string] $Path

    [string[]] $Owners
}

function Get-CodeOwners
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param
    (
        # Specifies a path to one or more locations. Wildcards are permitted.
        [Parameter(Position = 0,
            ParameterSetName = "Path",
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            HelpMessage = "Path to one or more locations.")]
        [ValidateNotNullOrEmpty()]
        [SupportsWildcards()]
        [string[]] $Path,

        # Specifies a path to one or more locations. Unlike the Path parameter, the value of the LiteralPath parameter is
        # used exactly as it is typed. No characters are interpreted as wildcards. If the path includes escape characters,
        # enclose it in single quotation marks. Single quotation marks tell Windows PowerShell not to interpret any
        # characters as escape sequences.
        [Parameter(Mandatory,
            Position = 0,
            ParameterSetName = "LiteralPath",
            ValueFromPipelineByPropertyName,
            HelpMessage = "Literal path to one or more locations.")]
        [Alias("PSPath")]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath
    )

    begin
    {
        $GitRoot = Get-GitDirectory -ErrorAction Stop | Split-Path
        $Entries = Get-ChildItem -LiteralPath:$GitRoot -Depth 2 -Include 'CODEOWNERS' | Read-CodeOwners
        Push-Location $GitRoot
    }

    end
    {
        Pop-Location
    }

    process
    {
        $LiteralPath = switch ($PSCmdlet.ParameterSetName)
        {
            'Path' {
                if (!$Path)
                {
                    return $GitRoot
                }

                $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
            }
            'LiteralPath' { $LiteralPath }
        }

        # We cannot guarantee all paths actually exist at this time, they may be historical.
        $LiteralPath | ForEach-Object {
            $RelativePath = '/' + [IO.Path]::GetRelativePath($GitRoot, $_) -creplace '\\', '/' # normalize to what Git wants.
            return [PSCustomObject] @{
                Path = $_
                Owners = $Entries | Where-Object { $RelativePath -clike $_.Expression } | ForEach-Object Owners
            }
        }
    }    
}

New-Alias -Name 'codeowners' -Value 'Get-CodeOwners'