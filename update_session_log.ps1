# utility script to append session notes to PROJECT_CONTEXT.md
param (
    [Parameter(Mandatory=$true)]
    [string]$Summary
)

$contextFile = Join-Path (Get-Location) "PROJECT_CONTEXT.md"

if (-not (Test-Path $contextFile)) {
    Write-Error "PROJECT_CONTEXT.md not found in the root directory."
    exit
}

$date = Get-Date -Format "yyyy-MM-dd HH:mm"
$header = "`n## Session Log: $date`n"
$footer = "`n---`n"

try {
    Add-Content -Path $contextFile -Value "$header$Summary$footer"
    Write-Host "Context updated successfully with session log." -ForegroundColor Green
}
catch {
    Write-Error "Failed to update context file: $_"
}