#requires -Version 5
using namespace System
using namespace System.Collections.Generic
using namespace System.IO
using namespace System.Text

param
(
)

Set-StrictMode -Version Latest

class CodeownerEntry
{
    [string] $Expression
    [string[]] $Owners

    hidden [Regex] $Pattern

    CodeownerEntry([string] $Expression, [string[]] $Owners)
    {
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
            switch -regex (($_ | Get-Content) -creplace '(?<!\\)#.*', '') {
                '(?<Expression>[\S^#].*?)\s+(?<Owners>(?<Owner>@\w\S*)(?:\s+(?<Owner>@\w\S*))*)'
                {
                    $expression = $Matches.Expression
                    $owners =  ($Matches.Owners -split '\s+')

                    [CodeownerEntry]::new($expression, $owners)
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
            return [PSCustomObject] @{
                Path = $_
                Owners = $Entries | Where-Object { $_.IsMatch($RelativePath) } | ForEach-Object Owners
            }
        }
    }    
}

New-Alias -Name 'codeowners' -Value 'Get-CodeOwners'