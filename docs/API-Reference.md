# API Reference Documentation

## 📚 **Function App API Reference**

This document provides detailed API documentation for all functions and modules in the AAD Export to ADX solution.

---

## 🎯 **Core Export Functions**

### **Invoke-AADDataExport**

The primary business logic function that orchestrates the complete Azure AD data export process.

#### **Syntax**

```powershell
Invoke-AADDataExport [-TriggerContext <String>]
```

#### **Parameters**

| Parameter        | Type   | Required | Description                                                                    |
| ---------------- | ------ | -------- | ------------------------------------------------------------------------------ |
| `TriggerContext` | String | No       | Context information from calling trigger ("TimerTrigger", "HTTPTrigger", etc.) |

#### **Return Value**

Returns a hashtable with the following structure:

```powershell
@{
    Success = $true/$false                    # Boolean indicating export success
    ExportId = "guid-string"                  # Unique identifier for correlation
    Statistics = @{                           # Performance and volume metrics
        Users = 1234                          # Total users processed
        Groups = 567                          # Total groups processed  
        Memberships = 8901                    # Total memberships processed
        ApiCalls = 234                        # Total Graph API calls made
        EventHubBatches = 45                  # Total Event Hub batches sent
        Duration = 23.5                       # Total execution time (minutes)
        GroupSuccessRate = 98.5               # Percentage of groups processed successfully
        FailedGroups = 12                     # Number of groups that failed processing
        Performance = @{                      # Performance metrics
            ExecutionDurationMinutes = 23.5
            RecordsPerMinute = 456
            ApiCallsPerMinute = 10.2
        }
    }
    StartTime = [DateTime]                    # Export start timestamp
    EndTime = [DateTime]                      # Export completion timestamp
    Error = @{                                # Error details (if Success = $false)
        ExportId = "guid-string"
        TriggerContext = "context"
        ErrorMessage = "error description"
        ErrorType = "error classification"
        HttpStatusCode = 401
        Timestamp = "iso-datetime"
        PartialStatistics = @{}               # Statistics collected before failure
    }
}
```

#### **Examples**

```powershell
# Basic usage
$result = Invoke-AADDataExport

# With trigger context
$result = Invoke-AADDataExport -TriggerContext "TimerTrigger"

# Check results
if ($result.Success) {
    Write-Host "Export completed: $($result.Statistics.Users) users, $($result.Statistics.Groups) groups"
} else {
    Write-Error "Export failed: $($result.Error.ErrorMessage)"
}
```

---

## 🔐 **Authentication Functions**

### **Get-AzureADToken**

Acquires access tokens using managed identity for Azure resource access.

#### **Syntax**

```powershell
Get-AzureADToken -resource <String> -clientId <String> [-apiVersion <String>]
```

#### **Parameters**

| Parameter    | Type   | Required | Description                                               |
| ------------ | ------ | -------- | --------------------------------------------------------- |
| `resource`   | String | Yes      | Target resource URI (e.g., "https://graph.microsoft.com") |
| `clientId`   | String | Yes      | Managed identity client ID                                |
| `apiVersion` | String | No       | Azure Identity API version (default: "2019-08-01")        |

#### **Return Value**

Returns the access token as a string, or throws an exception on failure.

#### **Examples**

```powershell
# Get Graph API token
$token = Get-AzureADToken -resource "https://graph.microsoft.com" -clientId $env:CLIENTID

# Get Event Hub token
$ehToken = Get-AzureADToken -resource "https://eventhubs.azure.net" -clientId $env:CLIENTID
```

---

## 📡 **Event Hub Functions**

### **Send-EventsToEventHub**

Sends JSON payload to Event Hub with automatic chunking for 1MB payload limit compliance.

#### **Syntax**

```powershell
Send-EventsToEventHub -Payload <String>
```

#### **Parameters**

| Parameter | Type   | Required | Description                                      |
| --------- | ------ | -------- | ------------------------------------------------ |
| `Payload` | String | Yes      | JSON string containing data to send to Event Hub |

#### **Behavior**

- Automatically chunks payloads exceeding 900KB
- Acquires Event Hub access token using managed identity
- Handles PowerShell Core vs Windows PowerShell differences
- Supports retry logic when used with `Invoke-WithRetry`

#### **Examples**

```powershell
# Send user data
$userData = @(@{OdataContext="users"; Data=@{id="123"; displayName="John Doe"}})
Send-EventsToEventHub -Payload (ConvertTo-Json -InputObject $userData -Depth 50)

# Large dataset (automatically chunked)
Send-EventsToEventHub -Payload (ConvertTo-Json -InputObject $largeDataArray -Depth 50)
```

---

## 🔄 **Error Handling Functions**

### **Invoke-WithRetry**

Executes script blocks with intelligent retry logic and comprehensive telemetry.

#### **Syntax**

```powershell
Invoke-WithRetry -ScriptBlock <ScriptBlock> [-MaxRetryCount <Int>] [-InitialDelaySeconds <Int>] [-OperationName <String>] [-TelemetryProperties <Hashtable>]
```

#### **Parameters**

| Parameter             | Type        | Required | Description                                         |
| --------------------- | ----------- | -------- | --------------------------------------------------- |
| `ScriptBlock`         | ScriptBlock | Yes      | Code to execute with retry logic                    |
| `MaxRetryCount`       | Int         | No       | Maximum retry attempts (default: 3)                 |
| `InitialDelaySeconds` | Int         | No       | Base delay for exponential backoff (default: 2)     |
| `OperationName`       | String      | No       | Name for telemetry correlation (default: "Unknown") |
| `TelemetryProperties` | Hashtable   | No       | Additional properties for telemetry events          |

#### **Retry Strategy**

- **Exponential Backoff**: Delay = min(2^attempt * InitialDelay, 60 seconds)
- **Jitter**: Random delay variation to prevent thundering herd
- **Error Classification**: Smart retry decisions based on error type
- **Circuit Breaking**: Fast failure for non-retryable errors

#### **Examples**

```powershell
# Basic retry
$result = Invoke-WithRetry -ScriptBlock { 
    Invoke-RestMethod -Uri "https://api.example.com/data" -Method GET 
} -OperationName "GetExternalData"

# Advanced retry with custom properties
$telemetryProps = @{ 'DataSource' = 'GraphAPI'; 'Endpoint' = 'Users' }
$users = Invoke-WithRetry -ScriptBlock {
    Invoke-RestMethod -Uri $usersUrl -Headers $authHeader -Method GET
} -MaxRetryCount 5 -OperationName "GetGraphUsers" -TelemetryProperties $telemetryProps
```

### **Invoke-GraphAPIWithRetry**

Specialized retry function for Microsoft Graph API calls with dependency tracking.

#### **Syntax**

```powershell
Invoke-GraphAPIWithRetry -Uri <String> -Headers <Hashtable> [-Method <String>] [-CorrelationContext <Hashtable>] [-MaxRetryCount <Int>]
```

#### **Parameters**

| Parameter            | Type      | Required | Description                          |
| -------------------- | --------- | -------- | ------------------------------------ |
| `Uri`                | String    | Yes      | Graph API endpoint URL               |
| `Headers`            | Hashtable | Yes      | HTTP headers including authorization |
| `Method`             | String    | No       | HTTP method (default: "GET")         |
| `CorrelationContext` | Hashtable | No       | Context for telemetry correlation    |
| `MaxRetryCount`      | Int       | No       | Maximum retry attempts (default: 3)  |

#### **Features**

- Automatic dependency telemetry for Application Insights
- Performance timing and latency tracking
- Graph API specific error handling
- Rate limiting detection and backoff

---

## 📊 **Telemetry Functions**

### **Write-CustomTelemetry**

Writes structured custom telemetry events to Application Insights.

#### **Syntax**

```powershell
Write-CustomTelemetry -EventName <String> [-Properties <Hashtable>] [-Metrics <Hashtable>]
```

#### **Parameters**

| Parameter    | Type      | Required | Description                                     |
| ------------ | --------- | -------- | ----------------------------------------------- |
| `EventName`  | String    | Yes      | Name of the custom event                        |
| `Properties` | Hashtable | No       | String properties for filtering and correlation |
| `Metrics`    | Hashtable | No       | Numeric metrics for aggregation and alerting    |

#### **Examples**

```powershell
# Simple event
Write-CustomTelemetry -EventName "DataProcessingComplete"

# Event with properties and metrics
$props = @{ 'DataSource' = 'GraphAPI'; 'ProcessingStage' = 'Users' }
$metrics = @{ 'RecordCount' = 1234; 'ProcessingTimeMs' = 5678 }
Write-CustomTelemetry -EventName "StageCompleted" -Properties $props -Metrics $metrics
```

### **Write-DependencyTelemetry**

Logs dependency calls for external service monitoring.

#### **Syntax**

```powershell
Write-DependencyTelemetry -DependencyName <String> -Target <String> -DurationMs <Long> -Success <Boolean> [-Properties <Hashtable>]
```

#### **Parameters**

| Parameter        | Type      | Required | Description                    |
| ---------------- | --------- | -------- | ------------------------------ |
| `DependencyName` | String    | Yes      | Name of the dependency service |
| `Target`         | String    | Yes      | Target endpoint or resource    |
| `DurationMs`     | Long      | Yes      | Call duration in milliseconds  |
| `Success`        | Boolean   | Yes      | Whether the call succeeded     |
| `Properties`     | Hashtable | No       | Additional context properties  |

### **Write-ExportProgress**

Logs progress updates during long-running export operations.

#### **Syntax**

```powershell
Write-ExportProgress -Stage <String> -ProcessedCount <Int> [-TotalCount <Int>] [-CorrelationContext <Hashtable>]
```

---

## 🔍 **Utility Functions**

### **Get-ErrorType**

Classifies exceptions into specific error types for intelligent retry decisions.

#### **Syntax**

```powershell
Get-ErrorType -Exception <Exception>
```

#### **Return Values**

| Error Type       | Description                 | Retry Recommended             |
| ---------------- | --------------------------- | ----------------------------- |
| `Authentication` | 401 Unauthorized            | No - needs new token          |
| `Authorization`  | 403 Forbidden               | No - insufficient permissions |
| `RateLimit`      | 429 Too Many Requests       | Yes - with backoff            |
| `ServerError`    | 500 Internal Server Error   | Yes                           |
| `Timeout`        | Request timeout             | Yes                           |
| `Network`        | Network connectivity issues | Yes                           |
| `Unknown`        | Unclassified errors         | Yes (conservative)            |

### **Test-ShouldRetry**

Determines whether an operation should be retried based on error type and context.

#### **Syntax**

```powershell
Test-ShouldRetry -Exception <Exception> -ErrorType <String>
```

#### **Logic**

- **Always Retry**: Rate limits, server errors, timeouts, network issues
- **Never Retry**: Authentication failures, authorization errors
- **Conservative Default**: Unknown errors are retried

### **New-CorrelationContext**

Creates correlation context for tracking operations across telemetry events.

#### **Syntax**

```powershell
New-CorrelationContext [-OperationId <String>] [-OperationName <String>]
```

#### **Return Value**

```powershell
@{
    OperationId = "guid-string"      # Unique operation identifier
    OperationName = "AADDataExport"  # Operation name for grouping
    ParentId = $null                 # Parent operation (for nested operations)
    StartTime = [DateTime]           # Operation start time
}
```

---

## 🌐 **HTTP Trigger API**

### **Endpoint**: `/api/HttpTriggerFunction`

Manual trigger endpoint for development, testing, and emergency exports.

#### **HTTP Methods**

- `GET` - Triggers export and returns status
- `POST` - Triggers export and returns detailed response

#### **Authentication**

- **Type**: Function key authentication
- **Header**: `x-functions-key: your-function-key`
- **URL Parameter**: `?code=your-function-key`

#### **Request Format**

```http
POST /api/HttpTriggerFunction?code=your-function-key HTTP/1.1
Host: your-function-app.azurewebsites.net
Content-Type: application/json

{
    "requestedBy": "admin@contoso.com",
    "reason": "Manual data refresh"
}
```

#### **Response Format**

**Success Response (202 Accepted)**

```json
{
    "status": "success",
    "message": "AAD data export completed successfully", 
    "requestId": "guid-string",
    "exportId": "guid-string",
    "statistics": {
        "Users": 1234,
        "Groups": 567,
        "Memberships": 8901,
        "ApiCalls": 234,
        "EventHubBatches": 45,
        "Duration": 23.5,
        "GroupSuccessRate": 98.5,
        "FailedGroups": 12,
        "Performance": {
            "ExecutionDurationMinutes": 23.5,
            "RecordsPerMinute": 456,
            "ApiCallsPerMinute": 10.2
        }
    },
    "execution": {
        "startTime": "2025-08-31T01:00:00Z",
        "endTime": "2025-08-31T01:23:30Z", 
        "durationMinutes": 23.5
    },
    "nextScheduledRun": "Daily at 01:00 UTC"
}
```

**Error Response (500 Internal Server Error)**

```json
{
    "status": "error",
    "message": "AAD data export failed",
    "requestId": "guid-string",
    "exportId": "guid-string", 
    "error": {
        "message": "Failed to acquire Graph API token",
        "timestamp": "2025-08-31T01:05:00Z"
    },
    "supportInfo": "Check Application Insights for detailed error information"
}
```

**Method Not Allowed (405)**

```json
{
    "error": "Method Not Allowed",
    "message": "Only GET and POST methods are supported",
    "requestId": "guid-string"
}
```

---

## ⏰ **Timer Trigger Configuration**

### **Schedule Format**

The timer trigger uses CRON expressions with Azure Functions specific format:

```
{second} {minute} {hour} {day} {month} {day-of-week}
```

#### **Current Configuration**

```json
{
    "schedule": "0 0 1 * * *"
}
```

- **Translation**: Daily at 1:00 AM UTC
- **Next Runs**: 01:00:00 UTC every day

#### **Alternative Schedules**

| Schedule      | Description              | CRON Expression  |
| ------------- | ------------------------ | ---------------- |
| Daily at 2 AM | Every day at 2:00 AM UTC | `0 0 2 * * *`    |
| Twice daily   | 6 AM and 6 PM UTC        | `0 0 6,18 * * *` |
| Weekdays only | Monday-Friday at 1 AM    | `0 0 1 * * 1-5`  |
| Weekly        | Sundays at 1 AM          | `0 0 1 * * 0`    |

---

## 🛠️ **Error Handling API**

### **Error Classification System**

The solution uses a structured error classification system for intelligent retry decisions:

#### **Error Types**

| Type             | HTTP Codes        | Retry Strategy        | Description              |
| ---------------- | ----------------- | --------------------- | ------------------------ |
| `Authentication` | 401               | ❌ No Retry            | Token expired or invalid |
| `Authorization`  | 403               | ❌ No Retry            | Insufficient permissions |
| `RateLimit`      | 429               | ✅ Exponential Backoff | API quota exceeded       |
| `ServerError`    | 500, 502, 503     | ✅ Linear Backoff      | Temporary server issues  |
| `Timeout`        | 504, timeout      | ✅ Immediate Retry     | Request timeout          |
| `Network`        | Connection errors | ✅ Linear Backoff      | Network connectivity     |
| `Unknown`        | Other             | ✅ Conservative Retry  | Unclassified errors      |

#### **Retry Configuration**

| Error Type    | Max Retries | Initial Delay | Backoff Strategy                |
| ------------- | ----------- | ------------- | ------------------------------- |
| `RateLimit`   | 5           | 2s            | Exponential (2^n * 2s, max 60s) |
| `ServerError` | 3           | 2s            | Linear (2s, 4s, 6s)             |
| `Timeout`     | 2           | 1s            | Immediate (1s, 2s)              |
| `Network`     | 3           | 3s            | Linear (3s, 6s, 9s)             |

---

## 📊 **Telemetry Events Reference**

### **Standard Telemetry Events**

#### **AADExportStarted**

Logged when export operation begins.

**Properties:**

```json
{
    "ExportId": "guid-string",
    "TriggerContext": "TimerTrigger|HTTPTrigger", 
    "FunctionVersion": "2.0",
    "PowerShellVersion": "7.4.x"
}
```

#### **AADExportCompleted**

Logged when export completes successfully.

**Properties:**

```json
{
    "ExportId": "guid-string",
    "TriggerContext": "TimerTrigger|HTTPTrigger",
    "UserCount": 1234,
    "GroupCount": 567,
    "MembershipCount": 8901,
    "ApiCallCount": 234,
    "EventHubBatchCount": 45,
    "TotalExecutionTimeMs": 1410000,
    "GroupSuccessRate": 98.5,
    "FailedGroupCount": 12
}
```

**Metrics:**

```json
{
    "ExecutionDurationMinutes": 23.5,
    "RecordsPerMinute": 456,
    "ApiCallsPerMinute": 10.2
}
```

#### **ExportProgress**

Logged periodically during processing stages.

**Properties:**

```json
{
    "ExportId": "guid-string",
    "Stage": "Users|Groups|GroupMemberships",
    "ProcessedCount": 1000,
    "TotalCount": 5000,
    "PercentComplete": 20.0
}
```

### **Error Telemetry Events**

#### **OperationRetry**

Logged when operations are retried due to errors.

**Properties:**

```json
{
    "OperationName": "GraphAPI-users",
    "AttemptNumber": 2,
    "ErrorType": "RateLimit",
    "ErrorMessage": "Too many requests",
    "HttpStatusCode": "429",
    "ShouldRetry": true,
    "DelaySeconds": 4,
    "DurationMs": 1500
}
```

#### **OperationFailure**

Logged when operations fail permanently.

**Properties:**

```json
{
    "OperationName": "GraphAPI-users",
    "ErrorType": "Authentication", 
    "ErrorMessage": "Invalid authentication token",
    "HttpStatusCode": "401",
    "AttemptsRequired": 3,
    "DurationMs": 2100
}
```

#### **GroupMembershipError**

Logged when individual group processing fails.

**Properties:**

```json
{
    "ExportId": "guid-string",
    "GroupID": "group-guid",
    "ErrorMessage": "Group not found",
    "ErrorType": "NotFound",
    "HttpStatusCode": "404"
}
```

---

## 🔧 **Configuration Reference**

### **Required Environment Variables**

| Variable                                | Example Value                                  | Description                     |
| --------------------------------------- | ---------------------------------------------- | ------------------------------- |
| `CLIENTID`                              | `12345678-1234-1234-1234-123456789012`         | Managed identity client ID      |
| `EVENTHUBNAMESPACE`                     | `eh-aad-export-prod`                           | Event Hub namespace name        |
| `EVENTHUB`                              | `aad-data`                                     | Event Hub name                  |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | `InstrumentationKey=...;IngestionEndpoint=...` | Application Insights connection |

### **Function App Settings**

| Setting                            | Value                       | Purpose                   |
| ---------------------------------- | --------------------------- | ------------------------- |
| `FUNCTIONS_WORKER_RUNTIME`         | `powershell`                | PowerShell runtime        |
| `FUNCTIONS_EXTENSION_VERSION`      | `~4`                        | Functions runtime version |
| `FUNCTIONS_WORKER_RUNTIME_VERSION` | `~7.4`                      | PowerShell version        |
| `WEBSITE_TIME_ZONE`                | `AUS Eastern Standard Time` | Function timezone         |

### **Host.json Configuration**

```json
{
  "version": "2.0",
  "functionTimeout": "04:00:00",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "maxTelemetryItemsPerSecond": 10,
        "excludedTypes": "Request"
      },
      "enableLiveMetricsFilters": true,
      "httpAutoCollectionOptions": {
        "enableHttpTriggerExtendedInfoCollection": true,
        "enableW3CDistributedTracing": true
      }
    },
    "logLevel": {
      "Function": "Information",
      "Host.Results": "Information", 
      "Host.Aggregator": "Trace"
    }
  },
  "retry": {
    "strategy": "exponentialBackoff",
    "maxRetryCount": 3,
    "minimumInterval": "00:00:02",
    "maximumInterval": "00:00:30"
  }
}
```

---

## 📈 **Performance Characteristics**

### **Execution Time Expectations**

| Tenant Size    | Users         | Groups      | Typical Duration | Memory Usage |
| -------------- | ------------- | ----------- | ---------------- | ------------ |
| **Small**      | <1,000        | <100        | 2-5 minutes      | 50-100 MB    |
| **Medium**     | 1,000-10,000  | 100-1,000   | 10-30 minutes    | 200-500 MB   |
| **Large**      | 10,000-50,000 | 1,000-5,000 | 30-120 minutes   | 500-1000 MB  |
| **Enterprise** | 50,000+       | 5,000+      | 2-4 hours        | 1-1.5 GB     |

### **API Rate Limits**

| Endpoint               | Limit                | Strategy                         |
| ---------------------- | -------------------- | -------------------------------- |
| `/users`               | 1000 requests/minute | Pagination with 999 records/page |
| `/groups`              | 1000 requests/minute | Pagination with 999 records/page |
| `/groups/{id}/members` | 500 requests/minute  | 2-second delays between calls    |

### **Event Hub Batching**

| Data Type         | Batch Size        | Frequency         | Payload Limit |
| ----------------- | ----------------- | ----------------- | ------------- |
| **Users**         | ~500-1000 records | Per API page      | <900KB        |
| **Groups**        | ~500-1000 records | Per API page      | <900KB        |
| **Group Members** | ~2000 records     | Accumulated batch | <900KB        |

---

## 🔍 **Monitoring & Alerting API**

### **Health Check Endpoints**

While not exposed as HTTP endpoints, health status can be monitored via Application Insights:

#### **Function Health Query**

```kusto
traces
| where timestamp > ago(15m)
| where message contains "Function Invoked" or message contains "AADExportCompleted" or message contains "AADExportFailed"
| summarize 
    LastActivity = max(timestamp),
    RecentExecutions = count(),
    LastStatus = arg_max(timestamp, case(
        message contains "AADExportCompleted", "Healthy",
        message contains "AADExportFailed", "Failed", 
        "InProgress"
    ))
| extend HealthStatus = case(
    LastStatus == "Healthy" and LastActivity > ago(25h), "🟢 Healthy",
    LastStatus == "Failed", "🔴 Critical",
    LastActivity < ago(25h), "🟡 Stale",
    "🔵 Running"
)
```

### **Alert Integration**

The solution supports Azure Monitor alerts based on Application Insights data:

#### **Critical Alerts**

- Export failure: Any `AADExportFailed` event
- Authentication failure: Multiple authentication errors in 15 minutes
- Long execution: Execution time >2 hours

#### **Warning Alerts**

- High retry rate: >10 retries in 30 minutes
- Partial data loss: Group success rate <95%
- Performance degradation: Execution time >1.5x baseline

---

## 🧪 **Testing API**

### **HTTP Trigger Testing**

#### **Basic Test**

```powershell
# Test function accessibility
$functionKey = "your-function-key"
$testUrl = "https://your-function-app.azurewebsites.net/api/HttpTriggerFunction?code=$functionKey"

try {
    $response = Invoke-RestMethod -Uri $testUrl -Method GET -TimeoutSec 300
    Write-Host "✅ Function accessible: $($response.status)" -ForegroundColor Green
} catch {
    Write-Error "❌ Function test failed: $_"
}
```

#### **Full Export Test**

```powershell
# Execute complete export and monitor
$response = Invoke-RestMethod -Uri $testUrl -Method POST -TimeoutSec 1800  # 30 minute timeout

if ($response.status -eq "success") {
    Write-Host "✅ Export completed successfully" -ForegroundColor Green
    Write-Host "Statistics: $($response.statistics | ConvertTo-Json)"
} else {
    Write-Error "❌ Export failed: $($response.error.message)"
}
```

### **Timer Trigger Validation**

#### **Schedule Verification**

```bash
# Verify timer configuration
az functionapp function show \
  --resource-group "your-rg" \
  --name "your-function-app" \
  --function-name "TimerTriggerFunction" \
  --query "config.bindings[0].schedule" -o tsv

# Expected output: "0 0 1 * * *"
```

#### **Next Execution Check**

```kusto
// Check next scheduled execution
traces
| where timestamp > ago(24h)
| where message contains "Next Schedule:"
| extend NextSchedule = extract("Next Schedule: ([^\\r\\n]+)", 1, message)
| project timestamp, NextSchedule
| order by timestamp desc
| take 1
```

---

## 📋 **Integration Reference**

### **Azure Data Explorer (ADX) Schema**

The exported data creates the following table structure in ADX:

#### **Users Table**

```kusto
.create table Users (
    OdataContext: string,
    ExportId: string,
    ExportTimestamp: datetime,
    Data: dynamic
)
```

#### **Groups Table**

```kusto
.create table Groups (
    OdataContext: string,
    ExportId: string, 
    ExportTimestamp: datetime,
    Data: dynamic
)
```

#### **GroupMembers Table**

```kusto
.create table GroupMembers (
    OdataContext: string,
    ExportId: string,
    ExportTimestamp: datetime,
    GroupID: string,
    Data: string
)
```

### **Event Hub Message Format**

#### **Standard Message Structure**

```json
{
    "OdataContext": "users|groups|GroupMembers",
    "ExportId": "correlation-guid",
    "ExportTimestamp": "2025-08-31T01:00:00.000Z",
    "GroupID": "group-guid-if-applicable",
    "Data": {
        // Microsoft Graph API response object
    }
}
```

#### **Batch Message Structure**

Event Hub receives arrays of the above message structure, automatically chunked to respect the 1MB payload limit:

```json
[
    { /* Message 1 */ },
    { /* Message 2 */ },
    { /* ... */ },
    { /* Message N */ }
]
```

---

## 🔒 **Security Reference**

### **Required Microsoft Graph Permissions**

| Permission          | Type        | Justification                              |
| ------------------- | ----------- | ------------------------------------------ |
| `User.Read.All`     | Application | Read all user profile information          |
| `Group.Read.All`    | Application | Read all group properties and memberships  |
| `AuditLog.Read.All` | Application | Optional - for enhanced audit capabilities |

### **Managed Identity Configuration**

#### **Required Role Assignments**

- **Microsoft Graph**: Application permissions (see above)
- **Event Hub**: `Azure Event Hubs Data Sender` role
- **Application Insights**: Built-in integration (no additional roles)

#### **Security Best Practices**

- No stored credentials or connection strings in code
- Managed identity authentication throughout
- HTTPS-only communication
- Minimal required permissions principle
- Regular permission auditing

---

*This API reference provides complete documentation for developers, operators, and future AI sessions working with the AAD Export solution.*