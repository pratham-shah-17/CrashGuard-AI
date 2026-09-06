# CrashGuard AI verification script (fast local gate)
#
# Runs the same high-signal checks CI expects from contributors:
# - dependency resolution
# - static analysis
# - unit/widget tests

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host "Verifying CrashGuard AI..." -ForegroundColor Cyan

# Resolve Flutter when not on PATH (ZIP installs, CI clones, Android Studio SDK).
if (!(Get-Command flutter -ErrorAction SilentlyContinue)) {
    if ($env:FLUTTER_ROOT) {
        $flutterBin = Join-Path $env:FLUTTER_ROOT "bin"
        if (Test-Path (Join-Path $flutterBin "flutter.bat")) {
            $env:Path = "$flutterBin;$env:Path"
        }
    }
}
if (!(Get-Command flutter -ErrorAction SilentlyContinue)) {
    foreach ($dir in @(
            "C:\Users\Aravindh\Downloads\flutter_windows_3.41.8-stable\flutter\bin",
            "$env:LOCALAPPDATA\Android\flutter\bin",
            "$env:USERPROFILE\flutter\bin"
        )) {
        if (Test-Path "$dir\flutter.bat") {
            $env:Path = "$dir;$env:Path"
            Write-Host "Using Flutter SDK bin: $dir" -ForegroundColor DarkGray
            break
        }
    }
}

if (!(Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error @"
Flutter is not on PATH. Install: https://docs.flutter.dev/get-started/install/windows
Then reopen the terminal and run this script again from the repo root:
  .\scripts\verify.ps1
"@
    exit 1
}

Write-Host "flutter pub get" -ForegroundColor Yellow
flutter pub get

Write-Host "flutter analyze" -ForegroundColor Yellow
flutter analyze

Write-Host "flutter test" -ForegroundColor Yellow
flutter test

Write-Host "Verification complete." -ForegroundColor Green

