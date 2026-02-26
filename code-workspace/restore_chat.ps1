# Script to restore Cursor chat history from backup
# Run this script if your chat history is missing

$workspaceStorage = "C:\Users\robie\AppData\Roaming\Cursor\User\workspaceStorage\53725de4b99ffb0be1f96c1045b09918"
$mainDb = Join-Path $workspaceStorage "state.vscdb"
$backupDb = Join-Path $workspaceStorage "state.vscdb.backup"

Write-Host "Cursor Chat History Restore Script" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

# Check if files exist
if (-not (Test-Path $backupDb)) {
    Write-Host "ERROR: Backup file not found at: $backupDb" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $mainDb)) {
    Write-Host "WARNING: Main database file not found. Creating from backup..." -ForegroundColor Yellow
    Copy-Item $backupDb $mainDb
    Write-Host "✓ Restored from backup" -ForegroundColor Green
    exit 0
}

# Create a backup of current state
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$oldBackup = "$mainDb.old_$timestamp"
Copy-Item $mainDb $oldBackup
Write-Host "✓ Created backup of current state: $oldBackup" -ForegroundColor Green

# Restore from backup
Copy-Item $backupDb $mainDb -Force
Write-Host "✓ Restored chat history from backup" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Close Cursor completely (if it's open)" -ForegroundColor White
Write-Host "2. Reopen Cursor and open your workspace" -ForegroundColor White
Write-Host "3. Your chat history should now be restored" -ForegroundColor White

