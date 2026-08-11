param(
    [int]$SampleIntervalMs = 500
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $projectRoot "build\performance"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stdoutPath = Join-Path $reportDir "desktop-lyric-$timestamp.stdout.log"
$stderrPath = Join-Path $reportDir "desktop-lyric-$timestamp.stderr.log"
$summaryPath = Join-Path $reportDir "desktop-lyric-$timestamp.summary.json"
$flutterPath = (Get-Command flutter).Source
$startedAt = Get-Date
$arguments = @(
    "run",
    "--profile",
    "--device-id=windows",
    "--no-pub",
    "--target=tool/windows_desktop_lyric_benchmark.dart"
)
$driveProcess = Start-Process `
    -FilePath $flutterPath `
    -ArgumentList $arguments `
    -WorkingDirectory $projectRoot `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

try {
    $deadline = (Get-Date).AddMinutes(5)
    $appProcess = $null
    while ((Get-Date) -lt $deadline -and -not $driveProcess.HasExited) {
        $appProcess = Get-Process -Name "desktop_lyric" -ErrorAction SilentlyContinue |
            Where-Object { $_.StartTime -ge $startedAt } |
            Sort-Object StartTime -Descending |
            Select-Object -First 1
        if ($null -ne $appProcess) { break }
        Start-Sleep -Milliseconds 500
        $driveProcess.Refresh()
    }
    if ($null -eq $appProcess) {
        throw "The desktop lyric benchmark app did not start. See $stdoutPath and $stderrPath."
    }

    $logicalProcessors = [Environment]::ProcessorCount
    $samples = [System.Collections.Generic.List[object]]::new()
    $previousCpuSeconds = $appProcess.TotalProcessorTime.TotalSeconds
    $previousSampleTime = Get-Date
    $appProcessId = $appProcess.Id

    while ($true) {
        Start-Sleep -Milliseconds ([Math]::Max(100, $SampleIntervalMs))
        $appProcess = Get-Process -Id $appProcessId -ErrorAction SilentlyContinue
        if ($null -eq $appProcess) { break }
        $sampledAt = Get-Date
        $sampleDuration = ($sampledAt - $previousSampleTime).TotalSeconds
        $cpuSeconds = $appProcess.TotalProcessorTime.TotalSeconds
        $cpuPercent = 0.0
        if ($sampleDuration -gt 0) {
            $cpuPercent = (($cpuSeconds - $previousCpuSeconds) /
                    $sampleDuration / $logicalProcessors) * 100.0
        }
        $previousSampleTime = $sampledAt
        $previousCpuSeconds = $cpuSeconds

        $phase = "startup"
        try {
            $output = Get-Content -Path $stdoutPath -Raw -Encoding UTF8
            $matches = [regex]::Matches($output, "DESKTOP_LYRIC_PHASE (?<phase>[a-z_]+)")
            if ($matches.Count -gt 0) {
                $phase = $matches[$matches.Count - 1].Groups["phase"].Value
            }
        }
        catch {}

        $samples.Add([pscustomobject]@{
            Timestamp = $sampledAt.ToString("o")
            Phase = $phase
            CpuPercent = [Math]::Round($cpuPercent, 3)
            WorkingSetMb = [Math]::Round($appProcess.WorkingSet64 / 1MB, 3)
            PrivateMemoryMb = [Math]::Round($appProcess.PrivateMemorySize64 / 1MB, 3)
        })
    }

    $driveProcess.WaitForExit()
    $driveProcess.Refresh()
    $flutterOutput = Get-Content -Path $stdoutPath -Raw -Encoding UTF8
    $reportMatch = [regex]::Match($flutterOutput, "DESKTOP_LYRIC_REPORT (?<json>\[.*\])")
    if (-not $reportMatch.Success) {
        throw "The benchmark report is missing. See $stdoutPath and $stderrPath."
    }

    $parsedReport = $reportMatch.Groups["json"].Value | ConvertFrom-Json
    $report = if ($parsedReport -is [System.Array]) {
        @($parsedReport)
    }
    elseif ($parsedReport.PSObject.Properties.Name -contains "value") {
        @($parsedReport.value)
    }
    else {
        @($parsedReport)
    }
    $cpuValues = [double[]]$samples.CpuPercent
    $summary = [ordered]@{
        SampleCount = $samples.Count
        LogicalProcessors = $logicalProcessors
        CpuAveragePercent = [Math]::Round(($cpuValues | Measure-Object -Average).Average, 3)
        CpuPeakPercent = [Math]::Round(($cpuValues | Measure-Object -Maximum).Maximum, 3)
        WorkingSetPeakMb = [Math]::Round(($samples.WorkingSetMb | Measure-Object -Maximum).Maximum, 3)
        PrivateMemoryPeakMb = [Math]::Round(($samples.PrivateMemoryMb | Measure-Object -Maximum).Maximum, 3)
        FrameReport = $report
        Samples = $samples
        FlutterOutput = $stdoutPath
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -Path $summaryPath -Encoding UTF8
    $summary | Format-List
}
finally {
    if (-not $driveProcess.HasExited) {
        Stop-Process -Id $driveProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
