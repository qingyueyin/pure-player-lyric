param(
    [switch] $NoPause
)

$ErrorActionPreference = "Stop"

Set-Location -Path $PSScriptRoot

$BuildMode = "Release"
$finalOutputDir = Join-Path $PSScriptRoot "output"
$ephemeralDir = "windows\flutter\ephemeral"

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

if (-not (Test-Path $appIconResourcePath)) {
    Write-Warning "Icon not found: $appIconResourcePath. The application icon might be default."
}
else {
    if ((Test-Path $exePath) -and (Test-Path $buildRoot)) {
        $iconTime = (Get-Item $appIconResourcePath).LastWriteTime
        $exeTime = (Get-Item $exePath).LastWriteTime
        if ($iconTime -gt $exeTime) {
            Write-Host "Icon updated; cleaning $buildRoot to force resource rebuild..." -ForegroundColor Yellow
            Remove-Item -Path $buildRoot -Recurse -Force
        }
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
