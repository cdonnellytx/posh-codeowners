#!/usr/bin/env -S pwsh -NoProfile
#requires -version 7

using namespace System.Diagnostics.CodeAnalysis

[CmdletBinding()]
[SuppressMessageAttribute('PSAvoidUsingPositionalParameters', 'dotnet')]
[SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[SuppressMessageAttribute('PSReviewUnusedParameter', 'Configuration')]
[SuppressMessageAttribute('PSReviewUnusedParameter', 'Destination')]
param
(
    [Parameter(Position = 0, HelpMessage = "The target to run.")]
    [ValidateSet("GitVersion", "Clean", "Build", "Dist", "LocalPublish")]
    [string] $Target = 'Build',

    [ValidateSet("Debug", "Release")]
    [string] $Configuration = 'Release',

    # The destination (if LocalPublish is selected)
    [string] $Destination
)

Set-StrictMode -Version Latest

$repoRoot = $PSScriptRoot

$buildDir = Join-Path $repoRoot 'build'
$distDir = Join-Path $repoRoot 'dist'
#$srcDir = Join-Path $repoRoot "src"


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

    Get-Item -LiteralPath $buildDir, $distDir -ErrorAction Ignore | Remove-Item -Recurse

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
        if ($DebugPreference)
        {
            Write-Debug (Test-ModuleManifest $_.FullName | Out-String)
        }
    }
}

function BuildStep()
{
    Write-Header $MyInvocation.MyCommand.Name

    New-Item -ItemType Directory -Path $buildDir | Out-Null
    Push-Location -Path $repoRoot
    try
    {
        dotnet build --configuration $Configuration --output $buildDir
        UpdateModuleManifest $buildDir
    }
    finally
    {
        Pop-Location
    }
}

function DistStep()
{
    Write-Header $MyInvocation.MyCommand.Name

    $buildRuntimePath = Join-Path $buildDir 'runtimes'
    $buildRuntimePaths = Get-ChildItem -LiteralPath $buildRuntimePath -Directory -ErrorAction Ignore
    Get-ChildItem -LiteralPath $buildDir -Include '*.psd1' | Test-ModuleManifest | ForEach-Object {
        $item = $_
        $distModuleDir = Join-Path $distDir $item.Name

        # Publish contents to the destination (dist/MODULE/MODULE.psm1).
        dotnet publish --no-build --configuration $configuration --output $distModuleDir $repoRoot
        UpdateModuleManifest $distModuleDir

        # MSCRAP: We need to *also* copy runtime files; for some reason `dotnet publish` won't do this by default AND only does one runtime at a time.
        # @see https://vatioz.github.io/programming/poormans-powershell-publish/
        $buildRuntimePaths | ForEach-Object {
            $runtime = $_.Name
            $distModuleRuntimeDir = Join-Path $distModuleDir $runtime
            dotnet publish --no-restore --configuration $configuration --runtime $runtime --output $distModuleRuntimeDir $repoRoot
        }

        # MSCRAP: For PowerShell Desktop we have to publish the Windows variant in the top directory.
        # Don't know a way to do this that allows other architectures to work.
        if ($desktopBuildRuntimePath = $buildRuntimePaths | Where-Object Name -eq 'win-x64')
        {
            dotnet publish --no-restore --configuration $Configuration --runtime $desktopBuildRuntimePath.Name --output $distModuleDir $repoRoot
        }
    }
}

function LocalPublishStep()
{
    Write-Header $MyInvocation.MyCommand.Name
    # .\build.ps1 -Target Dist && cp -Recurse .\dist\posh-projectsystem\ C:\Users\CRDONNELLY\.local\repos\powershell\Modules\

    Get-ChildItem -Directory -LiteralPath $distDir | Copy-Item -Recurse -Destination $Destination -Force
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
