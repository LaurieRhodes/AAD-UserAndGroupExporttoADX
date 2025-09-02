# Timer Trigger Function Issues and Solutions

## Problems Identified

### 1. Parameter Binding Mismatch
**Issue**: The `function.json` defines the timer parameter as `myTimer`, but `run.ps1` expects `$Timer`.

**Current Configuration:**
```json
{
  "bindings": [
    {
      "name": "myTimer",  // ❌ This doesn't match run.ps1
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 0 1 * * *"
    }
  ]
}
```

**Fix Required**: Update parameter name consistency.

### 2. Missing Timer Information Properties
**Issue**: Timer trigger binding lacks `runOnStartup` and `useMonitor` properties for proper scheduling.

### 3. Quick Failure Pattern
**Issue**: 3-11ms execution time suggests the function is failing before reaching the PowerShell code, likely due to binding issues.

## Solutions

### Solution 1: Fix Parameter Binding

Update `function.json` to match the PowerShell parameter:

```json
{
  "bindings": [
    {
      "name": "Timer",
      "type": "timerTrigger", 
      "direction": "in",
      "schedule": "0 0 1 * * *",
      "runOnStartup": false,
      "useMonitor": true
    }
  ],
  "scriptFile": "run.ps1"
}
```

### Solution 2: Enhanced run.ps1 with Better Error Handling

```powershell
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
```

### Solution 3: Alternative Timer Configuration

If the above doesn't work, try this alternative approach:

```json
{
  "bindings": [
    {
      "name": "myTimer",
      "type": "timerTrigger",
      "direction": "in", 
      "schedule": "0 0 1 * * *",
      "runOnStartup": false,
      "useMonitor": true
    }
  ],
  "scriptFile": "run.ps1"
}
```

And update `run.ps1` first line to:
```powershell
param($myTimer)
```

## Immediate Troubleshooting Steps

### Step 1: Test Timer Binding
Create a minimal test version of `run.ps1`:

```powershell
param($Timer)

Write-Host "=== TIMER BINDING TEST ==="
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Host "Timer parameter received: $($null -ne $Timer)"

if ($Timer) {
    Write-Host "Timer type: $($Timer.GetType().FullName)"
    Write-Host "Timer properties:"
    $Timer | Get-Member -MemberType Properties | ForEach-Object {
        Write-Host "  - $($_.Name): $($Timer.($_.Name))"
    }
} else {
    Write-Error "Timer parameter is NULL - binding configuration issue"
}

Write-Host "Environment variables:"
Write-Host "  - CLIENTID: $($env:CLIENTID -ne $null)"
Write-Host "  - EVENTHUBNAMESPACE: $($env:EVENTHUBNAMESPACE -ne $null)" 
Write-Host "  - EVENTHUBNAME: $($env:EVENTHUBNAME -ne $null)"

Write-Host "Available modules:"
Get-Module | ForEach-Object { Write-Host "  - $($_.Name)" }

Write-Host "=== END TIMER BINDING TEST ==="
```

### Step 2: Check Function App Configuration

Verify in Azure Portal:

1. **Function App → Configuration → Application Settings**
   - Ensure all required environment variables are present
   - Check for any configuration drift

2. **Function App → Functions → TimerTriggerFunction → Integration**
   - Verify timer trigger configuration
   - Check schedule expression: `0 0 1 * * *` (daily at 1 AM UTC)

3. **Function App → Functions → TimerTriggerFunction → Monitor**
   - Check for more detailed error messages
   - Look for invocation history patterns

### Step 3: Verify Schedule Expression

The current schedule `0 0 1 * * *` means:
- **Second**: 0
- **Minute**: 0  
- **Hour**: 1 (1 AM UTC)
- **Day**: * (every day)
- **Month**: * (every month)
- **DayOfWeek**: * (every day of week)

For testing, consider using `0 */5 * * * *` (every 5 minutes) temporarily.

### Step 4: Check Function App Logs

Enable detailed logging in `host.json`:

```json
{
  "version": "2.0",
  "logging": {
    "logLevel": {
      "default": "Information",
      "Function.TimerTriggerFunction": "Information", 
      "Host": "Information"
    },
    "applicationInsights": {
      "enableLiveMetricsFilters": true
    }
  }
}
```

## Root Cause Analysis

Based on the 3-11ms execution time, the most likely causes are:

### 1. Binding Configuration Mismatch ⭐ Most Likely
The parameter name mismatch between `function.json` (`myTimer`) and `run.ps1` (`$Timer`) is preventing proper binding initialization.

### 2. PowerShell Execution Policy
Check if execution policy is blocking script execution in the Function App environment.

### 3. Module Loading Failure
The profile.ps1 module loading may be failing silently in timer context but working in HTTP context.

## Quick Fix Implementation

### Immediate Fix (Choose Option A or B):

**Option A**: Update `function.json` to match `run.ps1`:
```json
{
  "bindings": [
    {
      "name": "Timer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 0 1 * * *",
      "runOnStartup": false,
      "useMonitor": true
    }
  ],
  "scriptFile": "run.ps1"
}
```

**Option B**: Update `run.ps1` to match `function.json`:
```powershell
param($myTimer)
# Then use $myTimer throughout the script instead of $Timer
```

### Test Immediately After Fix:
1. Deploy the corrected configuration
2. Manually trigger the timer function in Azure Portal
3. Check logs for detailed execution information
4. If successful, wait for next scheduled execution

The parameter binding mismatch is almost certainly the root cause of the immediate failure pattern you're seeing.
