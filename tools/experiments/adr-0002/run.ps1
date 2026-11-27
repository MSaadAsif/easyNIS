param([Parameter(Mandatory)][string]$Evidence, [string[]]$Tasks, [int[]]$Profiles = @(4, 8))
$ErrorActionPreference = 'Stop'
if (!$Tasks) {
  $Tasks = @('open','open_skip','open_arrow','flag_dx','flag_pr','timing','ccsr_default','ccsr_codes',
    'outcomes','comorbidity','attrition','design','saved_design','survey','survey_by','survey_glm','annual',
    'cells','suppress','write','convert','prday','dx_audit','inventory','audit','compute','collect_narrow','ccsr')
}
$evidencePath = (Resolve-Path -LiteralPath $Evidence).Path
$r = Join-Path (Split-Path (Get-Command Rscript).Source) "x64/Rscript.exe"
foreach ($profile in $Profiles) {
  foreach ($task in $Tasks) {
    $stem = Join-Path $evidencePath "$task-$profile"
    $argsForR = @('--vanilla', 'tools/experiments/adr-0002/capture.R', "`"$evidencePath`"", $task, "$profile")
    $proc = Start-Process -FilePath $r -ArgumentList $argsForR -WindowStyle Hidden -PassThru -RedirectStandardOutput "$stem.stdout" -RedirectStandardError "$stem.stderr"
    $peak = 0L
    $peakRss = 0L
    while (!$proc.HasExited) {
      $proc.Refresh()
      $peak = [Math]::Max($peak, $proc.PeakPagedMemorySize64)
      $peakRss = [Math]::Max($peakRss, $proc.PeakWorkingSet64)
      Start-Sleep -Milliseconds 20
    }
    $proc.WaitForExit()
    [pscustomobject]@{task=$task; threads=$profile; peak_commit_bytes=$peak; peak_working_set=$peakRss; exit=$proc.ExitCode} |
      ConvertTo-Json -Compress | Set-Content "$stem.process.json"
    Write-Output "$task/$profile exit $($proc.ExitCode) private $peak"
  }
}
