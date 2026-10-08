[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$PullRequest,
    [Parameter(Mandatory = $true)][string]$ReviewFile,
    [switch]$Merge
)
$ErrorActionPreference = 'Stop'
function Invoke-TaskGhJson([string[]]$Arguments) {
    $taskJson = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'GitHub query failed.' }
    return ($taskJson | ConvertFrom-Json)
}
$taskRepo = 'MSaadAsif/easyNIS'
$taskPr = Invoke-TaskGhJson @('pr', 'view', "$PullRequest", '--repo', $taskRepo, '--json', 'state,isDraft,headRefOid,baseRefOid,baseRefName,mergeStateStatus,statusCheckRollup,reviewDecision')
if ($taskPr.state -ne 'OPEN' -or $taskPr.isDraft -or $taskPr.baseRefName -ne 'main') { throw 'Require an open, ready PR against main.' }
if ($taskPr.mergeStateStatus -ne 'CLEAN' -or $taskPr.reviewDecision -eq 'CHANGES_REQUESTED') { throw 'The PR is blocked, outdated, conflicting, or has changes requested.' }
$taskRequired = @('windows-latest (R release)', 'macos-latest (R release)', 'ubuntu-latest (R release)', 'ubuntu-latest (R oldrel-1)', 'ubuntu-latest (R devel)')
$taskProtection = Invoke-TaskGhJson @('api', "repos/$taskRepo/branches/main/protection")
if (-not $taskProtection.enforce_admins.enabled -or -not $taskProtection.required_status_checks.strict) { throw 'Require strict main protection, including admins.' }
$taskProtectedNames = @($taskProtection.required_status_checks.checks | ForEach-Object { $_.context })
foreach ($taskName in $taskRequired) {
    if ($taskName -notin $taskProtectedNames) { throw "Protection is missing $taskName." }
    $taskChecks = @($taskPr.statusCheckRollup | Where-Object { $_.name -eq $taskName })
    if ($taskChecks.Count -ne 1 -or $taskChecks[0].status -ne 'COMPLETED' -or $taskChecks[0].conclusion -ne 'SUCCESS') { throw "Require a unique successful current check: $taskName." }
}
foreach ($taskCheck in $taskPr.statusCheckRollup) {
    if ($taskCheck.__typename -eq 'CheckRun') {
        if ($taskCheck.status -ne 'COMPLETED' -or $taskCheck.conclusion -ne 'SUCCESS') { throw 'A current PR check is pending or unsuccessful.' }
    } elseif ($taskCheck.state -ne 'SUCCESS') { throw 'A current commit status is pending or unsuccessful.' }
}
$taskReview = Get-Content -LiteralPath $ReviewFile -Raw | ConvertFrom-Json
if ($taskReview.head_sha -cne $taskPr.headRefOid -or $taskReview.base_sha -cne $taskPr.baseRefOid -or
    $taskReview.verdict -cne 'VERIFIED' -or $taskReview.independent -isnot [bool] -or $taskReview.independent -ne $true -or
    $null -eq $taskReview.blocking_findings -or $taskReview.blocking_findings -ne 0 -or
    [string]::IsNullOrWhiteSpace($taskReview.reviewer) -or [string]::IsNullOrWhiteSpace($taskReview.report_file) -or
    [string]::IsNullOrWhiteSpace($taskReview.verification_dir)) {
    throw 'Require independent VERIFIED review with no blockers for the current head and base.'
}
if (-not (Test-Path -LiteralPath $taskReview.report_file -PathType Leaf) -or
    [string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $taskReview.report_file -Raw))) {
    throw 'The saved independent review report is missing or empty.'
}
$taskSummary = Join-Path $taskReview.verification_dir 'summary.txt'
$taskVerifiedHead = Join-Path $taskReview.verification_dir 'head.txt'
$taskVerifiedTree = Join-Path $taskReview.verification_dir 'working-tree.txt'
if (-not (Test-Path -LiteralPath $taskSummary -PathType Leaf) -or
    -not (Test-Path -LiteralPath $taskVerifiedHead -PathType Leaf) -or
    -not (Test-Path -LiteralPath $taskVerifiedTree -PathType Leaf)) { throw 'Local verification evidence is incomplete.' }
if (-not [string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $taskVerifiedTree -Raw))) {
    throw 'Final local verification must have run from clean committed source.'
}
if ((Get-Content -LiteralPath $taskSummary -TotalCount 1) -cne 'VERIFIED' -or
    (Get-Content -LiteralPath $taskVerifiedHead -Raw).Trim() -cne $taskPr.headRefOid) {
    throw 'Local verification did not pass for the current committed head.'
}
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskOrigin = & git -C $taskRoot remote get-url origin
if ($LASTEXITCODE -ne 0 -or $taskOrigin -notin @('https://github.com/MSaadAsif/easyNIS.git', 'git@github.com:MSaadAsif/easyNIS.git')) { throw 'Unexpected repository origin.' }
$taskHead = & git -C $taskRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $taskHead -cne $taskPr.headRefOid) { throw 'Local HEAD must match the reviewed PR head.' }
$taskStatus = & git -C $taskRoot status --porcelain
if ($LASTEXITCODE -ne 0 -or $taskStatus) { throw 'Use a clean checkout at the reviewed head; preserve unfinished work elsewhere.' }
Write-Output "VERIFIED: PR #$PullRequest at $($taskPr.headRefOid). Independent review and all CI checks passed."
if ($Merge) {
    & gh pr merge "$PullRequest" --repo $taskRepo --merge --match-head-commit $taskPr.headRefOid
    if ($LASTEXITCODE -ne 0) { throw 'Protected merge failed; refresh head/base, review and checks.' }
} else { Write-Output 'Read-only check complete. Add -Merge to execute the authorized merge.' }
