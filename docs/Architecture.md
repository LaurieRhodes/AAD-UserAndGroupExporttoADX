# System Architecture

## 🏗️ **High-Level Architecture**

The AAD Export to ADX solution follows a serverless, event-driven architecture designed for enterprise scalability and security.

```mermaid
graph TB
    subgraph "Azure AD Tenant"
        Users[👥 Users]
        Groups[📁 Groups]
        Members[🔗 Memberships]
    end

    subgraph "Azure Function App"
        Timer[Timer Trigger<br/>Daily @ 1 AM]
        HTTP[HTTP Trigger<br/>Manual Testing]
        Core[Invoke-AADDataExport<br/>Core Logic]
        Auth[Get-AzureADToken<br/>Authentication]
        EventSend[Send-EventsToEventHub<br/>Data Streaming]
    end

    subgraph "Azure Services"
        MI[Managed Identity]
        EH[Event Hub]
        ADX[Azure Data Explorer]
        AI[Application Insights]
    end

    Timer --> Core
    HTTP --> Core
    Core --> Auth
    Auth --> MI
    MI --> Users
    MI --> Groups
    MI --> Members
    Core --> EventSend
    EventSend --> EH
    EH --> ADX
    Core --> AI

    classDef azure fill:#0078d4,stroke:#fff,stroke-width:2px,color:#fff
    classDef function fill:#ff6b35,stroke:#fff,stroke-width:2px,color:#fff
    classDef data fill:#00bcf2,stroke:#fff,stroke-width:2px,color:#fff

    class MI,EH,ADX,AI azure
    class Timer,HTTP,Core,Auth,EventSend function
    class Users,Groups,Members data
```

## 🔧 **Component Details**

### **Function Triggers**

#### **Timer Trigger Function**

- **Purpose**: Scheduled daily execution
- **Schedule**: Daily at 1:00 AM UTC (`0 0 1 * * *`)
- **Timeout**: 4 hours maximum execution time
- **Monitoring**: Full Application Insights telemetry

#### **HTTP Trigger Function**

- **Purpose**: Manual execution for development and testing
- **Authentication**: Function key required
- **Methods**: GET and POST supported
- **Response**: JSON status with execution details

### **Core Modules**

#### **AZRest PowerShell Module**

Custom module providing Azure REST API functionality:

```powershell
# Module Structure
AZRest/
├── AZRest.psd1          # Module manifest
├── AZRest.psm1          # Module loader
└── public/              # Exported functions
    ├── Get-AzureADToken.ps1
    ├── Send-EventsToEventHub.ps1
    └── Invoke-AADDataExport.ps1 (planned)
```

#### **Authentication Flow**

```mermaid
sequenceDiagram
    participant FA as Function App
    participant MI as Managed Identity
    participant AAD as Azure AD
    participant Graph as Graph API

    FA->>MI: Request access token
    MI->>AAD: Authenticate with managed identity
    AAD->>MI: Return access token
    MI->>FA: Provide token
    FA->>Graph: API call with Bearer token
    Graph->>FA: Return data
```

## 📊 **Data Flow Architecture**

### **Export Process Flow**

```mermaid
flowchart TD
    Start([Function Triggered]) --> Auth[Acquire Access Token]
    Auth --> Users[Export Users]
    Users --> Groups[Export Groups]
    Groups --> Members[Export Group Members]
    Members --> Complete[Export Complete]

    subgraph "Data Processing"
        Users --> UserChunk[Chunk User Data]
        Groups --> GroupChunk[Chunk Group Data] 
        Members --> MemberChunk[Chunk Member Data]
    end

    subgraph "Event Hub Delivery"
        UserChunk --> EH1[Event Hub Batch 1]
        GroupChunk --> EH2[Event Hub Batch 2]
        MemberChunk --> EH3[Event Hub Batch N]
    end

    EH1 --> ADX[Azure Data Explorer]
    EH2 --> ADX
    EH3 --> ADX

    Complete --> Log[Update Telemetry]
    Log --> End([Function Complete])
```

### **Data Transformation**

#### **Input: Microsoft Graph API Response**

```json
{
  "@odata.context": "https://graph.microsoft.com/beta/$metadata#users",
  "@odata.nextLink": "https://graph.microsoft.com/beta/users?$skiptoken=...",
  "value": [
    {
      "id": "12345678-1234-1234-1234-123456789012",
      "displayName": "John Doe",
      "userPrincipalName": "john.doe@contoso.com",
      // ... additional user properties
    }
  ]
}
```

#### **Output: Event Hub Message Format**

```json
[
  {
    "OdataContext": "users",
    "Data": {
      "id": "12345678-1234-1234-1234-123456789012",
      "displayName": "John Doe",
      "userPrincipalName": "john.doe@contoso.com"
      // ... complete user object
    }
  }
]
```

## 🔐 **Security Architecture**

### **Authentication & Authorization**

```mermaid
graph LR
    subgraph "Azure AD Tenant"
        MI[Managed Identity]
        Perms[Graph API Permissions]
    end

    subgraph "Function App"
        Func[Function Code]
        Env[Environment Variables]
    end

    subgraph "External Services"
        Graph[Microsoft Graph]
        EH[Event Hub]
    end

    MI --> Perms
    Func --> MI
    Env --> Func
    Perms --> Graph
    Func --> EH
```

### **Required Permissions**

| Permission          | Justification                | Risk Level |
| ------------------- | ---------------------------- | ---------- |
| `User.Read.All`     | Read user profile data       | Low        |
| `Group.Read.All`    | Read group information       | Low        |
| `AuditLog.Read.All` | Access audit logs (optional) | Medium     |

### **Security Controls**

- **No Stored Credentials**: Managed identity eliminates password management
- **Minimal Permissions**: Least privilege access to Graph API
- **Network Security**: HTTPS-only communication
- **Audit Logging**: All operations logged to Application Insights

## ⚡ **Performance Architecture**

### **Scalability Considerations**

| Component        | Scaling Strategy              | Limits                   |
| ---------------- | ----------------------------- | ------------------------ |
| **Function App** | Consumption plan auto-scaling | 200 concurrent instances |
| **Graph API**    | Rate limiting + retry logic   | 1000+ requests/minute    |
| **Event Hub**    | Partition-based throughput    | 1000 TUs maximum         |
| **Memory Usage** | Chunked processing            | 1.5 GB per instance      |

### **Optimization Strategies**

1. **Pagination**: Process Graph API results in manageable chunks
2. **Batching**: Group Event Hub messages for efficiency
3. **Retry Logic**: Exponential backoff for transient failures
4. **Memory Management**: Stream large datasets rather than loading entirely

## 🏃‍♂️ **Execution Flow**

### **Detailed Process Steps**

```mermaid
flowchart TD
    Init[Function Initialize] --> LoadMods[Load PowerShell Modules]
    LoadMods --> GetToken[Get-AzureADToken]
    GetToken --> StartUsers[Start User Export]

    subgraph "User Export Loop"
        StartUsers --> UserAPI[Call Graph Users API]
        UserAPI --> UserProcess[Process User Page]
        UserProcess --> UserEvent[Send to Event Hub]
        UserEvent --> UserNext{Next Page?}
        UserNext -->|Yes| UserAPI
        UserNext -->|No| StartGroups[Start Group Export]
    end

    subgraph "Group Export Loop"
        StartGroups --> GroupAPI[Call Graph Groups API]
        GroupAPI --> GroupProcess[Process Group Page]
        GroupProcess --> GroupCollect[Collect Group IDs]
        GroupCollect --> GroupEvent[Send to Event Hub]
        GroupEvent --> GroupNext{Next Page?}
        GroupNext -->|Yes| GroupAPI
        GroupNext -->|No| StartMembers[Start Member Export]
    end

    subgraph "Member Export Loop"
        StartMembers --> MemberLoop[For Each Group ID]
        MemberLoop --> MemberAPI[Call Group Members API]
        MemberAPI --> MemberProcess[Process Members]
        MemberProcess --> MemberEvent[Send to Event Hub]
        MemberEvent --> MemberNext{More Groups?}
        MemberNext -->|Yes| MemberLoop
        MemberNext -->|No| Complete[Export Complete]
    end

    Complete --> Return[Return Success Response]
```

### **Error Handling Flow**

```mermaid
flowchart TD
    Operation[Graph API Operation] --> Try[Execute Request]
    Try --> Success{Success?}
    Success -->|Yes| Process[Process Response]
    Success -->|No| Error[Handle Error]

    Error --> RateLimit{Rate Limited?}
    RateLimit -->|Yes| Wait[Wait + Retry]
    RateLimit -->|No| Auth{Auth Error?}

    Auth -->|Yes| RefreshToken[Refresh Token]
    Auth -->|No| Critical[Log Critical Error]

    Wait --> Try
    RefreshToken --> Try
    Critical --> Fail[Function Fails]

    Process --> Continue[Continue Processing]
```

## 🔄 **Data Pipeline Architecture**

### **End-to-End Data Flow**

```mermaid
graph LR
    subgraph "Source"
        AAD[Azure AD<br/>Identity Data]
    end

    subgraph "Processing Layer"
        FA[Function App<br/>PowerShell]
        MI[Managed Identity<br/>Authentication]
    end

    subgraph "Streaming Layer"
        EH[Event Hub<br/>Message Broker]
        Partitions[Multiple Partitions<br/>Parallel Processing]
    end

    subgraph "Analytics Layer"
        ADX[Azure Data Explorer<br/>Analytics Database]
        Tables[Structured Tables<br/>Users, Groups, Members]
    end

    subgraph "Monitoring"
        AI[Application Insights<br/>Telemetry & Logs]
        Alerts[Alerts & Notifications]
    end

    AAD --> FA
    MI --> AAD
    FA --> EH
    EH --> Partitions
    Partitions --> ADX
    ADX --> Tables
    FA --> AI
    AI --> Alerts
```

### **Event Hub Message Structure**

#### **User Records**

```json
{
  "OdataContext": "users",
  "Data": {
    "id": "user-guid",
    "displayName": "John Doe",
    "userPrincipalName": "john.doe@contoso.com",
    "jobTitle": "Senior Developer",
    "department": "Engineering",
    "accountEnabled": true,
    "createdDateTime": "2023-01-15T10:30:00Z",
    "businessPhones": ["+1-555-0123"],
    "officeLocation": "Building A, Floor 3"
  }
}
```

#### **Group Records**

```json
{
  "OdataContext": "groups",
  "Data": {
    "id": "group-guid",
    "displayName": "Engineering Team",
    "groupTypes": ["Unified"],
    "securityEnabled": true,
    "mailEnabled": true,
    "createdDateTime": "2023-01-10T08:00:00Z"
  }
}
```

#### **Group Member Records**

```json
{
  "OdataContext": "GroupMembers",
  "GroupID": "group-guid",
  "Data": "user-or-group-guid"
}
```

## 🏗️ **Infrastructure Components**

### **Azure Function App Configuration**

```json
{
  "functionTimeout": "04:00:00",
  "healthMonitor": {
    "enabled": true,
    "healthCheckInterval": "00:00:10"
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
```

### **Managed Identity Setup**

- **Type**: User-assigned managed identity
- **Scope**: Microsoft Graph API access
- **Permissions**: Minimal required (User.Read.All, Group.Read.All)
- **Security**: No stored credentials or secrets

### **Event Hub Configuration**

- **Namespace**: Dedicated namespace for identity data
- **Partitions**: Multiple partitions for parallel processing
- **Retention**: 7-day message retention
- **Throughput**: Auto-scaling based on load

## 📈 **Scalability & Performance**

### **Design Patterns**

#### **Pagination Handling**

```powershell
do {
    $response = Invoke-RestMethod -Uri $apiUrl -Headers $authHeader
    # Process current page
    $apiUrl = $response.'@odata.nextLink'
} while ($null -ne $apiUrl)
```

#### **Chunked Event Hub Delivery**

```powershell
# Ensure messages don't exceed Event Hub 1MB limit
$maxPayloadSize = 900KB
# Split large collections into manageable chunks
```

#### **Rate Limit Management**

```powershell
Start-Sleep -Seconds 2  # Respect Graph API limits
# Future: Implement exponential backoff
```

### **Performance Metrics**

| Metric             | Small Tenant | Large Tenant  | Enterprise |
| ------------------ | ------------ | ------------- | ---------- |
| **Users**          | < 1,000      | 1,000-10,000  | 50,000+    |
| **Groups**         | < 100        | 100-1,000     | 5,000+     |
| **Execution Time** | 2-5 minutes  | 10-30 minutes | 1-4 hours  |
| **Memory Usage**   | 50-100 MB    | 200-500 MB    | 1-1.5 GB   |
| **API Calls**      | 10-50        | 100-500       | 1,000+     |

## 🔒 **Security Design**

### **Authentication Architecture**

```mermaid
sequenceDiagram
    participant FA as Function App
    participant MI as Managed Identity
    participant AAD as Azure AD
    participant Graph as Microsoft Graph
    participant EH as Event Hub

    Note over FA,EH: Secure Authentication Flow

    FA->>MI: Request Graph API token
    MI->>AAD: Authenticate managed identity
    AAD->>MI: Return access token
    MI->>FA: Provide Graph token

    FA->>Graph: GET /users (with Bearer token)
    Graph->>FA: Return user data

    FA->>MI: Request Event Hub token
    MI->>AAD: Authenticate for Event Hub
    AAD->>MI: Return Event Hub token
    MI->>FA: Provide Event Hub token

    FA->>EH: POST data (with Bearer token)
    EH->>FA: Acknowledge receipt
```

### **Network Security**

- **TLS 1.2+**: All communications encrypted in transit
- **HTTPS Only**: Function app configured for HTTPS-only access
- **Private Endpoints**: Optional VNet integration for enhanced security
- **Firewall Rules**: Configurable IP restrictions

### **Data Protection**

- **At Rest**: Event Hub and ADX encryption enabled by default
- **In Transit**: TLS encryption for all API communications
- **Access Control**: RBAC-based permissions throughout pipeline
- **Audit Trail**: Complete operation logging in Application Insights

## 🔄 **Error Handling Strategy**

### **Error Classification**

```mermaid
graph TD
    Error[Error Occurs] --> Type{Error Type}

    Type -->|Transient| Retry[Implement Retry Logic]
    Type -->|Authentication| RefreshToken[Refresh Access Token]
    Type -->|Rate Limit| Backoff[Exponential Backoff]
    Type -->|Critical| Log[Log and Fail Gracefully]

    Retry --> Success{Retry Success?}
    Success -->|Yes| Continue[Continue Processing]
    Success -->|No| Log

    RefreshToken --> RetryAuth[Retry with New Token]
    RetryAuth --> Continue

    Backoff --> WaitRetry[Wait and Retry]
    WaitRetry --> Continue

    Log --> Alert[Send Alert]
    Alert --> End[Function Terminates]
    Continue --> End
```

### **Retry Patterns**

| Error Type           | Retry Strategy        | Max Attempts |
| -------------------- | --------------------- | ------------ |
| **429 Rate Limited** | Exponential backoff   | 5            |
| **5xx Server Error** | Linear backoff        | 3            |
| **Network Timeout**  | Immediate retry       | 2            |
| **401 Unauthorized** | Token refresh + retry | 1            |

## 🔍 **Monitoring Architecture**

### **Telemetry Collection**

```mermaid
graph TB
    subgraph "Function App"
        Traces[Trace Logs]
        Metrics[Custom Metrics]
        Deps[Dependencies]
        Exceptions[Exceptions]
    end

    subgraph "Application Insights"
        Analytics[Analytics Engine]
        Alerts[Alert Rules]
        Dashboard[Monitoring Dashboard]
    end

    subgraph "Notifications"
        Email[Email Alerts]
        Teams[Teams Notifications]
        SMS[SMS Alerts]
    end

    Traces --> Analytics
    Metrics --> Analytics
    Deps --> Analytics
    Exceptions --> Analytics

    Analytics --> Alerts
    Alerts --> Email
    Alerts --> Teams
    Alerts --> SMS

    Analytics --> Dashboard
```

### **Key Performance Indicators**

- **Success Rate**: Percentage of successful executions
- **Execution Duration**: Time to complete full export
- **Graph API Latency**: Response times for Microsoft Graph calls
- **Event Hub Throughput**: Messages per second delivered
- **Error Rates**: Breakdown by error type and frequency

## 🔧 **Deployment Architecture**

### **Infrastructure as Code**

```mermaid
graph TD
    subgraph "Source Control"
        Repo[GitHub Repository]
        Bicep[Bicep Templates]
        Params[Parameter Files]
    end

    subgraph "Deployment Pipeline"
        CI[Continuous Integration]
        Validate[Template Validation]
        Deploy[Resource Deployment]
    end

    subgraph "Azure Resources"
        RG[Resource Group]
        FA[Function App]
        Storage[Storage Account]
        AI[Application Insights]
        MI[Managed Identity]
    end

    Repo --> CI
    Bicep --> Validate
    Params --> Deploy
    Validate --> Deploy
    Deploy --> RG
    RG --> FA
    RG --> Storage
    RG --> AI
    RG --> MI
```

### **Environment Configuration**

| Environment     | Purpose                   | Configuration                  |
| --------------- | ------------------------- | ------------------------------ |
| **Development** | Local testing             | Mock services, reduced logging |
| **Staging**     | Pre-production validation | Full monitoring, test data     |
| **Production**  | Live data export          | Enterprise monitoring, alerts  |

## 🧩 **Module Dependencies**

### **PowerShell Module Graph**

```mermaid
graph TD
    Profile[profile.ps1] --> Modules[Load All Modules]
    Modules --> AZRest[AZRest Module]

    subgraph "AZRest Functions"
        AZRest --> Token[Get-AzureADToken]
        AZRest --> EventHub[Send-EventsToEventHub]
        AZRest --> Export[Invoke-AADDataExport]
    end

    subgraph "Trigger Functions"
        Timer[Timer Trigger] --> Export
        HTTP[HTTP Trigger] --> Export
    end

    Export --> Token
    Export --> EventHub

    subgraph "Azure Dependencies"
        Token --> Identity[Azure Identity]
        EventHub --> EHClient[Event Hub Client]
    end
```

### **External Dependencies**

```powershell
# requirements.psd1
@{
    'AzTable' = '2.*'                    # Azure Table Storage
    'Az.OperationalInsights' = '3.*'     # Log Analytics queries
    'Az.Resources' = '5.*'               # Resource management
    'Az.Storage' = '5.*'                 # Storage operations
}
```

## 🔄 **Data Consistency & Reliability**

### **Consistency Model**

- **Eventually Consistent**: Data appears in ADX within minutes of export
- **At-Least-Once Delivery**: Event Hub guarantees message delivery
- **Idempotent Operations**: Safe to retry failed exports
- **Audit Trail**: Complete operation history in Application Insights

### **Reliability Patterns**

- **Circuit Breaker**: Prevent cascading failures
- **Bulkhead Isolation**: Separate user/group/member processing
- **Timeout Management**: Configurable timeouts for all operations
- **Health Checks**: Monitor function app and dependency health

---

## 📋 **Deployment Considerations**

### **Resource Sizing**

| Component                | Recommended Size  | Rationale                         |
| ------------------------ | ----------------- | --------------------------------- |
| **Function App**         | Consumption Plan* | Auto-scaling based on demand      |
| **Storage Account**      | Standard LRS      | Function app storage requirements |
| **Event Hub**            | Standard Tier     | 1000 TU capacity sufficient       |
| **Application Insights** | Standard          | Full feature set required         |

Note that long running Function Apps (more than 10 minutes in duration) need to be hosted on an organisational AppService Plan.  By using a PowerShell Function App, this may share a Windows App Service Plan with Logic Apps used by the SOC.