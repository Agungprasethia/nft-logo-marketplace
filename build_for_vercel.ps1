#!/usr/bin/env pwsh
# =============================================================
# NFT Marketplace — Build Script for Vercel Deployment
# =============================================================
# Usage: .\build_for_vercel.ps1
# =============================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Building for Vercel Deployment" -ForegroundColor Cyan  
Write-Host "========================================`n" -ForegroundColor Cyan

# Step 1: Build Mobile App (Main Web App)
Write-Host "[1/4] Building Mobile App (Main Website)..." -ForegroundColor Yellow
Set-Location -Path "mobile-app"
flutter build web
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ Failed to build mobile-app!" -ForegroundColor Red
    exit 1
}
Set-Location -Path ".."
Write-Host "  ✅ Mobile App built successfully`n" -ForegroundColor Green

# Step 2: Build Admin Dashboard
Write-Host "[2/4] Building Admin Dashboard (Sub-directory /admin/)..." -ForegroundColor Yellow
Set-Location -Path "admin-dashboard"
flutter build web --base-href "/admin/"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ Failed to build admin-dashboard!" -ForegroundColor Red
    exit 1
}
Set-Location -Path ".."
Write-Host "  ✅ Admin Dashboard built successfully`n" -ForegroundColor Green

# Step 3: Combine both builds into public_deploy folder
Write-Host "[3/4] Assembling public_deploy folder..." -ForegroundColor Yellow
$deployDir = "public_deploy"

# Hapus jika folder public_deploy sudah ada dari build sebelumnya
if (Test-Path -Path $deployDir) {
    Remove-Item -Path $deployDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $deployDir | Out-Null

# Copy mobile-app/build/web ke public_deploy
Copy-Item -Path "mobile-app\build\web\*" -Destination $deployDir -Recurse -Force

# Buat folder admin di dalam public_deploy
$adminDir = Join-Path -Path $deployDir -ChildPath "admin"
New-Item -ItemType Directory -Force -Path $adminDir | Out-Null

# Copy admin-dashboard/build/web ke public_deploy/admin
Copy-Item -Path "admin-dashboard\build\web\*" -Destination $adminDir -Recurse -Force

Write-Host "  ✅ Folders assembled`n" -ForegroundColor Green

# Step 4: Create vercel.json
Write-Host "[4/4] Creating vercel.json for routing..." -ForegroundColor Yellow
$vercelJsonContent = @"
{
  "rewrites": [
    { "source": "/admin/(.*)", "destination": "/admin/index.html" },
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
Write-Host "  1. Open terminal and run: cd public_deploy" -ForegroundColor Gray
Write-Host "  2. Run Vercel CLI: vercel --prod" -ForegroundColor Gray
Write-Host "     (Or simply drag and drop the 'public_deploy' folder to the Vercel dashboard if you use the web UI)" -ForegroundColor Gray
Write-Host ""
