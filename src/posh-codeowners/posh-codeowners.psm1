#requires -Version 7
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
        $this.Pattern = [CodeownerEntry]::BuildRegex($Expression)
    }

    [string] ToString()
    {
        return "{0} {1}" -f $this.Expression, ($this.Owners -join " ")
    }

    [bool] IsMatch([string] $relativePath)
    {
        return $this.Pattern.IsMatch($relativePath)
    }

    hidden static [Regex] BuildRegex([string] $expression)
    {
        $buf = ''
        if ($Expression -clike '/*')
        {
            # Repo-relative
            $buf += '^'
        }
        else
        {
            # Relative paths
            $buf += '^(?:.*/)?'
        }

        $buf += $Expression -creplace '\*', '[^/]*' # Wildcards should not match a directory name

        # Ensure the end is anchored to string end or a directory.
        if ($Expression -cnotlike '*/')
        {
            $buf += '(\Z|/)'
        }

        return [Regex] $buf
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
            $_ | Get-Content | Select-String '^\s*(?<Expression>[\S-[#]].*?)\s+(?<Owners>(?:@\w\S*)(?:\s+(?:@\w\S*))*)' | ForEach-Object {
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

    [string] ToString()
    {
        return $this.Path
    }
}

$sep = [IO.Path]::DirectorySeparatorChar

<#
.SYNOPSIS
Gets the common path.
#>
function Get-CommonPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path
    )

    # Find the shortest path.
    $result = $Path[0] # | Sort-Object Length | Select-Object -First 1
    for ($i = 1; $result -and $i -lt $path.Count; $i++)
    {
        $item = $path[$i]

        # win condition: `item` == `result` or like `result/*`
        while ($result -and $item -ne $result -and $item -notlike "${result}${sep}*")
        {
             $result = Split-Path -LiteralPath $result
        }
    }

    return $result

}

function Find-GitRoot
{
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path
    )

    if ($Env:GIT_DIR)
    {
        Write-Debug "GitRoot: GIT_DIR is set"
        return $Env:GIT_DIR -creplace '[\\/]', [Path]::DirectorySeparatorChar
    }

    # is there a common git root for these.
    $CommonPath = Get-CommonPath $Path
    while ($CommonPath)
    {
        # Is CommonPath the root of this repo or worktree?
        if (Test-Path -LiteralPath (Join-Path $CommonPath '.git'))
        {
            Write-Debug "GitRoot: ${Path} => ${CommonPath}"
            return $CommonPath
        }
        $CommonPath = Split-Path -LiteralPath $CommonPath
    }

    # No common path located.
    Write-Error "Find-GitRoot: Could not find root for ${ResolvedPaths}"
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
        # $GitRoot = Get-GitDirectory -ErrorAction Stop | Split-Path
        # $Entries = Get-ChildItem -LiteralPath:$GitRoot -Depth 2 -Include 'CODEOWNERS' | Read-CodeOwners
        #Push-Location $GitRoot
        $RecurseSplat = $PSBoundParameters.ContainsKey('Depth') ? @{ Depth = $Depth } : $Recurse ? @{ Recurse = $Recurse } : $null

        $EntriesCache = @{
        }

        function Read-CodeOwnersForGitRoot([string] $Path)
        {
            if (!$EntriesCache.ContainsKey($Path))
            {
                Write-Debug "Read-CodeOwnersForGitRoot: CACHE MISS ${Path}"
                $EntriesCache[$Path] = Get-ChildItem -LiteralPath:$Path -Depth 2 -Include 'CODEOWNERS' | Read-CodeOwners
                if ($DebugPreference) { Write-Debug "=> $($EntriesCache[$Path] | Out-String)" }
            }

            return $EntriesCache[$Path]
        }
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

        $GitRoot = Find-GitRoot $ResolvedPaths
        if (!$GitRoot)
        {
            return
        }

        if ($RecurseSplat)
        {
            $Splat = $ResolvedPaths ? $RecurseSplat + @{ LiteralPath = $ResolvedPaths } : $RecurseSplat
            $ResolvedPaths = Get-ChildItem @Splat | Select-Object -ExpandProperty FullName
        }

        if ($ResolvedPaths)
        {
            $Entries = Read-CodeOwnersForGitRoot -Path:$GitRoot

            $ResolvedPaths | ForEach-Object {
                $RelativePath = '/' + [IO.Path]::GetRelativePath($GitRoot, $_) -creplace '\\', '/' # normalize to what Git wants.
                return [CodeownerResult]::new(
                    $_,
                    ($Entries | Where-Object { $_.IsMatch($RelativePath) })
                )
            }
        }
    }
}

New-Alias -Name 'codeowners' -Value 'Get-CodeOwners'
