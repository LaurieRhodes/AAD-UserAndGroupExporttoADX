# Application Insights Monitoring Queries

## 📊 **Custom Telemetry Queries for AAD Export**

This document provides KQL queries specifically designed for monitoring the AAD Export to ADX Function App using the enhanced Application Insights integration.

---

## 🎯 **Executive Dashboard Queries**

### **Export Success Rate (Last 30 Days)**

```kusto
traces
| where timestamp > ago(30d)
| where message contains "CUSTOM_TELEMETRY: " and message contains "AADExport"
| extend TelemetryData = parse_json(extract("CUSTOM_TELEMETRY: (.*)", 1, message))
| where TelemetryData.EventName in ("AADExportStarted", "AADExportCompleted", "AADExportFailed")
| summarize 
    Started = countif(TelemetryData.EventName == "AADExportStarted"),
    Completed = countif(TelemetryData.EventName == "AADExportCompleted"),
    Failed = countif(TelemetryData.EventName == "AADExportFailed")
  by bin(timestamp, 1d)
| extend SuccessRate = round((Completed * 100.0) / Started, 2)
| project timestamp, Started, Completed, Failed, SuccessRate
| render timechart with (title="Daily Export Success Rate")
```

### **Performance Trends**

```kusto
traces
| where timestamp > ago(7d)
| where message contains "CUSTOM_TELEMETRY: " and message contains "AADExportCompleted"
| extend TelemetryData = parse_json(extract("CUSTOM_TELEMETRY: (.*)", 1, message))
| extend Properties = TelemetryData.Properties
| project 
    timestamp,
    ExportId = tostring(Properties.ExportId),
    TriggerContext = tostring(Properties.TriggerContext),
    UserCount = toint(Properties.UserCount),
    GroupCount = toint(Properties.GroupCount),
    MembershipCount = toint(Properties.MembershipCount),
    ExecutionTimeMs = toint(Properties.TotalExecutionTimeMs),
    ApiCalls = toint(Properties.ApiCallCount)
| extend ExecutionTimeMinutes = round(ExecutionTimeMs / 60000.0, 2)
| summarize 
    AvgUsers = avg(UserCount),
    AvgGroups = avg(GroupCount), 
    AvgMemberships = avg(MembershipCount),
    AvgExecutionTimeMin = avg(ExecutionTimeMinutes),
    AvgApiCalls = avg(ApiCalls)
  by bin(timestamp, 1d), TriggerContext
| render timechart with (title="Performance Trends by Trigger Type")
```

---

## 🔍 **Error Analysis Queries**

### **Error Breakdown by Type**

```kusto
traces
| where timestamp > ago(7d)
| where message contains "TELEMETRY_EVENT: OperationFailure" or message contains "TELEMETRY_EXCEPTION:"
| extend 
    TelemetryType = case(
        message contains "OperationFailure", "OperationFailure",
        message contains "TELEMETRY_EXCEPTION", "Exception",
        "Unknown"
    )
| extend TelemetryData = case(
    TelemetryType == "OperationFailure", parse_json(extract("OperationFailure\\|(.+)", 1, message)),
    TelemetryType == "Exception", parse_json(extract("TELEMETRY_EXCEPTION: [^|]+\\|[^|]+\\|(.+)", 1, message)),
    dynamic({})
)
| where isnotempty(TelemetryData)
| extend 
    ErrorType = tostring(TelemetryData.ErrorType),
    OperationName = tostring(TelemetryData.OperationName),
    HttpStatusCode = tostring(TelemetryData.HttpStatusCode)
| summarize ErrorCount = count() by ErrorType, OperationName, HttpStatusCode, bin(timestamp, 1h)
| order by timestamp desc, ErrorCount desc
| render columnchart with (title="Error Breakdown by Type and Operation")
```

### **Retry Analysis**

```kusto
traces
| where timestamp > ago(24h)
| where message contains "TELEMETRY_EVENT: OperationRetry"
| extend RetryData = parse_json(extract("OperationRetry\\|(.+)", 1, message))
| extend 
    OperationName = tostring(RetryData.OperationName),
    AttemptNumber = toint(RetryData.AttemptNumber),
    ErrorType = tostring(RetryData.ErrorType),
    DelaySeconds = toint(RetryData.DelaySeconds)
| summarize 
    RetryCount = count(),
    AvgDelay = avg(DelaySeconds),
    MaxAttempt = max(AttemptNumber)
  by OperationName, ErrorType, bin(timestamp, 1h)
| order by timestamp desc, RetryCount desc
| render columnchart with (title="Retry Patterns by Operation and Error Type")
```

---

## ⚡ **Performance Monitoring**

### **Graph API Performance**

```kusto
traces
| where timestamp > ago(24h)
| where message contains "DEPENDENCY_TELEMETRY:"
| extend DependencyData = parse_json(extract("DEPENDENCY_TELEMETRY: (.*)", 1, message))
| where DependencyData.DependencyName == "Microsoft Graph API"
| extend 
    Target = tostring(DependencyData.Target),
    Duration = toint(DependencyData.Duration),
    Success = tobool(DependencyData.Success),
    ApiEndpoint = extract("graph\\.microsoft\\.com/[^/]+/([^?]+)", 1, tostring(DependencyData.Target))
| summarize 
    RequestCount = count(),
    SuccessRate = round(countif(Success) * 100.0 / count(), 2),
    AvgDurationMs = avg(Duration),
    P95DurationMs = percentile(Duration, 95),
    MaxDurationMs = max(Duration)
  by ApiEndpoint, bin(timestamp, 15m)
| order by timestamp desc
| render timechart with (title="Graph API Performance by Endpoint")
```

### **Event Hub Throughput**

```kusto
traces
| where timestamp > ago(24h)
| where message contains "TELEMETRY_EVENT: " and message contains "EventHub"
| extend TelemetryData = parse_json(extract("TELEMETRY_EVENT: [^|]+\\|(.+)", 1, message))
| extend 
    DataType = tostring(TelemetryData.DataType),
    RecordCount = toint(TelemetryData.RecordCount),
    BatchNumber = toint(TelemetryData.BatchNumber)
| summarize 
    TotalBatches = count(),
    TotalRecords = sum(RecordCount),
    AvgBatchSize = avg(RecordCount),
    MaxBatchSize = max(RecordCount)
  by DataType, bin(timestamp, 15m)
| order by timestamp desc
| render timechart with (title="Event Hub Throughput by Data Type")
```

---

## 🚨 **Alert Queries**

### **Function Failures (Alert Rule)**

```kusto
traces
| where timestamp > ago(15m)
| where message contains "CUSTOM_TELEMETRY: " and message contains "AADExportFailed"
| count
```

### **High Error Rate (Alert Rule)**

```kusto
traces
| where timestamp > ago(30m)
| where message contains "TELEMETRY_EVENT: OperationFailure"
| extend TelemetryData = parse_json(extract("OperationFailure\\|(.+)", 1, message))
| summarize ErrorCount = count() by bin(timestamp, 5m)
| where ErrorCount > 5  // Alert if more than 5 errors in 5 minutes
```

### **Long Execution Time (Alert Rule)**

```kusto
traces
| where timestamp > ago(15m)
| where message contains "CUSTOM_TELEMETRY: " and message contains "AADExportCompleted"
| extend TelemetryData = parse_json(extract("CUSTOM_TELEMETRY: (.*)", 1, message))
| extend ExecutionTimeMs = toint(TelemetryData.Properties.TotalExecutionTimeMs)
| where ExecutionTimeMs > 7200000  // Alert if execution > 2 hours
| count
```

---

## 📈 **Business Intelligence Queries**

### **Data Volume Trends**

```kusto
traces
| where timestamp > ago(30d)
| where message contains "CUSTOM_TELEMETRY: " and message contains "AADExportCompleted"
| extend TelemetryData = parse_json(extract("CUSTOM_TELEMETRY: (.*)", 1, message))
| extend Properties = TelemetryData.Properties
| project 
    timestamp,
    UserCount = toint(Properties.UserCount),
    GroupCount = toint(Properties.GroupCount),
    MembershipCount = toint(Properties.MembershipCount)
| summarize 
    AvgUsers = avg(UserCount),
    AvgGroups = avg(GroupCount),
    AvgMemberships = avg(MembershipCount),
    TotalRecords = avg(UserCount + GroupCount + MembershipCount)
  by bin(timestamp, 1d)
| render timechart with (title="Daily Data Volume Trends")
```

### **API Efficiency Analysis**

```kusto
traces
| where timestamp > ago(7d)
| where message contains "CUSTOM_TELEMETRY: " and message contains "AADExportCompleted"
| extend TelemetryData = parse_json(extract("CUSTOM_TELEMETRY: (.*)", 1, message))
| extend 
    Properties = TelemetryData.Properties,
    Metrics = TelemetryData.Metrics
| project 
    timestamp,
    ApiCalls = toint(Properties.ApiCallCount),
    TotalRecords = toint(Properties.UserCount) + toint(Properties.GroupCount) + toint(Properties.MembershipCount),
    RecordsPerMinute = todouble(Metrics.RecordsPerMinute),
    ApiCallsPerMinute = todouble(Metrics.ApiCallsPerMinute)
| summarize 
    AvgRecordsPerApi = avg(TotalRecords / ApiCalls),
    AvgRecordsPerMinute = avg(RecordsPerMinute),
    AvgApiCallsPerMinute = avg(ApiCallsPerMinute)
  by bin(timestamp, 1d)
| render timechart with (title="API Efficiency Metrics")
```

---

## 🔄 **Operational Queries**

### 

### **Current Function Status**

```kusto
traces
| where timestamp > ago(1h)
| where message contains "Function Invoked" or message contains "Export Completed" or message contains "Export Failed"
| extend 
    Status = case(
        message contains "Function Invoked", "Started",
        message contains "Export Completed", "Completed",
        message contains "Export Failed", "Failed",
        "Unknown"
    ),
    TriggerType = case(
        message contains "HTTP", "HTTP",
        message contains "Timer", "Timer",
        "Unknown"
    )
| summarize arg_max(timestamp, Status, TriggerType) by cloud_RoleInstance
| project Instance = cloud_RoleInstance, LastStatus = Status, TriggerType, LastActivity = timestamp
| order by LastActivity desc
```

---

## 🔧 **Troubleshooting Queries**

### **Failed Group Analysis**

```kusto
traces
| where timestamp > ago(24h)
| where message contains "CUSTOM_TELEMETRY: " and message contains "GroupMembershipError"
| extend ErrorData = parse_json(extract("GroupMembershipError\\|(.+)", 1, message))
| extend 
    GroupID = tostring(ErrorData.GroupID),
    ErrorType = tostring(ErrorData.ErrorType),
    ErrorMessage = tostring(ErrorData.ErrorMessage)
| summarize 
    ErrorCount = count(),
    UniqueErrors = dcount(ErrorMessage),
    LatestError = arg_max(timestamp, ErrorMessage)
  by GroupID, ErrorType
| order by ErrorCount desc
| take 20
```

### **Token Refresh Patterns**

```kusto
traces
| where timestamp > ago(24h)
| where message contains "GetGraphToken"
| extend 
    Status = case(
        message contains "completed successfully", "Success",
        message contains "failed", "Failed", 
        "InProgress"
    )
| summarize TokenRequests = count() by Status, bin(timestamp, 1h)
| render timechart with (title="Authentication Token Requests")
```

### **Rate Limiting Detection**

```kusto
traces
| where timestamp > ago(24h)
| where message contains "TELEMETRY_EVENT: OperationRetry"
| extend RetryData = parse_json(extract("OperationRetry\\|(.+)", 1, message))
| where tostring(RetryData.ErrorType) == "RateLimit"
| extend 
    OperationName = tostring(RetryData.OperationName),
    DelaySeconds = toint(RetryData.DelaySeconds)
| summarize 
    RateLimitHits = count(),
    AvgDelay = avg(DelaySeconds),
    MaxDelay = max(DelaySeconds)
  by OperationName, bin(timestamp, 5m)
| render timechart with (title="Graph API Rate Limiting Incidents")
```



## 🔧 **Alert Rule Configuration**

### **Critical Failure Alert**

```kusto
// Alert when any export completely fails
traces
| where timestamp > ago(15m)
| where message contains "CUSTOM_TELEMETRY: " and message contains "AADExportFailed"
| count
// Threshold: > 0
```

### **Performance Degradation Alert**

```kusto
// Alert when execution time exceeds 2 hours
traces
| where timestamp > ago(15m)
| where message contains "CUSTOM_TELEMETRY: " and message contains "AADExportCompleted"
| extend TelemetryData = parse_json(extract("CUSTOM_TELEMETRY: (.*)", 1, message))
| extend ExecutionTimeMs = toint(TelemetryData.Properties.TotalExecutionTimeMs)
| where ExecutionTimeMs > 7200000  // 2 hours in milliseconds
| count
// Threshold: > 0
```

### **High Error Rate Alert**

```kusto
// Alert when error rate exceeds 10% in last 30 minutes
let timeRange = 30m;
let errorThreshold = 10.0;
traces
| where timestamp > ago(timeRange)
| where message contains "TELEMETRY_EVENT: Operation"
| extend 
    IsError = message contains "OperationFailure",
    IsSuccess = message contains "OperationSuccess"
| summarize 
    Total = count(),
    Errors = countif(IsError),
    Successes = countif(IsSuccess)
| extend ErrorRate = round((Errors * 100.0) / Total, 2)
| where ErrorRate > errorThreshold
| project ErrorRate, Errors, Total
```

---

## 📋 **Custom Workbook Queries**

### **Executive Summary Dashboard**

```kusto
// Multi-query workbook combining key metrics
union 
(
    traces
    | where timestamp > ago(7d)
    | where message contains "CUSTOM_TELEMETRY: " and message contains "AADExportCompleted"
    | extend TelemetryData = parse_json(extract("CUSTOM_TELEMETRY: (.*)", 1, message))
    | extend Properties = TelemetryData.Properties
    | summarize 
        TotalExports = count(),
        AvgUsers = avg(toint(Properties.UserCount)),
        AvgGroups = avg(toint(Properties.GroupCount)),
        AvgMemberships = avg(toint(Properties.MembershipCount)),
        AvgDurationMin = avg(toint(Properties.TotalExecutionTimeMs) / 60000.0)
    | extend MetricType = "Summary"
),
(
    exceptions
    | where timestamp > ago(7d)
    | where cloud_RoleName contains "AAD"
    | summarize 
        TotalExceptions = count(),
        UniqueExceptions = dcount(type)
    | extend MetricType = "Errors"
)
```

### **Operational Health Check**

```kusto
// Health status for operational dashboard
let latestExport = traces
| where timestamp > ago(48h)
| where message contains "CUSTOM_TELEMETRY: " and message contains ("AADExportCompleted" or "AADExportFailed")
| extend TelemetryData = parse_json(extract("CUSTOM_TELEMETRY: (.*)", 1, message))
| extend Status = case(
    TelemetryData.EventName == "AADExportCompleted", "Success",
    TelemetryData.EventName == "AADExportFailed", "Failed",
    "Unknown"
)
| summarize arg_max(timestamp, Status, TelemetryData) by TelemetryData.Properties.TriggerContext
| extend HealthStatus = case(
    Status == "Success" and timestamp > ago(25h), "🟢 Healthy",
    Status == "Success" and timestamp > ago(48h), "🟡 Warning", 
    Status == "Failed", "🔴 Critical",
    "🔴 No Data"
);
latestExport
| project TriggerType = TelemetryData_Properties_TriggerContext, HealthStatus, LastRun = timestamp, Status
```

---

## 🔍 **Diagnostic Queries**

### **Correlation Tracking**

```kusto
// Track complete export lifecycle by Export ID
let exportId = "your-export-id-here";  // Replace with actual Export ID
traces
| where timestamp > ago(24h)
| where message contains exportId
| extend 
    EventType = case(
        message contains "AADExportStarted", "🚀 Started",
        message contains "ExportProgress", "⏳ Progress",
        message contains "OperationRetry", "🔄 Retry",
        message contains "OperationFailure", "❌ Error",
        message contains "AADExportCompleted", "✅ Completed",
        message contains "AADExportFailed", "💥 Failed",
        "📝 Info"
    )
| project timestamp, EventType, message
| order by timestamp asc
```

### 

## 📱 **Daily Summary Query (for scheduled reports)**

```kusto
// Daily summary for automated reports
traces
| where timestamp > ago(1d)
| where message contains "CUSTOM_TELEMETRY: " and message contains "AADExportCompleted"
| extend TelemetryData = parse_json(extract("CUSTOM_TELEMETRY: (.*)", 1, message))
| extend Properties = TelemetryData.Properties
| summarize 
    ExportCount = count(),
    TotalUsers = sum(toint(Properties.UserCount)),
    TotalGroups = sum(toint(Properties.GroupCount)),
    TotalMemberships = sum(toint(Properties.MembershipCount)),
    AvgDurationMin = avg(toint(Properties.TotalExecutionTimeMs) / 60000.0),
    MaxDurationMin = max(toint(Properties.TotalExecutionTimeMs) / 60000.0)
| extend 
    Status = case(ExportCount > 0, "✅ Operational", "❌ No Exports"),
    Summary = strcat("Daily AAD Export Summary: ", ExportCount, " exports, ", 
                    TotalUsers, " users, ", TotalGroups, " groups, ", 
                    TotalMemberships, " memberships processed")
| project Status, Summary, ExportCount, TotalUsers, TotalGroups, TotalMemberships, AvgDurationMin, MaxDurationMin
```

---