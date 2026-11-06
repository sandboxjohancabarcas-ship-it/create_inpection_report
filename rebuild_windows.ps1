param(
    [switch]$SkipTests = $false
)

$params = @{}
if ($SkipTests) { $params['SkipTests'] = $true }

& "$PSScriptRoot\scripts\rebuild_windows.ps1" @params

