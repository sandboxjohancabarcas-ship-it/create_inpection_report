param(
    [ValidateSet("clean", "persistent", "c", "p", "")]
    [string]$Mode = "",
    [switch]$Release
)

$params = @{}
if ($Mode) { $params['Mode'] = $Mode }
if ($Release) { $params['Release'] = $true }

& "$PSScriptRoot\scripts\run_windows.ps1" @params

