#!/usr/bin/env pwsh
# =============================================================
# NFT Marketplace — One-Click Deployment Script
# =============================================================
# Usage: .\deploy.ps1
# Prerequisites: 
#   - Node.js installed
#   - Firebase CLI: npm install -g firebase-tools
#   - Logged in: firebase login
# =============================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " NFT Marketplace Deployment" -ForegroundColor Cyan  
Write-Host "========================================`n" -ForegroundColor Cyan

# Step 1: Firebase Login Check
Write-Host "[1/5] Checking Firebase authentication..." -ForegroundColor Yellow
$loginResult = npx firebase-tools login:list 2>&1
if ($loginResult -match "No authorized accounts") {
    Write-Host "  ⚠️  Not logged in. Opening browser for login..." -ForegroundColor Red
    npx firebase-tools login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ❌ Login failed. Run 'npx firebase-tools login' manually." -ForegroundColor Red
        exit 1
    }
}
Write-Host "  ✅ Authenticated" -ForegroundColor Green

# Step 2: Deploy Firestore Security Rules
Write-Host "`n[2/5] Deploying Firestore security rules..." -ForegroundColor Yellow
npx firebase-tools deploy --only firestore:rules --project leo-nft-marketplace 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ Rules deployment failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  ✅ Security rules deployed" -ForegroundColor Green

# Step 3: Deploy Firestore Indexes
Write-Host "`n[3/5] Deploying Firestore composite indexes..." -ForegroundColor Yellow
npx firebase-tools deploy --only firestore:indexes --project leo-nft-marketplace 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ❌ Index deployment failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  ✅ Composite indexes deployed (may take a few minutes to build)" -ForegroundColor Green

# Step 4: Flutter Analyze
Write-Host "`n[4/5] Running Flutter analysis..." -ForegroundColor Yellow
$analyzeResult = flutter analyze --no-pub 2>&1
$errors = $analyzeResult | Select-String -Pattern "^  error" -CaseSensitive
if ($errors) {
    Write-Host "  ❌ Compile errors found:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    exit 1
}
$warnings = $analyzeResult | Select-String -Pattern "^  warning" -CaseSensitive
$issueCount = ($analyzeResult | Select-String -Pattern "issues found").ToString()
Write-Host "  ✅ Analysis passed: $issueCount" -ForegroundColor Green
if ($warnings) {
    Write-Host "  ⚠️  Warnings (non-blocking):" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
}

# Step 5: Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " DEPLOYMENT COMPLETE ✅" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Create admin account:" -ForegroundColor White
Write-Host "     Firebase Console → Firestore → users/{uid} → role: 'admin'" -ForegroundColor Gray
Write-Host "  2. Run mobile app:  flutter run -d <android-device>" -ForegroundColor Gray
Write-Host "  3. Run web admin:   flutter run -d chrome" -ForegroundColor Gray
Write-Host ""
