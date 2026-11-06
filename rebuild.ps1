param(
    [switch]$SkipTests = $false,
    [switch]$Install = $false,
    [string]$DeviceSerial = ""
)

$params = @{}
if ($SkipTests) { $params['SkipTests'] = $true }
if ($Install) { $params['Install'] = $true }
if ($DeviceSerial) { $params['DeviceSerial'] = $DeviceSerial }

& "$PSScriptRoot\scripts\rebuild.ps1" @params

