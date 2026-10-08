$ErrorActionPreference = 'Stop'
$taskGate = Join-Path (Split-Path -Parent $PSScriptRoot) 'merge-verified.ps1'
$taskReceipt = [System.IO.Path]::GetTempFileName()
$taskReport = [System.IO.Path]::GetTempFileName()
$taskEvidenceDir = Join-Path ([System.IO.Path]::GetTempPath()) ('easynis-gate-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $taskEvidenceDir | Out-Null
$taskNames = @('windows-latest (R release)', 'macos-latest (R release)', 'ubuntu-latest (R release)', 'ubuntu-latest (R oldrel-1)', 'ubuntu-latest (R devel)')
$taskCount = 0
function Reset-TaskFixture {
    $global:taskPrFixture = [pscustomobject]@{
        state = 'OPEN'; isDraft = $false; headRefOid = 'abc123'; baseRefOid = 'def456'
        baseRefName = 'main'; mergeStateStatus = 'CLEAN'; reviewDecision = ''
        statusCheckRollup = @($taskNames | ForEach-Object { [pscustomobject]@{ __typename = 'CheckRun'; name = $_; status = 'COMPLETED'; conclusion = 'SUCCESS' } })
    }
    $global:taskProtectionFixture = [pscustomobject]@{
        enforce_admins = @{enabled = $true}
        required_status_checks = @{strict = $true; checks = @($taskNames | ForEach-Object { @{context = $_; app_id = 15368} })}
    }
    $global:taskReviewFixture = [pscustomobject]@{ head_sha = 'abc123'; base_sha = 'def456'; verdict = 'VERIFIED'; reviewer = 'independent-test-agent'; independent = $true; blocking_findings = 0; report_file = $taskReport; verification_dir = $taskEvidenceDir }
    Set-Content -LiteralPath $taskReport -Value 'Invented independent review fixture.'
    Set-Content -LiteralPath (Join-Path $taskEvidenceDir 'summary.txt') -Value 'VERIFIED'
    Set-Content -LiteralPath (Join-Path $taskEvidenceDir 'head.txt') -Value 'abc123'
    Set-Content -LiteralPath (Join-Path $taskEvidenceDir 'working-tree.txt') -Value ''
    $global:taskGitHead = 'abc123'
    $global:taskGitStatus = $null
    $global:taskGitOrigin = 'https://github.com/MSaadAsif/easyNIS.git'
    $global:taskMergeCalls = @()
}
function global:gh {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'pr' -and $args[1] -eq 'view') { $global:taskPrFixture | ConvertTo-Json -Depth 8 }
    elseif ($args[0] -eq 'api') { $global:taskProtectionFixture | ConvertTo-Json -Depth 8 }
    elseif ($args[0] -eq 'pr' -and $args[1] -eq 'merge') { $global:taskMergeCalls += ,$args }
    else { throw 'Unexpected gh command in isolated gate test.' }
}
function global:git {
    $global:LASTEXITCODE = 0
    if ($args -contains 'get-url') { $global:taskGitOrigin }
    elseif ($args -contains 'rev-parse') { $global:taskGitHead }
    elseif ($args -contains 'status') { $global:taskGitStatus }
    else { throw 'Unexpected git command in isolated gate test.' }
}
function Write-TaskReceipt { $global:taskReviewFixture | ConvertTo-Json | Set-Content -LiteralPath $taskReceipt -Encoding utf8 }
function Test-TaskRejection([string]$Name, [scriptblock]$Mutate) {
    Reset-TaskFixture
    & $Mutate
    Write-TaskReceipt
    $taskRejected = $false
    try { & $taskGate -PullRequest 1 -ReviewFile $taskReceipt -Merge | Out-Null }
    catch { $taskRejected = $true }
    if (-not $taskRejected -or $global:taskMergeCalls.Count -ne 0) { throw "$Name failed to prevent a merge." }
    $script:taskCount++
    Write-Output "PASS: $Name rejects without a merge call."
}
try {
    Reset-TaskFixture
    Write-TaskReceipt
    & $taskGate -PullRequest 1 -ReviewFile $taskReceipt | Out-Null
    if ($global:taskMergeCalls.Count -ne 0) { throw 'Read-only gate performed a merge.' }
    $taskCount++
    & $taskGate -PullRequest 1 -ReviewFile $taskReceipt -Merge | Out-Null
    if ($global:taskMergeCalls.Count -ne 1 -or $global:taskMergeCalls[0] -contains '--admin' -or
        $global:taskMergeCalls[0] -notcontains '--match-head-commit' -or $global:taskMergeCalls[0] -notcontains 'abc123') {
        throw 'Successful gate did not request a protected, head-matched merge.'
    }
    $taskCount++
    Test-TaskRejection 'draft PR' { $global:taskPrFixture.isDraft = $true }
    Test-TaskRejection 'closed PR' { $global:taskPrFixture.state = 'CLOSED' }
    Test-TaskRejection 'wrong base' { $global:taskPrFixture.baseRefName = 'other' }
    Test-TaskRejection 'outdated base' { $global:taskPrFixture.mergeStateStatus = 'BEHIND' }
    Test-TaskRejection 'changes requested' { $global:taskPrFixture.reviewDecision = 'CHANGES_REQUESTED' }
    Test-TaskRejection 'pending CI' { $global:taskPrFixture.statusCheckRollup[0].status = 'IN_PROGRESS' }
    Test-TaskRejection 'failed CI' { $global:taskPrFixture.statusCheckRollup[0].conclusion = 'FAILURE' }
    Test-TaskRejection 'skipped CI' { $global:taskPrFixture.statusCheckRollup[0].conclusion = 'SKIPPED' }
    Test-TaskRejection 'missing CI' { $global:taskPrFixture.statusCheckRollup = @($global:taskPrFixture.statusCheckRollup | Select-Object -Skip 1) }
    Test-TaskRejection 'duplicate CI' { $global:taskPrFixture.statusCheckRollup += $global:taskPrFixture.statusCheckRollup[0] }
    Test-TaskRejection 'extra failed status' { $global:taskPrFixture.statusCheckRollup += [pscustomobject]@{__typename = 'StatusContext'; state = 'FAILURE'} }
    Test-TaskRejection 'admin bypass enabled' { $global:taskProtectionFixture.enforce_admins.enabled = $false }
    Test-TaskRejection 'loose base checks' { $global:taskProtectionFixture.required_status_checks.strict = $false }
    Test-TaskRejection 'missing protected check' { $global:taskProtectionFixture.required_status_checks.checks = @() }
    Test-TaskRejection 'stale reviewed head' { $global:taskReviewFixture.head_sha = 'old' }
    Test-TaskRejection 'stale reviewed base' { $global:taskReviewFixture.base_sha = 'old' }
    Test-TaskRejection 'inconclusive review' { $global:taskReviewFixture.verdict = 'INCONCLUSIVE' }
    Test-TaskRejection 'self review' { $global:taskReviewFixture.independent = $false }
    Test-TaskRejection 'blocking review finding' { $global:taskReviewFixture.blocking_findings = 1 }
    Test-TaskRejection 'missing finding count' { $global:taskReviewFixture.blocking_findings = $null }
    Test-TaskRejection 'missing reviewer' { $global:taskReviewFixture.reviewer = '' }
    Test-TaskRejection 'missing report path' { $global:taskReviewFixture.report_file = '' }
    Test-TaskRejection 'nonexistent report' { $global:taskReviewFixture.report_file = 'nonexistent-review-file.md' }
    Test-TaskRejection 'empty report' { Set-Content -LiteralPath $taskReport -Value '' }
    Test-TaskRejection 'missing verification path' { $global:taskReviewFixture.verification_dir = '' }
    Test-TaskRejection 'missing verification files' { $global:taskReviewFixture.verification_dir = 'nonexistent-verification-directory' }
    Test-TaskRejection 'failed local verification' { Set-Content -LiteralPath (Join-Path $taskEvidenceDir 'summary.txt') -Value 'NOT VERIFIED' }
    Test-TaskRejection 'stale local verification' { Set-Content -LiteralPath (Join-Path $taskEvidenceDir 'head.txt') -Value 'old' }
    Test-TaskRejection 'verification from dirty source' { Set-Content -LiteralPath (Join-Path $taskEvidenceDir 'working-tree.txt') -Value ' M R/years.R' }
    Test-TaskRejection 'missing verification worktree state' { Remove-Item -LiteralPath (Join-Path $taskEvidenceDir 'working-tree.txt') -Force }
    Test-TaskRejection 'string independence claim' { $global:taskReviewFixture.independent = 'true' }
    Test-TaskRejection 'wrong local repository' { $global:taskGitOrigin = 'https://github.com/other/other.git' }
    Test-TaskRejection 'wrong local head' { $global:taskGitHead = 'different' }
    Test-TaskRejection 'unfinished local work' { $global:taskGitStatus = ' M R/cohorts.R' }
    Write-Output "Merge gate passed $taskCount scenarios. All git/gh calls were isolated; no network or real ref writes occurred."
} finally {
    Remove-Item -LiteralPath $taskReceipt -Force
    Remove-Item -LiteralPath $taskReport -Force
    Remove-Item -LiteralPath (Join-Path $taskEvidenceDir 'summary.txt') -Force
    Remove-Item -LiteralPath (Join-Path $taskEvidenceDir 'head.txt') -Force
    Remove-Item -LiteralPath (Join-Path $taskEvidenceDir 'working-tree.txt') -Force
    Remove-Item -LiteralPath $taskEvidenceDir -Force
    Remove-Item Function:\gh, Function:\git
}
