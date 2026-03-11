param(
    [switch] $NoPause
)

$ErrorActionPreference = "Stop"

Set-Location -Path $PSScriptRoot

$BuildMode = "Release"
$finalOutputDir = Join-Path $PSScriptRoot "output"
$ephemeralDir = "windows\flutter\ephemeral"
$logsDir = Join-Path $PSScriptRoot "logs"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logsDir "build_$timestamp.log"

if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
}

Write-Host "Starting build process ($BuildMode Mode)..." -ForegroundColor Green

if (-not (Get-Command "flutter" -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter command not found. Please ensure Flutter is installed and in your PATH."
    if (-not $NoPause) { Read-Host "Press Enter to exit..." }
    exit 1
}

if (Test-Path $ephemeralDir) {
    Write-Host "Cleaning ephemeral directory to avoid symlink conflicts..." -ForegroundColor Yellow
    Remove-Item -Path $ephemeralDir -Recurse -Force
}

$VerbosePreference = "Continue"
$DebugPreference = "Continue"

function Write-Log {
    param([string]$Message)
    $Message | Tee-Object -FilePath $logFile -Append | Out-Null
}

$needPubGet = $true
$packageConfig = ".dart_tool\package_config.json"

if ((Test-Path "pubspec.yaml") -and (Test-Path "pubspec.lock") -and (Test-Path $packageConfig)) {
    $yamlTime = (Get-Item "pubspec.yaml").LastWriteTime
    $lockTime = (Get-Item "pubspec.lock").LastWriteTime
    if ($yamlTime -le $lockTime) {
        $needPubGet = $false
    }
}

if ($needPubGet) {
    Write-Host "Running flutter pub get..." -ForegroundColor Cyan
    flutter pub get
}
else {
    Write-Host "Skipping flutter pub get (dependencies are up to date)." -ForegroundColor Gray
}

$appIconResourcePath = "windows\runner\resources\app_icon.ico"
$buildRoot = "build\windows"
$exePath = "build\windows\x64\runner\$BuildMode\desktop_lyric.exe"

function Update-RcVersion {
    $pubspec = Join-Path $PSScriptRoot "pubspec.yaml"
    if (-not (Test-Path $pubspec)) { return }
    
    $content = Get-Content -Path $pubspec -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return }
    
    $m = [regex]::Match($content, '(?m)^\s*version\s*:\s*([^\r\n]+)\s*$')
    if (-not $m.Success) { return }
    
    $version = $m.Groups[1].Value.Trim()
    
    $rcPath = Join-Path $PSScriptRoot "windows\runner\Runner.rc"
    if (-not (Test-Path $rcPath)) { return }
    
    $rcContent = Get-Content -Path $rcPath -Raw
    
    $parts = $version -split '\+'
    $verNum = $parts[0]
    $verParts = $verNum -split '\.'
    
    $major = if ($verParts.Length -gt 0) { $verParts[0] } else { "0" }
    $minor = if ($verParts.Length -gt 1) { $verParts[1] } else { "0" }
    $patch = if ($verParts.Length -gt 2) { $verParts[2] } else { "0" }
    $build = if ($parts.Length -gt 1) { $parts[1] } else { "0" }
    
    $newNumber = "$major,$minor,$patch,$build"
    $newString = """$version"""
    
    $rcContent = $rcContent -replace '#define VERSION_AS_NUMBER .+', "#define VERSION_AS_NUMBER $newNumber"
    $rcContent = $rcContent -replace '#define VERSION_AS_STRING ".+"', "#define VERSION_AS_STRING $newString"
    
    Set-Content -Path $rcPath -Value $rcContent -NoNewline -ErrorAction SilentlyContinue
    Write-Host "Updated Runner.rc version to $version" -ForegroundColor Green
}

Update-RcVersion

if (-not (Test-Path $appIconResourcePath)) {
    Write-Warning "Icon not found: $appIconResourcePath. The application icon might be default."
}
else {
    # Always clear the previous build artifacts so that any changes
    # to the resource files (icon/manifest) are picked up.  Without this step
    # the cached object files can keep the previous icon which results in the
    # compiled executable showing the wrong icon in Explorer.
    if (Test-Path $buildRoot) {
        Write-Host "Cleaning $buildRoot to ensure resources are rebuilt..." -ForegroundColor Yellow
        Remove-Item -Path $buildRoot -Recurse -Force
    }
}

Write-Host "Building Windows ($BuildMode)..." -ForegroundColor Cyan
flutter build windows --release

if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed!"
    if (-not $NoPause) { Read-Host "Press Enter to exit..." }
    exit 1
}

$buildDir = "build\windows\x64\runner\$BuildMode"
if (-not (Test-Path $buildDir)) {
    Write-Error "Build output directory not found: $buildDir"
    if (-not $NoPause) { Read-Host "Press Enter to exit..." }
    exit 1
}

Write-Host "Preparing Output Directory: $finalOutputDir..." -ForegroundColor Cyan

$processName = "desktop_lyric"
if (Get-Process $processName -ErrorAction SilentlyContinue) {
    Write-Host "Stopping running instance of $processName..." -ForegroundColor Yellow
    Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

if (Test-Path $finalOutputDir) {
    Remove-Item -Path $finalOutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $finalOutputDir | Out-Null

Write-Host "Copying build artifacts to output directory..." -ForegroundColor Cyan
Copy-Item -Path "$buildDir\*" -Destination $finalOutputDir -Recurse -Force

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "All files have been output to: $finalOutputDir" -ForegroundColor Yellow
Write-Host "  - Main: desktop_lyric.exe (icon embedded via Runner.rc)`n" -ForegroundColor Yellow

if (-not $NoPause) { Read-Host "Press Enter to exit..." }
