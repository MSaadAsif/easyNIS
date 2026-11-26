#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('reference', 'minimum')]
    [string] $Profile,
    [string] $NisRoot = 'invented',
    [string] $Rscript = 'Rscript',
    [ValidateRange(3, 20)]
    [int] $Repeats = 3,
    [switch] $SplitConstruction
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
Set-Location $repo
$rscriptExe = (Get-Command $Rscript -CommandType Application).Source
$rExe = Join-Path (Split-Path $rscriptExe) 'R.exe'
$os = Get-CimInstance Win32_OperatingSystem
$system = Get-CimInstance Win32_ComputerSystem
$processors = @(Get-CimInstance Win32_Processor)
$drive = Get-Partition -DriveLetter ([IO.Path]::GetPathRoot($repo).Substring(0, 1)) | Get-Disk
$threads = if ($Profile -eq 'minimum') { 4 } else { [Math]::Min(8, $system.NumberOfLogicalProcessors) }
$memoryMb = if ($Profile -eq 'minimum') { 4800 } else { [int]([Math]::Floor(0.6 * $system.TotalPhysicalMemory / 1e6)) }
$invented = $NisRoot -eq 'invented'
if (!$invented) { $NisRoot = (Resolve-Path -LiteralPath $NisRoot).Path }
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$kind = if ($invented) { 'invented' } else { 'licensed' }
$relative = "local/loop/q26-survey-backend/$stamp-$kind-$Profile/private"
git check-ignore --quiet -- "$relative/metrics.tsv"
if ($LASTEXITCODE -ne 0) { throw 'Experiment outputs must be Git-ignored.' }
$run = (New-Item -ItemType Directory -Path (Join-Path $repo $relative) -Force).FullName
$library = (New-Item -ItemType Directory -Path (Join-Path $run 'library')).FullName
$scratch = (New-Item -ItemType Directory -Path (Join-Path $run 'r-tmp')).FullName
$env:R_LIBS = if ($env:R_LIBS) { "$library;$env:R_LIBS" } else { $library }
$env:TMP = $env:TEMP = $env:TMPDIR = $scratch
$env:LC_ALL = 'C'
$experiment = Join-Path $PSScriptRoot 'experiment.R'
$summary = Join-Path $PSScriptRoot 'summarize.R'
$tasks = @('mean', 'total', 'by', 'adult_mean', 'adult_by', 'hf_mean', 'hf_glm', 'glm', 'srvyr')
if ($invented) { $tasks += 'table' }

[ordered]@{
    profile = $Profile
    dataset = $kind
    input = $NisRoot
    revision = (git rev-parse HEAD)
    command = "pwsh -NoProfile -File tools/experiments/q26-survey-backend/run.ps1 -Profile $Profile -NisRoot `"$NisRoot`" -Rscript `"$Rscript`" -Repeats $Repeats" +
        $(if ($SplitConstruction) { ' -SplitConstruction' })
    started_utc = $stamp
    os = "$($os.Caption) $($os.Version)"
    physical_ram_bytes = $system.TotalPhysicalMemory
    free_ram_start_kib = $os.FreePhysicalMemory
    cpu = ($processors.Name -join ', ')
    physical_cores = ($processors.NumberOfCores | Measure-Object -Sum).Sum
    logical_cores = $system.NumberOfLogicalProcessors
    cpu_load_start_pct = ($processors.LoadPercentage | Measure-Object -Average).Average
    disk = "$($drive.FriendlyName), $($drive.BusType), $($drive.Size) bytes"
    rscript = $rscriptExe
    duckdb_threads = $threads
    duckdb_memory_mb = $memoryMb
    repeats_under_one_minute = $Repeats
    split_construction = $SplitConstruction.IsPresent
    harness_sha256 = [ordered]@{
        'run.ps1' = (Get-FileHash -LiteralPath $PSCommandPath).Hash
        'experiment.R' = (Get-FileHash -LiteralPath $experiment).Hash
        'summarize.R' = (Get-FileHash -LiteralPath $summary).Hash
    }
} | ConvertTo-Json | Set-Content (Join-Path $run 'environment.json')
Write-Output "Evidence directory $run"

function Get-TreeBytes([string] $Path) {
    [long](Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
}

function Invoke-Trial([string] $Backend, [string] $Task, [int] $Repeat,
        [string] $Stage = 'measure', [string] $Key = '') {
    $name = if ($Stage -eq 'build') { "build-$Key" } else { "$Task-$Backend-$Repeat" }
    $trial = (New-Item -ItemType Directory -Path (Join-Path $run $name)).FullName
    $spill = Join-Path $trial 'spill'
    $cache = Join-Path $scratch "design-$Key.rds"
    $argLine = '--vanilla "{0}" {7} "{1}" {2} {3} {4} {5} "{6}" "{8}"' -f
        $experiment, $run, $threads, $memoryMb, $Backend, $Task, $trial, $Stage, $cache
    $launch = [Diagnostics.Stopwatch]::StartNew()
    $startOptions = @{
        ArgumentList = $argLine
        PassThru = $true
        WindowStyle = 'Hidden'
        RedirectStandardOutput = Join-Path $trial 'stdout.log'
        RedirectStandardError = Join-Path $trial 'stderr.log'
    }
    $process = Start-Process $rscriptExe @startOptions
    $buildFile = Join-Path $trial 'build-seconds.txt'
    $callFile = Join-Path $trial 'call-seconds.txt'
    $done = Join-Path $trial 'done'
    $pidFile = Join-Path $trial 'pid'
    $worker = $null
    [long]$peak = 0
    [long]$buildPeak = 0
    [long]$tempPeak = 0
    $buildSampled = $false
    $sampledDone = $false
    $doneSeconds = $null
    try {
        while (!$process.HasExited) {
            # Rscript.exe can launch the interpreter as a separate Windows process.
            if (!$worker -and (Test-Path -LiteralPath $pidFile)) {
                $workerId = Get-Content -LiteralPath $pidFile -Raw
                if ($workerId) {
                    $worker = Get-Process -Id ([int]$workerId) -ErrorAction SilentlyContinue
                }
            }
            if ($worker -and !$worker.HasExited) {
                $worker.Refresh()
                try { $peak = [Math]::Max($peak, $worker.PeakWorkingSet64) }
                catch [InvalidOperationException] { }
            }
            $tempPeak = [Math]::Max($tempPeak, (Get-TreeBytes $spill))
            if (!$buildSampled -and (Test-Path -LiteralPath $buildFile)) {
                $buildPeak = $peak
                New-Item -ItemType File -Path (Join-Path $trial 'build-sampled') | Out-Null
                $buildSampled = $true
            }
            if (!$sampledDone -and (Test-Path -LiteralPath $done)) {
                $doneSeconds = $launch.Elapsed.TotalSeconds
                New-Item -ItemType File -Path (Join-Path $trial 'sampled') | Out-Null
                $sampledDone = $true
            }
            Start-Sleep -Milliseconds 50
        }
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    } finally {
        if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
        if ($worker) { $worker.Dispose() }
    }
    $residual = Get-TreeBytes $spill
    $status = if ($sampledDone) { (Get-Content -LiteralPath $done -Raw).Trim() } else { 'aborted' }
    if ($exitCode -ne 0 -and $status -eq 'ok') { $status = 'aborted' }
    if ($peak -eq 0) { $status = 'unmeasured' }
    if ($null -eq $doneSeconds) { $doneSeconds = $launch.Elapsed.TotalSeconds }
    Remove-OwnedDirectory $spill
    [pscustomobject]@{
        profile = $Profile
        call = $Task
        path = $Backend
        repeat = $Repeat
        status = $status
        exit_code = $exitCode
        stage = $Stage
        design_key = $Key
        build_s = if (Test-Path -LiteralPath $buildFile) { [double](Get-Content $buildFile -Raw) }
        call_s = if (Test-Path -LiteralPath $callFile) { [double](Get-Content $callFile -Raw) }
        process_s = [Math]::Round($doneSeconds, 3)
        build_peak_bytes = $buildPeak
        peak_bytes = $peak
        temp_peak_bytes = $tempPeak
        residual_bytes = $residual
    }
}

function Get-DesignKey([string] $Backend, [string] $Task) {
    if ($Backend -eq 'dbi') { return 'dbi-full' }
    switch -Regex ($Task) {
        '^(mean|by|table)$' { 'placeholder-full-los' }
        '^(adult_mean|adult_by|srvyr)$' { 'placeholder-adult-los' }
        default { "placeholder-$Task" }
    }
}

function Remove-OwnedDirectory([string] $Path) {
    if (!(Test-Path -LiteralPath $Path)) { return }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (!$resolved.StartsWith($run + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup path escaped experiment directory.' }
    Remove-Item -LiteralPath $resolved -Force -Recurse
}

try {
    & $rExe CMD INSTALL --no-multiarch --with-keep.source "--library=$library" . *> (Join-Path $run 'install.log')
    if ($LASTEXITCODE -ne 0) { throw "Package installation failed. See $run/install.log." }
    & $rscriptExe --vanilla $experiment prepare $run $threads $memoryMb $NisRoot *> (Join-Path $run 'prepare.log')
    if ($LASTEXITCODE -ne 0) { throw "Input preparation failed. See $run/prepare.log." }
    $metrics = Join-Path $run 'metrics.tsv'
    $builds = @{}
    foreach ($task in $tasks) {
        $remaining = @('dbi', 'placeholder')
        for ($i = 1; $i -le $Repeats; $i++) {
            $order = if ($i % 2 -eq 1) { 'dbi', 'placeholder' } else { 'placeholder', 'dbi' }
            foreach ($backend in $order) {
                if ($backend -notin $remaining) { continue }
                if ($SplitConstruction) {
                    $key = Get-DesignKey $backend $task
                    if (!$builds.ContainsKey($key)) {
                        $builds[$key] = Invoke-Trial $backend $task 1 'build' $key
                        $builds[$key] | Export-Csv (Join-Path $run 'construction.tsv') -Delimiter ([char]9) -NoTypeInformation -Append
                        Write-Output ("Build {0} {1} {2:F2} s {3:F2} GB" -f $key,
                            $builds[$key].status, $builds[$key].process_s,
                            ($builds[$key].build_peak_bytes / 1e9))
                    }
                    $created = $builds[$key]
                    if ($created.status -eq 'ok') {
                        $trial = Invoke-Trial $backend $task $i 'load' $key
                    } else {
                        $trial = $created.PSObject.Copy()
                        $trial.call = $task
                        $trial.stage = 'build-failed'
                    }
                } else {
                    $trial = Invoke-Trial $backend $task $i
                }
                $trial | Export-Csv $metrics -Delimiter ([char]9) -NoTypeInformation -Append
                Write-Output ("{0,-12} {1,-11} #{2} {3,-7} {4,7:F2} s {5,6:F2} GB" -f
                    $task, $backend, $i, $trial.status, $trial.process_s, ($trial.peak_bytes / 1e9))
                if ($trial.status -ne 'ok' -or ($i -eq 1 -and ($trial.build_s + $trial.call_s) -ge 60)) {
                    $remaining = @($remaining | Where-Object { $_ -ne $backend })
                }
            }
            if (!$remaining.Count) { break }
        }
    }
    & $rscriptExe --vanilla $summary $run
    if ($LASTEXITCODE -ne 0) { throw 'Result comparison failed to run.' }
} finally {
    Remove-OwnedDirectory $scratch
    Remove-OwnedDirectory $library
    Remove-OwnedDirectory (Join-Path $run 'setup-spill')
}
