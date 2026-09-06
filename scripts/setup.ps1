# CrashGuard AI Dev Setup Script

Write-Host "🚀 Initializing CrashGuard AI Development Environment..." -ForegroundColor Cyan

# 1. Check Flutter
if (!(Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter is not installed. Please install Flutter before continuing."
    exit 1
}

# 2. Get Dependencies
Write-Host "📦 Fetching dependencies..." -ForegroundColor Yellow
flutter pub get

# 3. Handle dotenv (Flutter loads assets/.env)
$assetsDir = Join-Path $PSScriptRoot "..\\assets"
$envTemplatePath = Join-Path $assetsDir "env.template"
$envPath = Join-Path $assetsDir ".env"

if (!(Test-Path $assetsDir)) {
    Write-Error "Expected assets directory not found: $assetsDir"
    exit 1
}

if (!(Test-Path $envTemplatePath)) {
    Write-Error "Expected env template not found: $envTemplatePath"
    exit 1
}

if (!(Test-Path $envPath)) {
    Write-Host "📄 Creating assets/.env from assets/env.template..." -ForegroundColor Yellow
    Copy-Item $envTemplatePath $envPath
    Write-Host "⚠️ Created assets/.env. Fill in values locally and avoid committing secrets." -ForegroundColor Red
} else {
    Write-Host "📄 Found assets/.env (leaving as-is)." -ForegroundColor Green
}

# 4. Run Analysis
Write-Host "🔍 Running initial analysis..." -ForegroundColor Yellow
flutter analyze

Write-Host "✅ Setup complete! You are ready to build CrashGuard AI." -ForegroundColor Green
