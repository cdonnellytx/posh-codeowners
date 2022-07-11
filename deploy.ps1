[CmdletBinding(SupportsShouldProcess)]
param
(
	[string] $Source = (Join-Path $PSScriptRoot 'src\ProjectSystem\bin\Debug\netcoreapp2.1')
)

Push-Location $Source
try
{
	Get-ChildItem -Exclude '*.deps.json' | Copy-Item -Destination ~\.local\repos\powershell\Modules\posh-projectsystem -ErrorAction Stop
	Write-Warning "Copied!"
}
finally
{
	Pop-Location
}