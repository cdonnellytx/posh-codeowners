#requires -Version 5
using namespace System
using namespace System.Collections.Generic
using namespace System.IO
using namespace System.Text

param
(
)

Set-StrictMode -Version Latest

class FileLocation
{
    [Alias('PSPath')]
    [string] $Path

    # The one-based line number.
    [int] $LineNumber

    FileLocation([string] $Path, [int] $LineNumber)
    {
        $this.Path = $Path
        $this.LineNumber = $LineNumber
    }

    [string] ToString()
    {
        return "{0}:{1}" -f $this.Path, $this.LineNumber
    }
}

class CodeownerEntry
{
    # The expression for the rule.
    [string] $Expression

    # The list of owners for the rule.
    [string[]] $Owners

    # The location in which this rule was found.
    [Alias('PSPath')]
    [FileLocation] $Location

    hidden [Regex] $Pattern

    CodeownerEntry([string] $Path, [int] $LineNumber, [string] $Expression, [string[]] $Owners)
    {
        $this.Location = [FileLocation]::new($Path, $LineNumber)
        $this.Expression = $Expression
        $this.Owners = $Owners

        # Expression to regex
        $buf = ''
        if ($Expression -notlike '/*')
        {
            $buf += '^(?:.*/)?'
        }
        else
        {
            $buf += '^'
        }

        $buf += $Expression -creplace '\*', '[^/]*' # not a directory name
        $this.Pattern = [Regex] $buf
    }

    [string] ToString()
    {
        return "{0} {1}" -f $this.Expression, ($this.Owners -join " ")
    }

    [bool] IsMatch([string] $relativePath)
    {
        return $this.Pattern.IsMatch($relativePath)
    }
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
            $Item = $_
            $_ | Get-Content | Select-String '^\s*(?<Expression>[\S^#].*?)\s+(?<Owners>(?:@\w\S*)(?:\s+(?:@\w\S*))*)' | ForEach-Object {
                $match = $_
                $match.Matches | ForEach-Object {
                    $expression = $_.Groups['Expression'].Value
                    $owners =  $_.Groups['Owners'].Value -csplit '\s+'
                    [CodeownerEntry]::new($Item.FullName, $match.LineNumber, $expression, $owners)
                }
            }
        }
    }
}

class CodeownerResult
{
    [Alias('PSPath')]
    [string] $Path

    # All codeowner entries.
    [CodeownerEntry[]] $Entries

    CodeownerResult()
    {
    }

    CodeownerResult([string] $Path, [CodeownerEntry[]] $Entries)
    {
        $this.Path = $Path
        $this.Entries = $Entries
    }
}

function Get-CodeOwners
{
    <#
    .SYNOPSIS
    Gets the codeowners for the given path.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([CodeownerResult])]
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
        [string[]] $Path = '.',

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
        [string[]] $LiteralPath,

        # Gets the items in the specified locations and in all child items of the locations.
        [switch] $Recurse,

        # Determines the number of subdirectory levels that are included in the recursion and displays the contents.  Implies `-Recurse`.
        [uint] $Depth
    )

    begin
    {
        $GitRoot = Get-GitDirectory -ErrorAction Stop | Split-Path
        $Entries = Get-ChildItem -LiteralPath:$GitRoot -Depth 2 -Include 'CODEOWNERS' | Read-CodeOwners
        Push-Location $GitRoot

        $RecurseSplat = $PSBoundParameters.ContainsKey('Depth') ? @{ Depth = $Depth } : $Recurse ? @{ Recurse = $Recurse } : $null
    }

    end
    {
        Pop-Location
    }

    process
    {
        [ref] $dummy = $null
        [string[]] $ResolvedPaths = switch ($PSCmdlet.ParameterSetName)
        {
            'Path' {
                # We cannot guarantee all paths actually exist at this time, they may be historical.
                foreach ($value in $Path)
                {
                    try
                    {
                        $PSCmdlet.GetResolvedProviderPathFromPSPath($Value, $dummy)
                    }
                    catch
                    {
                        $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Value)
                    }
                }
            }
            'LiteralPath' {
                foreach ($value in $LiteralPath)
                {
                    try
                    {
                        $PSCmdlet.GetResolvedProviderPathFromPSPath($Value, $dummy)
                    }
                    catch
                    {
                        $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Value)
                    }
                }
            }
        }

        if ($RecurseSplat)
        {
            $Splat = $ResolvedPaths ? $RecurseSplat + @{ LiteralPath = $ResolvedPaths } : $RecurseSplat
            $ResolvedPaths = Get-ChildItem @Splat | Select-Object -ExpandProperty FullName
        }

        $ResolvedPaths | ForEach-Object {
            $RelativePath = '/' + [IO.Path]::GetRelativePath($GitRoot, $_) -creplace '\\', '/' # normalize to what Git wants.
            return [CodeownerResult]::new(
                $_,
                ($Entries | Where-Object { $_.IsMatch($RelativePath) })
            )
        }
    }    
}

New-Alias -Name 'codeowners' -Value 'Get-CodeOwners'