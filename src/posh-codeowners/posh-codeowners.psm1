#requires -Version 7
using namespace System
using namespace System.Collections.Generic
using namespace System.IO
using namespace System.Text

param
(
)

Set-StrictMode -Version 3.0

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

# Have to do this because of the way PowerShell and .NET in general handle the path separator, particularly on Windows.
function EnsureEndingDirectorySeparator([string] $value)
{
    if ($value -and $value.Length -gt 0 -and $value[$value.Length - 1] -ne $sep)
    {
        return $value + $sep
    }

    return $value
}

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
    $result = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path[0])
    for ($i = 1; $result -and $i -lt $path.Count; $i++)
    {
        $item = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path[$i])

        for ($s = $result; $s; $s = [IO.Path]::GetDirectoryName($s))
        {
            Write-Warning "[$i] $(ConvertTo-Json $item) CMP $(ConvertTo-Json $s)"
            if ($item -eq $s)
            {
                Write-Warning "[$i] $(ConvertTo-Json $item) -eq $(ConvertTo-Json $s) => $(ConvertTo-Json $s)"
                break <#inner#>
            }

            if ($item -like "${s}*" -and ($item[$s.Length] -eq $sep -or $s[-1] -eq $sep))
            {
                Write-Warning "[$i] $(ConvertTo-Json $item) -like $(ConvertTo-Json "${s}*") => $(ConvertTo-Json $s)"
                break <#inner#>
            }

            if ($s -like "${item}*" -and $s[$item.Length] -eq $sep)
            {
                Write-Warning "[$i] $(ConvertTo-Json $s) -like $(ConvertTo-Json "${item}*") => $(ConvertTo-Json $s)"
                $s = $item
                break <#inner#>
            }

            Write-Warning "[$i] go up one ($s)"
        }

        Write-Warning "[$i] $(ConvertTo-Json $path[0..$i]) => $(ConvertTo-Json $s)"
        $result = $s
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
        [FileSystemInfo] $Item
    )

    if ($Env:GIT_DIR)
    {
        Write-Debug "GitRoot: GIT_DIR is set"
        return $Env:GIT_DIR -creplace '[\\/]', [Path]::DirectorySeparatorChar
    }

    $ItemDir = if ($Item -is [DirectoryInfo]) { $Item }
    elseif ($Item -is [FileInfo]) { $Item.Directory }
    else
    {
        Write-Error "Unsupported FileSystemInfo type: $($Item.GetType().FullName)"
        return
    }

    for ($d = $ItemDir; $d; $d = $d.Parent)
    {
        $git = $d.GetFileSystemInfos('.git')
        if ($git.Count -gt 0)
        {
            Write-Debug "GitRoot: ${Path} => ${$git[0].FullName}"
            return $git[0].FullName
        }
    }

    # No common path located.
    Write-Error "Find-GitRoot: Could not find root for ${Item}"
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
        $RecurseSplat = $PSBoundParameters.ContainsKey('Depth') ? @{ Depth = $Depth } : $Recurse ? @{ Recurse = $Recurse } : $null

        $EntriesCache = @{}

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

        $ResolvedPaths | Get-Item | ForEach-Object {
            if ($RecurseSplat)
            {
                $Splat = $RecurseSplat + @{ LiteralPath = $_.FullName }
                Get-ChildItem @Splat
            }
            else
            {
                $_
            }
        } | ForEach-Object {
            $GitRoot = Find-GitRoot $_
            if (!$GitRoot)
            {
                return
            }


            $Entries = Read-CodeOwnersForGitRoot -Path:$GitRoot

            $RelativePath = '/' + [IO.Path]::GetRelativePath($GitRoot, $_.FullName) -creplace '\\', '/' # normalize to what Git wants.
            return [CodeownerResult]::new(
                $_,
                ($Entries | Where-Object { $_.IsMatch($RelativePath) })
            )
        }
    }
}

New-Alias -Name 'codeowners' -Value 'Get-CodeOwners'
