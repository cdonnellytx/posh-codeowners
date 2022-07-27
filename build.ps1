#!/usr/bin/env -S pwsh -NoProfile

[CmdletBinding()]
param
(
    [Parameter(Position = 0, HelpMessage = "The target to run.")]
    [ValidateSet("Clean", "Build", "Dist")]
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
    $Script:GitVersion = dotnet minver | Where-Object { $_ } | ForEach-Object {
        $parts = $_ -split '-', 2

        $prerelease = ''
        if ($parts.Length -eq 2)
        {
            $prerelease = $parts[1] -creplace '\.(\d+)$', { ([int] $_.Groups[1].Value).ToString('0000') } -creplace '[^A-Za-z0-9]', ''
        }

        [PSCustomObject] @{
            Version = $_
            ModuleVersion = $parts[0]
            Prerelease = $prerelease
        }
    }

    Write-Verbose "GitVersion: $($Script:GitVersion | ConvertTo-Json)"

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

        # Pre3 only works with alphanumerics.
        # MSCRAP: Additionally, Prerelease="" is ignored, Prerelease=" " is treated like "" SHOULD be.
        # Fortunately it trims whitespace so we don't have to be complicated about it, just add a space at the end.
        Prerelease    = $gitVersion.Prerelease + " "

        ProjectUri    = $repoUrl
    }

    Get-ChildItem -LiteralPath $LiteralPath -Include '*.psd1' | ForEach-Object {
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

        # Copy contents to the destination (dist/PSParquet/VERSION/PSParquet.psm1, not dist/PSParquet/VERSION/build/PSParquet.psm1).
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
        # Don't know a way to do this that allows the 32-bit version to work.
        if ($desktopBuildRuntimePath = $buildRuntimePaths | Where-Object Name -eq 'win-x64')
        {
            dotnet publish --no-restore --configuration $Configuration --runtime $desktopBuildRuntimePath.Name --output $distModuleDir $repoRoot
        }
    }
}

function Clean()
{
    RestoreDotnetToolStep
    GitVersionStep
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



