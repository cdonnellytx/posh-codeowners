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
    # The target.
    [Parameter(Position = 0, HelpMessage = "The target to run.")]
    [ValidateSet("GitVersion", "Clean", "Build", "Dist", "LocalPublish")]
    [string] $Target = 'Build',

    # The build configuration.
    [Parameter()]
    [ValidateSet("Debug", "Release")]
    [string] $Configuration = 'Release',

    # The publish dir (if LocalPublish is selected)
    [Parameter()]
    [string] $PublishDir
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
        if ($DebugPreference)
        {
            Write-Debug (Test-ModuleManifest $_.FullName | Out-String)
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

function DistStep()
{
    Write-Header $MyInvocation.MyCommand.Name

    Get-ChildItem -Directory -LiteralPath $srcDir | Get-ChildItem -Include '*.psd1' | Test-ModuleManifest | ForEach-Object {
        $item = $_
        $distModuleDir = Join-Path $distDir $item.Name

        # Publish contents to the PublishDir (dist/MODULE/MODULE.psm1).
        dotnet publish --no-restore --no-build --configuration $configuration "--property:PublishDir=${distModuleDir}" $repoRoot
        UpdateModuleManifest $distModuleDir
    }
}

function LocalPublishStep()
{
    Write-Header $MyInvocation.MyCommand.Name
    # .\build.ps1 -Target Dist && cp -Recurse .\dist\posh-projectsystem\ C:\Users\CRDONNELLY\.local\repos\powershell\Modules\

    Get-ChildItem -Directory -LiteralPath $distDir | Copy-Item -Recurse -Destination $PublishDir -Force
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
    # Check that PublishDir is set
    if (!$PublishDir)
    {
        Write-Error -Category InvalidArgument "PublishDir cannot be null or empty." -ErrorAction Stop
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
