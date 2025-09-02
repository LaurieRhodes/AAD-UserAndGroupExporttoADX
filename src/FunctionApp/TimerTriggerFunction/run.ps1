param($Timer)

# Enhanced logging and diagnostics
$DebugPreference = "Continue"
$InformationPreference = "Continue"
$VerbosePreference = "Continue"

Write-Host "=========================================="
Write-Host "Timer Trigger Function Started"
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Host "Execution Policy: $(Get-ExecutionPolicy)"
Write-Host "Current Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"

# Validate Timer object
if ($null -eq $Timer) {
    Write-Error "CRITICAL: Timer parameter is null - binding configuration problem"
    throw "Timer binding failed - check function.json configuration"
}

Write-Host "Timer Object Type: $($Timer.GetType().FullName)"
Write-Host "Timer Properties Available: $($Timer | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name)"

# Safe property access with null checking
$scheduledTime = if ($Timer.PSObject.Properties['ScheduledTime']) { $Timer.ScheduledTime } else { "Not Available" }
$isPastDue = if ($Timer.PSObject.Properties['IsPastDue']) { $Timer.IsPastDue } else { "Not Available" }

Write-Host "Scheduled Time: $scheduledTime"
Write-Host "Is Past Due: $isPastDue"
Write-Host "=========================================="

try {
    # Module availability check with detailed diagnostics
    Write-Host "Checking module availability..."
    
    $aadExportCommand = Get-Command -Name "Invoke-AADDataExport" -ErrorAction SilentlyContinue
    if (-not $aadExportCommand) {
        Write-Error "CRITICAL: AADExporter module not properly loaded"
        Write-Host "Available modules:"
        Get-Module | ForEach-Object { Write-Host "  - $($_.Name) ($($_.Version))" }
        
        Write-Host "Available commands containing 'AAD':"
        Get-Command -Name "*AAD*" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  - $($_.Name)" }
        
        throw "AADExporter module not properly loaded - Invoke-AADDataExport function not available"
    }

    Write-Host "✅ AADExporter module verified - Invoke-AADDataExport available"
    Write-Host "Starting scheduled AAD data export..."
    
    # Execute with comprehensive error handling
    $exportResult = Invoke-AADDataExport -TriggerContext "TimerTrigger" -IncludeExtendedUserProperties:$false
    
    if ($exportResult -and $exportResult.Success) {
        Write-Host "✅ Timer Trigger completed successfully"
        Write-Host "Export Statistics:"
        Write-Host "  - Export ID: $($exportResult.ExportId)"
        Write-Host "  - Users: $($exportResult.Statistics.Users)"
        Write-Host "  - Groups: $($exportResult.Statistics.Groups)" 
        Write-Host "  - Memberships: $($exportResult.Statistics.Memberships)"
        Write-Host "  - Total Records: $($exportResult.Statistics.TotalRecords)"
        Write-Host "  - Duration: $([Math]::Round($exportResult.Statistics.Duration, 2)) minutes"
        Write-Host "  - Event Hub Batches: $($exportResult.Statistics.EventHubBatches)"
        
        if ($scheduledTime -ne "Not Available") {
            Write-Host "Next scheduled run: $(([DateTime]$scheduledTime).AddDays(1))"
        }
        
    } else {
        $errorMessage = "Timer Trigger failed"
        if ($exportResult -and $exportResult.ExportId) {
            $errorMessage += " - Export ID: $($exportResult.ExportId)"
        }
        
        Write-Error $errorMessage
        
        if ($exportResult -and $exportResult.Error) {
            Write-Error "Error Type: $($exportResult.Error.ErrorType)"
            Write-Error "Error Message: $($exportResult.Error.ErrorMessage)"
            throw "AAD Data Export failed during scheduled execution: $($exportResult.Error.ErrorMessage)"
        } else {
            throw "AAD Data Export returned unsuccessful result with no error details"
        }
    }
    
} catch {
    Write-Error "❌ CRITICAL ERROR in Timer Trigger execution"
    Write-Error "Exception Type: $($_.Exception.GetType().FullName)"
    Write-Error "Exception Message: $($_.Exception.Message)"
    
    if ($_.Exception.InnerException) {
        Write-Error "Inner Exception: $($_.Exception.InnerException.Message)"
    }
    
    Write-Error "Stack Trace: $($_.ScriptStackTrace)"
    
    # Re-throw to ensure function shows as failed in Azure monitoring
    throw $_
}

Write-Host "Timer Trigger Function execution completed"