[CmdletBinding()]
param
(
    [Parameter(Position = 0, HelpMessage = "The target to run.")]
    [ValidateSet("Clean", "Build", "Dist")]
    [string] $Target = 'Build'
)

$reporoot = $PSScriptRoot

$buildDir = Join-Path $reporoot 'build'
$distDir = Join-Path $reporoot 'dist'
$srcDir = Join-Path $reporoot "src"

$DistExcludes = @(
    # never include these
    '*.deps.json',
    # only include these if nontrival
    '*.pdb', '*.dll'
)

function CleanStep()
{
    Get-Item -LiteralPath $buildDir, $distDir -ErrorAction Ignore | Remove-Item -Recurse

    Push-Location -Path $srcDir
    try
    {
        dotnet clean
    }
    finally
    {
        Pop-Location
    }
}

function BuildStep()
{
    New-Item -ItemType Directory -Path $buildDir | Out-Null
    Push-Location -Path $srcDir
    try
    {
        dotnet build --configuration release --output $buildDir
    }
    finally
    {
        Pop-Location
    }
}

function DistStep
{
    Get-ChildItem -LiteralPath $buildDir -Include '*.psd1' | ForEach-Object {
        $item = $_
        $moduleName = $item.BaseName
        $dest = Join-Path $distDir $moduleName

        $module = $item | Get-Content -Raw | Invoke-Expression
        if ($module.ModuleVersion)
        {
            $dest = Join-Path $dest $module.ModuleVersion
        }

        # Copy contents to the destination (dist/PSFoo/VERSION/PSFoo.psm1, not dist/PSFoo/VERSION/build/PSFoo.psm1).
        Copy-Item -LiteralPath $buildDir -Destination $dest -Recurse -Container:$false -Exclude $DistExcludes
    }
}



function Clean()
{
    CleanStep
}

function Build()
{
    CleanStep
    BuildStep
}

function Dist()
{
    CleanStep
    BuildStep
    DistStep
}

#
# Invoke the target
#
if (Get-Command -CommandType Function $Target)
{
    & $Target
}



