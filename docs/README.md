# AAD User and Group Export to ADX - Technical Specification

Version 1.0  
Last Modified: 2025-10-01

## 1. Overview

This specification defines the Azure AD data export system that extracts user, group, and membership data from Microsoft Graph API and streams it to Azure Data Explorer via Event Hub.

### 1.1 Purpose

The system provides automated extraction of Azure AD identity data for analytics and compliance purposes.

### 1.2 Scope

- Azure AD user data retrieval with comprehensive property coverage
- Azure AD group enumeration and metadata
- Group membership relationship mapping
- Event-driven data streaming to Event Hub
- Scheduled and on-demand execution models

## 2. Architecture

### 2.1 Components

| Component            | Type                   | Purpose                                     |
| -------------------- | ---------------------- | ------------------------------------------- |
| Function App         | Azure Functions v4     | Serverless execution runtime                |
| AADExporter Module   | PowerShell Module      | Core export logic and Graph API integration |
| Timer Trigger        | CRON Trigger           | Scheduled daily execution at 01:00 UTC      |
| HTTP Trigger         | HTTP Endpoint          | Manual execution and testing                |
| Managed Identity     | User-Assigned Identity | Password-less authentication                |
| Event Hub            | Event Hub Namespace    | Data streaming to ADX                       |
| Application Insights | Monitoring             | Telemetry and diagnostics                   |

### 2.2 Execution Flow

```
Timer/HTTP Trigger
    ↓
Invoke-AADDataExport
    ↓
    ├─→ Initialize-GraphAuthentication
    │       ↓
    │   Get-AzureADToken (Managed Identity)
    │
    ├─→ Export-AADUsers
    │       ↓
    │   Multiple Graph API calls for comprehensive properties
    │       ↓
    │   Send-EventsToEventHub
    │
    ├─→ Export-AADGroups
    │       ↓
    │   Graph API paginated retrieval
    │       ↓
    │   Send-EventsToEventHub
    │
    └─→ Export-AADGroupMemberships
            ↓
        Parallel membership queries per group
            ↓
        Send-EventsToEventHub
```

### 2.3 Data Flow

1. Function trigger initiates export
2. Managed identity acquires OAuth2 token from Azure AD
3. Graph API queries execute with pagination
4. Data transforms to Event Hub schema
5. Chunked payload transmission to Event Hub
6. Event Hub streams to ADX ingestion pipeline

## 3. Authentication

### 3.1 Managed Identity Requirements

The user-assigned managed identity requires these Microsoft Graph application permissions:

- `User.Read.All` - Read all user profiles
- `Group.Read.All` - Read all groups
- `GroupMember.Read.All` - Read group memberships

### 3.2 Event Hub Authorisation

The managed identity requires:

- `Azure Event Hubs Data Sender` role on the Event Hub namespace

### 3.3 Token Acquisition

```powershell
Get-AzureADToken -resource "https://graph.microsoft.com" -clientId $env:CLIENTID
```

Tokens are acquired per-request using the Azure Instance Metadata Service (IMDS) endpoint.

## 4. Data Export Operations

### 4.1 User Export

#### 4.1.1 Basic Properties Export

Endpoint: `https://graph.microsoft.com/v1.0/users`

Query parameters:

- `$select`: Basic properties (accountEnabled, displayName, userPrincipalName, etc.)
- `$top`: 999 (maximum page size)

#### 4.1.2 Enhanced Properties Export

Multiple API calls retrieve property groups:

1. Identity and security properties (createdDateTime, lastPasswordChangeDateTime, etc.)
2. Contact and location properties (businessPhones, city, country, etc.)
3. Organisation properties (employeeId, employeeType, employeeHireDate, etc.)
4. Licence properties (assignedLicenses, assignedPlans, etc.)
5. On-premises integration properties (onPremisesDistinguishedName, etc.)
6. Authentication properties (ageGroup, passwordPolicies, etc.)
7. Custom security attributes

Properties are consolidated into single user objects before Event Hub transmission.

#### 4.1.3 Extended Properties (Optional)

SharePoint-stored properties require individual per-user API calls:

- aboutMe, birthday, hireDate, interests, mySite, pastProjects, preferredName, responsibilities, schools, skills

Enabled via `-IncludeExtendedUserProperties` parameter.

### 4.2 Group Export

Endpoint: `https://graph.microsoft.com/v1.0/groups`

Query parameters:

- `$select`: All group properties
- `$top`: 999

Returns all Azure AD groups with metadata. Group IDs are collected for membership export.

### 4.3 Group Membership Export

Endpoint: `https://graph.microsoft.com/v1.0/groups/{groupId}/members`

Query parameters:

- `$select`: id, displayName, userPrincipalName
- `$top`: 999

Executes per-group queries for all groups retrieved in group export.

## 5. Event Hub Integration

### 5.1 Message Schema

All records transmitted to Event Hub use this envelope:

```json
{
  "OdataContext": "users|groups|GroupMembers",
  "ExportId": "correlation-guid",
  "ExportTimestamp": "2025-10-01T01:00:00.000Z",
  "GroupID": "group-guid-if-applicable",
  "Data": {
    // Microsoft Graph API response object
  }
}
```

### 5.2 Chunking Strategy

Maximum payload size: 900 KB

The system automatically chunks records to remain under this limit. Each chunk is transmitted as a separate Event Hub message.

### 5.3 Transmission

Endpoint: `https://{namespace}.servicebus.windows.net/{eventhub}/messages`

Headers:

- `Authorization`: Bearer token from managed identity
- `Content-Type`: application/json
- `Content-Length`: Calculated payload size

Retry strategy: 3 attempts with exponential backoff

## 6. Configuration

### 6.1 Environment Variables

Required configuration in Function App settings:

| Variable            | Description                | Example                                |
| ------------------- | -------------------------- | -------------------------------------- |
| `EVENTHUBNAMESPACE` | Event Hub namespace        | `mycompany-eh-namespace`               |
| `EVENTHUBNAME`      | Event Hub name             | `aad-export`                           |
| `CLIENTID`          | Managed identity client ID | `12345678-1234-1234-1234-123456789012` |

### 6.2 Function Configuration

File: `host.json`

Key settings:

- Runtime: PowerShell 7.4
- Extension version: ~4
- Function timeout: 10 minutes
- Retry strategy: Exponential backoff (3 attempts, 2-30 second interval)
- Logging: Application Insights with sampling

### 6.3 Timer Schedule

CRON expression: `0 0 1 * * *` (Daily at 01:00 UTC)

Configured in: `src/FunctionApp/TimerTriggerFunction/function.json`

## 7. Error Handling

### 7.1 Retry Logic

All Graph API calls and Event Hub transmissions use automatic retry:

- Maximum retry count: 3
- Strategy: Exponential backoff
- Base interval: 2 seconds
- Maximum interval: 30 seconds

### 7.2 HTTP Status Code Handling

Retryable errors (5xx, 429, 503):

- Implement exponential backoff
- Respect Retry-After headers

Non-retryable errors (4xx except 429):

- Fail immediately
- Log error telemetry
- Continue with remaining operations

### 7.3 Partial Failure Handling

If an individual group membership query fails:

- Log error for that group
- Continue processing remaining groups
- Report success rate in completion telemetry

## 8. Monitoring and Telemetry

### 8.1 Custom Events

| Event Name                          | Trigger                    | Properties                              |
| ----------------------------------- | -------------------------- | --------------------------------------- |
| `AADExportStarted`                  | Export begins              | ExportId, TriggerContext, Configuration |
| `AADExportCompleted`                | Export succeeds            | Statistics, Duration, Record counts     |
| `AADExportFailed`                   | Export fails               | Error details, Partial statistics       |
| `UsersExportComprehensiveCompleted` | User stage completes       | User count, Properties coverage         |
| `GroupsExportCompleted`             | Group stage completes      | Group count, Duration                   |
| `MembershipsExportCompleted`        | Membership stage completes | Membership count, Success rate          |



## 10. Deployment

### 10.1 Infrastructure Deployment

Bicep template: `infrastructure/main.bicep`

Required parameters:

- `functionAppName`: Unique Function App name
- `storageAccountName`: Unique storage account name
- `userAssignedIdentityResourceId`: Full resource ID of managed identity
- `applicationInsightsName`: Application Insights resource name
- `eventHubNamespace`: Event Hub namespace name
- `eventHubName`: Event Hub name
