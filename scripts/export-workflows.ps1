# Export workflows from the LOCAL n8n container to ./n8n-workflows and scan for secrets.
# Run from anywhere: powershell -File scripts\export-workflows.ps1
# Requires the local stack (docker-compose.yml in the project root) to be running.

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$outDir = Join-Path $root 'n8n-workflows'
$secretPatterns = @('gsk_', 'eyJ', 'sb_')

function Invoke-Native {
    param([string]$What, [scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed (exit code $LASTEXITCODE)"
    }
}

Write-Host 'Exporting workflows inside the n8n container...'
Invoke-Native 'n8n export:workflow' {
    docker compose exec -T n8n sh -c 'rm -rf /tmp/wf && mkdir -p /tmp/wf && n8n export:workflow --backup --output=/tmp/wf/'
}

if (Test-Path $outDir) {
    Remove-Item -Recurse -Force $outDir
}
New-Item -ItemType Directory -Path $outDir | Out-Null

Write-Host 'Copying export to .\n8n-workflows ...'
Invoke-Native 'docker compose cp' {
    docker compose cp n8n:/tmp/wf/. ./n8n-workflows
}

$files = @(Get-ChildItem -Path $outDir -Filter *.json -Recurse)
Write-Host ('Exported {0} workflow file(s).' -f $files.Count)

# Report file and line only, never the matched text, so secrets are not echoed.
$hits = @()
foreach ($file in $files) {
    foreach ($pattern in $secretPatterns) {
        $found = Select-String -Path $file.FullName -Pattern $pattern -SimpleMatch
        foreach ($m in $found) {
            $hits += ('{0}:{1} matches {2}' -f $file.Name, $m.LineNumber, $pattern)
        }
    }
}

if ($hits.Count -gt 0) {
    Write-Host ''
    Write-Host 'SECRET SCAN FAILED - possible keys found in exported workflows:' -ForegroundColor Red
    $hits | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host 'Do NOT commit .\n8n-workflows. Move the keys into n8n credentials and re-export.' -ForegroundColor Red
    exit 1
}

Write-Host 'Secret scan passed (no gsk_, eyJ or sb_ found).' -ForegroundColor Green
