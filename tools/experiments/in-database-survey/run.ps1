#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $NisRoot,
    [string] $Rscript = 'Rscript',
    [ValidateRange(3, 20)]
    [int] $Repeats = 3,
    [ValidateSet('sql', 'survey', 'both')]
    [string] $Backend = 'both',
    [ValidateSet('mean', 'total', 'by', 'adult_mean', 'adult_by',
        'srvyr', 'glm', 'adult_glm', 'gaussian', 'poisson')]
    [string[]] $Calls = @('mean', 'total', 'by', 'adult_mean', 'adult_by',
        'srvyr', 'glm', 'adult_glm', 'gaussian', 'poisson'),
    [string] $Evidence
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
Set-Location $repo
$rscriptExe = (Get-Command $Rscript -CommandType Application).Source
$NisRoot = (Resolve-Path -LiteralPath $NisRoot).Path
$os = Get-CimInstance Win32_OperatingSystem
$system = Get-CimInstance Win32_ComputerSystem
$referenceMb = [int][Math]::Floor(0.6 * $system.TotalPhysicalMemory / 1e6)
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$evidenceRoot = Join-Path $repo 'local/loop/in-database-survey'
$null = New-Item -ItemType Directory -Path $evidenceRoot -Force
$evidenceRoot = (Resolve-Path -LiteralPath $evidenceRoot).Path
if (!$Evidence) { $Evidence = Join-Path $evidenceRoot "$stamp/private" }
$target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Evidence)
if (!$target.StartsWith($evidenceRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must stay in the local experiment directory.' }
git check-ignore --quiet -- (Join-Path $target 'metrics.tsv')
if ($LASTEXITCODE -ne 0) { throw 'Experiment evidence must be git-ignored.' }
$run = (New-Item -ItemType Directory -Path $target -Force).FullName
$metrics = Join-Path $run 'metrics.tsv'
$env:LC_ALL = 'C'
$workerScript = Join-Path $PSScriptRoot 'trial.R'

[ordered]@{
    started_utc = $stamp
    revision = (git rev-parse HEAD)
    input = $NisRoot
    invocation = $MyInvocation.Line
    backend = $Backend
    calls = $Calls
    rscript = $rscriptExe
    os = "$($os.Caption) $($os.Version)"
    physical_ram_bytes = $system.TotalPhysicalMemory
    free_ram_start_kib = $os.FreePhysicalMemory
    logical_cores = $system.NumberOfLogicalProcessors
    reference_memory_mb = $referenceMb
    harness_sha256 = @(Get-ChildItem -LiteralPath $PSScriptRoot -File | Get-FileHash |
        Select-Object @{N='file';E={Split-Path $_.Path -Leaf}}, Hash)
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $run "$stamp-environment.json")
Write-Output "Evidence directory $run"
& $rscriptExe --vanilla -e 'cat(R.version.string, "\n"); for(p in c("DBI","duckdb","survey","srvyr","jsonlite")) cat(p, as.character(packageVersion(p)), "\n")' > (Join-Path $run 'versions.txt')
if ($LASTEXITCODE -ne 0) { throw 'Could not determine R dependency versions.' }

function Get-Spill([string] $Path) {
    $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue)
    @{bytes = [long]($files | Measure-Object Length -Sum).Sum; files = $files.Count}
}

# The R PID handshake follows the Q26 runner. Kernel peaks include allocations
# between samples and the final handshake keeps even very short workers alive.
function Invoke-Trial([int] $End, [string] $Profile, [string] $Path, [string] $Call, [int] $Repeat) {
    $threads = if ($Profile -eq 'minimum') { 4 } else { 8 }
    $mb = if ($Profile -eq 'minimum') { 4800 } else { $referenceMb }
    $name = "$End-$Profile-$Path-$Call-$Repeat"
    $trial = (New-Item -ItemType Directory -Path (Join-Path $run $name)).FullName
    $spill = Join-Path $trial 'spill'
    $argLine = '--vanilla "{0}" "{1}" "{2}" {3} {4} {5} {6} {7}' -f
        $workerScript, $trial, $NisRoot, $End, $threads, $mb, $Path, $Call
    if ($Call -eq 'control_suite') { $argLine += " $($Calls -join ',')" }
    $launch = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process $rscriptExe -ArgumentList $argLine -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $trial 'stdout.log') `
        -RedirectStandardError (Join-Path $trial 'stderr.log')
    $pidFile = Join-Path $trial 'pid'
    $done = Join-Path $trial 'done'
    $worker = $null
    [long]$ws = 0
    [long]$commit = 0
    [long]$temp = 0
    $wall = $null
    $status = 'aborted'
    try {
        while (!$process.HasExited) {
            if (!$worker -and (Test-Path -LiteralPath $pidFile)) {
                $workerId = Get-Content -LiteralPath $pidFile -Raw
                if ($workerId) { $worker = Get-Process -Id ([int]$workerId) -ErrorAction SilentlyContinue }
            }
            $complete = Test-Path -LiteralPath $done
            if ($worker -and !$worker.HasExited) {
                try {
                    $worker.Refresh()
                    $ws = [Math]::Max($ws, $worker.PeakWorkingSet64)
                    $commit = [Math]::Max($commit, $worker.PeakPagedMemorySize64)
                } catch [InvalidOperationException] { }
            }
            $temp = [Math]::Max($temp, (Get-Spill $spill).bytes)
            if ($complete -and $null -eq $wall) {
                $wall = $launch.Elapsed.TotalSeconds
                $status = (Get-Content -LiteralPath $done -Raw).Trim()
                $null = New-Item -ItemType File -Path (Join-Path $trial 'sampled')
            }
            Start-Sleep -Milliseconds 50
        }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0 -and $status -eq 'ok') { $status = 'aborted' }
    } finally {
        if (!$process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
        if ($worker) { $worker.Dispose() }
    }
    if ($ws -eq 0 -or $commit -eq 0) { $status = 'unmeasured' }
    $elapsedFile = Join-Path $trial 'elapsed.txt'
    $queriesFile = Join-Path $trial 'queries.tsv'
    $queries = if (Test-Path -LiteralPath $queriesFile) {
        Import-Csv -LiteralPath $queriesFile -Delimiter "`t"
    }
    $timings = if (Test-Path -LiteralPath $elapsedFile) {
        @(Get-Content -LiteralPath $elapsedFile | ForEach-Object { [double]$_ })
    }
    $residual = Get-Spill $spill
    $row = [pscustomobject]@{
        trial = $name; end_year = $End; profile = $Profile; backend = $Path
        call = $Call; repeat = $Repeat; status = $status
        cache = 'OS cache unmanaged; warm eligible after audit'
        setup_s = if ($timings) { $timings[0] }
        call_s = if ($timings) { $timings[1] }
        wall_s = [Math]::Round(($wall ?? $launch.Elapsed.TotalSeconds), 3)
        peak_commit_bytes = $commit; peak_ws_bytes = $ws
        sampled_temp_bytes = $temp; residual_temp_bytes = $residual.bytes
        residual_temp_files = $residual.files
        duckdb_peak_buffer_bytes = ($queries | ForEach-Object { [long]$_.buffer_bytes } |
            Measure-Object -Maximum).Maximum
        duckdb_peak_temp_bytes = ($queries | ForEach-Object { [long]$_.temp_bytes } |
            Measure-Object -Maximum).Maximum
    }
    $row | Export-Csv $metrics -Delimiter "`t" -NoTypeInformation -Append
    Write-Host ("{0,-41} {1,-10} {2,8:F2} s  {3,6:F2} GB commit" -f
        $name, $status, $row.wall_s, ($commit / 1e9))
    return $row
}

foreach ($end in 2020, 2022) {
    if (!(Test-Path -LiteralPath (Join-Path $run "$end-minimum-sql-audit-1/audit.rds"))) {
        $audit = Invoke-Trial $end minimum sql audit 1
        if ($audit.status -ne 'ok') { throw 'Annual input validation failed. See private evidence.' }
    }
}
if ($Backend -ne 'survey') {
    foreach ($call in $Calls) {
        $cells = @(@{end=2020; profile='minimum'}, @{end=2020; profile='reference'},
            @{end=2022; profile='minimum'}, @{end=2022; profile='reference'})
        $finished = @{}
        for ($i = 1; $i -le $Repeats; $i++) {
            if ($i -gt 1) { [array]::Reverse($cells) }
            foreach ($cell in $cells) {
                $key = "$($cell.end)-$($cell.profile)"
                if ($finished[$key]) { continue }
                $result = Invoke-Trial $cell.end $cell.profile sql $call $i
                if ($result.status -ne 'ok' -or ($i -eq 1 -and $result.wall_s -ge 60)) {
                    $finished[$key] = $true
                }
            }
        }
    }
}
if ($Backend -ne 'sql') {
    $null = Invoke-Trial 2020 reference survey control_suite 1
}
& $rscriptExe --vanilla (Join-Path $PSScriptRoot 'summarize.R') $run
if ($LASTEXITCODE -ne 0) { throw 'Summary failed. See private evidence.' }
