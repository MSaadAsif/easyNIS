[CmdletBinding()]
param([switch]$Doctor)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskConfig = Join-Path $taskRoot '.easynis-local.ps1'
if (Test-Path -LiteralPath $taskConfig) { . $taskConfig }
$taskRscript = $env:EASYNIS_RSCRIPT
if (-not $taskRscript) {
    $taskCommand = Get-Command Rscript -ErrorAction SilentlyContinue
    if (-not $taskCommand) { throw 'Set EASYNIS_RSCRIPT or put Rscript on PATH. See docs/AUTONOMY.md.' }
    $taskRscript = $taskCommand.Source
}
if (-not (Test-Path -LiteralPath $taskRscript)) { throw 'The configured Rscript does not exist.' }
Push-Location $taskRoot
try {
    if ($Doctor) {
        & $taskRscript tools/verify.R --doctor
        if ($LASTEXITCODE -ne 0) { throw 'R development doctor failed.' }
        & git rev-parse --show-toplevel
        if ($LASTEXITCODE -ne 0) { throw 'Git repository is unavailable.' }
        & gh api user --jq .login
        if ($LASTEXITCODE -ne 0) { throw 'GitHub authentication failed.' }
    } else {
        & (Join-Path $PSScriptRoot 'tests/test-merge-gate.ps1')
        & $taskRscript tools/verify.R
        if ($LASTEXITCODE -ne 0) { throw 'Verification failed. Inspect the reported evidence directory.' }
    }
} finally { Pop-Location }
