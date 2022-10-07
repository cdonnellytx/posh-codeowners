#!/usr/bin/env -S pwsh -NoProfile

[CmdletBinding()]
param
(
    [Parameter(Position = 0, HelpMessage = "The target to run.")]
    [ValidateSet("GitVersion", "Clean", "Build", "Dist")]
    [string] $Target = 'Build',

    [ValidateSet("Debug", "Release")]
    [string] $Configuration = 'Release'
)

Set-StrictMode -Version Latest

$repoRoot = $PSScriptRoot

$buildDir = Join-Path $repoRoot 'build'
$distDir = Join-Path $repoRoot 'dist'
#$srcDir = Join-Path $repoRoot "src"

$repoUrl = $null
$gitVersion = $null

$dotnet = Get-Command -Name 'dotnet' -CommandType Application

function dotnet
{
    Write-Verbose "dotnet $args"
    & $dotnet $args
}

function RestoreDotnetToolStep()
{
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
        Prerelease    = $gitVersion.Prerelease + " "

        ProjectUri    = $repoUrl
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

function DistStep
{
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

function GitVersion
{
    RestoreDotnetToolStep
    GitVersionStep
}

function Clean()
{
    GitVersion
    CleanStep
}

function Build()
{
    Clean
    BuildStep
}

function Dist()
{
    Build
    DistStep
}

#
# Invoke the target
#
if (Get-Command -CommandType Function $Target)
{
    & $Target
}



