#!/usr/bin/env -S pwsh -NoProfile
#requires -version 7

using namespace System.Diagnostics.CodeAnalysis

[CmdletBinding()]
[SuppressMessageAttribute('PSAvoidUsingPositionalParameters', 'dotnet')]
[SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[SuppressMessageAttribute('PSReviewUnusedParameter', 'Configuration')]
[SuppressMessageAttribute('PSReviewUnusedParameter', 'Destination')]
[SuppressMessageAttribute('PSReviewUnusedParameter', 'LocalPublishDir')]
param
(
    # The target.
    [Parameter(Position = 0, HelpMessage = "The target to run.")]
    [ValidateSet("GitVersion", "Clean", "Build", "Dist", "LocalPublish")]
    [string] $Target = 'Build',

    # The build configuration.
    [Parameter()]
    [ValidateSet("Debug", "Release")]
    [string] $Configuration = 'Release',

    # The local publish dir (if LocalPublish is selected).
    # Ideally this should be an entry in `PSModulePath`.
    [Parameter()]
    [string] $LocalPublishDir
)

Set-StrictMode -Version Latest

$repoRoot = $PSScriptRoot

$distDir = Join-Path $repoRoot 'dist'
$srcDir = Join-Path $repoRoot 'src'


$repoUrl = $null
$gitVersion = $null

$dotnet = Get-Command -Name 'dotnet' -CommandType Application


<#
.SYNOPSIS
Wrapper for dotnet command.
#>
function dotnet
{
    Write-Verbose "dotnet $args"
    & $dotnet $args
}

function Write-Header([string] $Name)
{
    Write-Host -ForegroundColor White -Object ("`n" + $Name + "`n" + ("=" * $Name.Length) + "`n")
}

function RestoreDotnetToolStep()
{
    Write-Header $MyInvocation.MyCommand.Name

    Push-Location -Path $repoRoot
    try
    {
        dotnet tool restore
    }
    finally
    {
        Pop-Location
    }
}

function GitVersionStep()
{
    Write-Header $MyInvocation.MyCommand.Name

    # As PowerShell Prerelease is very particular (alphanumeric ONLY), we ignore height.
    $Script:GitVersion = dotnet minver --verbosity warn | Where-Object { $_ } | ForEach-Object {
        $parts = $_ -split '-', 2

        $prerelease = ''
        if ($parts.Length -eq 2)
        {
            $prerelease = $parts[1] `
                -creplace '\.(?<Increment>\d+)(?:\.(?<Height>\d+))?$', { "{0:0000}{1:0000}" -f [int] $_.Groups['Increment'].Value, [int] $_.Groups['Height'].Value } `
                -creplace '[^A-Za-z0-9]', ''
        }

        [PSCustomObject] @{
            Version = $_
            ModuleVersion = $parts[0]
            Prerelease = $prerelease
        }
    }

    Write-Output "GitVersion: $($Script:GitVersion | Out-String)"

    if (!$Script:GitVersion)
    {
        Write-Error "GitVersion not set."
        return
    }

    $Script:RepoUrl = git config --get remote.origin.url
    if (!$Script:RepoUrl)
    {
        Write-Warning "RepoUrl not set."
    }
}

function CleanStep()
{
    Write-Header $MyInvocation.MyCommand.Name

    Get-Item -LiteralPath $distDir -ErrorAction Ignore | Remove-Item -Recurse

    Push-Location -Path $repoRoot
    try
    {
        dotnet clean
    }
    finally
    {
        Pop-Location
    }
}

function UpdateModuleManifest([string[]] $LiteralPath)
{
    # Update the version in the module manifest.
    $manifest = @{
        # ModuleVersion is a System.Version.
        ModuleVersion = $gitVersion.ModuleVersion

        # Prerelease only works with alphanumerics.
        # MSCRAP: Additionally, Prerelease="" is ignored, Prerelease=" " is treated like "" SHOULD be.
        # Fortunately it trims whitespace so we don't have to be complicated about it, just add a space at the end.
        Prerelease = $gitVersion.Prerelease + " "

        ProjectUri = $repoUrl
    }

    Get-ChildItem -LiteralPath $LiteralPath -Include '*.psd1' -Recurse | ForEach-Object {
        Update-ModuleManifest @manifest -Path $_.FullName
        $testResult = Test-ModuleManifest $_.FullName
        if ($DebugPreference)
        {
            Write-Debug ($testResult | Out-String)
        }
    }
}

function BuildStep()
{
    Write-Header $MyInvocation.MyCommand.Name

    Push-Location -Path $repoRoot
    try
    {
        dotnet build --configuration $Configuration
    }
    finally
    {
        Pop-Location
    }
}

<#
.NOTES

dotnet publish structures the native libraries as follows:

PSFileType
└───runtimes
    ├───linux-x64
    │   └───native
    ├───win-x64
    │   └───native
    …

However, at runtime the loader looks for them in

PSFileType
├───linux-x64
│   └───native
├───win-x64
│   └───native
…

So we have to rearrange them.

LATER: would be nice if there were some build property I could override, but there doesn't appear to be one.

.LINK
https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/writing-portable-modules?view=powershell-7.5#dependency-on-native-libraries
#>
function Fix-NativeModules($Path)
{
    # Move runtimes/** to base
    if ($runtimesDir = Get-ChildItem -Path:$Path -Filter 'runtimes')
    {
        $runtimesDir | Get-ChildItem | Move-Item -Destination $Path -PassThru | ForEach-Object {
            # Move <RID>/native/** to <RID>
            if ($native = $_ | Get-ChildItem -Include 'native')
            {
                $native | Get-ChildItem | Move-Item -Destination $_.FullName
                $native | Remove-Item
            }
        }
        $runtimesDir | Remove-Item
    }
}

function DistStep()
{
    Write-Header $MyInvocation.MyCommand.Name

    Get-ChildItem -Directory -LiteralPath $srcDir | Get-ChildItem -Include '*.psd1' | ForEach-Object {
        $item = $_
        $distModuleDir = Join-Path $distDir $item.BaseName

        # Publish contents to the PublishDir property (dist/MODULE).
        dotnet publish --no-restore --no-build --configuration $configuration "--property:PublishDir=${distModuleDir}" $repoRoot

        Fix-NativeModules $distModuleDir
        UpdateModuleManifest $distModuleDir
    }
}

function LocalPublishStep()
{
    Write-Header $MyInvocation.MyCommand.Name

    Get-ChildItem -Directory -LiteralPath $distDir | Copy-Item -Recurse -Destination $LocalPublishDir -Force
}

function Invoke-GitVersion
{
    RestoreDotnetToolStep
    GitVersionStep
}

function Invoke-Clean()
{
    Invoke-GitVersion
    CleanStep
}

function Invoke-Build()
{
    Invoke-Clean
    BuildStep
}

function Invoke-Dist()
{
    Invoke-Build
    DistStep
}

function Invoke-LocalPublish()
{
    # Check that LocalPublishDir is set
    if (!$LocalPublishDir)
    {
        Write-Error -Category InvalidArgument "LocalPublishDir cannot be null or empty." -ErrorAction Stop
        return
    }

    Invoke-Dist
    LocalPublishStep
}

#
# Invoke the target
#
if ($cmd = Get-Command -CommandType Function "Invoke-${Target}")
{
    & $cmd
}
