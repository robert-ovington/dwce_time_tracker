# Sync Projects from Access to Supabase using PowerShell
# Requires: ImportExcel module for CSV handling, or use built-in CSV cmdlets

param(
    [string]$AccessDbPath = "C:\path\to\your\database.accdb",
    [string]$SupabaseUrl = "your-supabase-url",
    [string]$SupabaseKey = "your-supabase-key",
    [string]$TempCsvPath = "$env:TEMP\projects_export.csv"
)

# Export from Access to CSV using Access COM object
Write-Host "🔄 Exporting projects from Access..." -ForegroundColor Cyan

try {
    $access = New-Object -ComObject Access.Application
    $access.OpenCurrentDatabase($AccessDbPath)
    
    # Export query to CSV
    $access.DoCmd.TransferText(
        [Microsoft.Office.Interop.Access.AcTextTransferType]::acExportDelim,
        "",  # Specification name (empty for default)
        "projects",  # Table name
        $TempCsvPath,
        $true  # Has field names
    )
    
    $access.CloseCurrentDatabase()
    $access.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($access) | Out-Null
    
    Write-Host "✅ Exported to CSV" -ForegroundColor Green
    
    # Read CSV
    $projects = Import-Csv $TempCsvPath
    
    # Upload to Supabase using REST API
    Write-Host "🔄 Uploading to Supabase..." -ForegroundColor Cyan
    
    $headers = @{
        "apikey" = $SupabaseKey
        "Authorization" = "Bearer $SupabaseKey"
        "Content-Type" = "application/json"
        "Prefer" = "return=representation"
    }
    
    foreach ($project in $projects) {
        $body = @{
            project_name = $project.ProjectName  # Adjust field names
            description = $project.Description
            # Add more fields as needed
        } | ConvertTo-Json
        
        $uri = "$SupabaseUrl/rest/v1/projects"
        
        try {
            # Try to find existing project
            $existing = Invoke-RestMethod -Uri "$uri?project_name=eq.$($project.ProjectName)" -Method Get -Headers $headers
            
            if ($existing) {
                # Update existing
                $projectId = $existing[0].id
                Invoke-RestMethod -Uri "$uri?id=eq.$projectId" -Method Patch -Headers $headers -Body $body
                Write-Host "  Updated: $($project.ProjectName)" -ForegroundColor Yellow
            } else {
                # Insert new
                Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
                Write-Host "  Inserted: $($project.ProjectName)" -ForegroundColor Green
            }
        } catch {
            Write-Host "  Error with $($project.ProjectName): $_" -ForegroundColor Red
        }
    }
    
    Write-Host "✅ Sync completed!" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
} finally {
    # Cleanup temp file
    if (Test-Path $TempCsvPath) {
        Remove-Item $TempCsvPath
    }
}
