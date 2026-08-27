#!/usr/bin/env pwsh
# =============================================================
# NFT Marketplace — Build Script for Vercel Deployment
# =============================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Building for Vercel Deployment" -ForegroundColor Cyan  
Write-Host "========================================`n" -ForegroundColor Cyan

# Step 1: Build Mobile App (Main Web App & Admin)
Write-Host "[1/3] Building Flutter App..." -ForegroundColor Yellow
Set-Location -Path "mobile-app"
flutter build web
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ Failed to build mobile-app!" -ForegroundColor Red
    exit 1
}
Set-Location -Path ".."
Write-Host "  ✅ App built successfully`n" -ForegroundColor Green

# Step 2: Assemble public_deploy folder
Write-Host "[2/3] Assembling public_deploy folder..." -ForegroundColor Yellow
$deployDir = "public_deploy"

if (Test-Path -Path $deployDir) {
    Remove-Item -Path $deployDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $deployDir | Out-Null

# Copy mobile-app/build/web ke public_deploy
Copy-Item -Path "mobile-app\build\web\*" -Destination $deployDir -Recurse -Force
Write-Host "  ✅ Folders assembled`n" -ForegroundColor Green

# Step 3: Create vercel.json
Write-Host "[3/3] Creating vercel.json for routing..." -ForegroundColor Yellow
$vercelJsonContent = @"
{
  "rewrites": [
    { "source": "/(.*)", "destination": "/index.html" }
  ]
}
"@
Set-Content -Path (Join-Path -Path $deployDir -ChildPath "vercel.json") -Value $vercelJsonContent
Write-Host "  ✅ vercel.json created`n" -ForegroundColor Green

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " BUILD COMPLETE ✅" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  Deploy 'public_deploy' folder to Vercel" -ForegroundColor Gray
Write-Host ""
