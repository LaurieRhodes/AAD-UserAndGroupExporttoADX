# Azure AD User and Group Export to ADX

[![Azure Function](https://img.shields.io/badge/Azure-Function%20App-blue?logo=microsoft-azure)](https://azure.microsoft.com/en-us/services/functions/)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.4-blue?logo=powershell)](https://docs.microsoft.com/en-us/powershell/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **Professional-grade Azure Function App that recursively exports Azure AD user and group data to Azure Data Explorer (ADX) via Event Hub with enterprise security and monitoring.**

## 🏗️ **Architecture Overview**

This solution provides automated, secure, and scalable extraction of Azure AD identity data using:

- **Azure Functions** (PowerShell) for serverless execution
- **Microsoft Graph API** for Azure AD data access  
- **Managed Identity** for secure, password-less authentication
- **Event Hub** for reliable data streaming to ADX
- **Application Insights** for monitoring and telemetry

## 🚀 **Quick Start**

### Prerequisites

- Azure subscription with contributor access
- Azure AD tenant with appropriate permissions
- PowerShell 7.0+ (for local development)
- Azure CLI or Azure PowerShell module

### Deployment

```bash
# Clone the repository
git clone https://github.com/your-org/AAD-UserAndGroupExporttoADX.git
cd AAD-UserAndGroupExporttoADX

# Deploy infrastructure
az deployment group create \
  --resource-group "your-rg" \
  --template-file infrastructure/main.bicep \
  --parameters @infrastructure/parameters.json

# Deploy function code
func azure functionapp publish your-function-app-name
```

This may also be achieved utilising the deploy.ps1 script in the root of this directory. 

## 📋 **Features**

### **Data Export Capabilities**

- **Users**: Comprehensive user object data 
- **Groups**: All Azure AD groups with metadata and properties
- **Group Memberships**: Complete group membership relationships for access analysis

### **Enterprise Features**

- **🔒 Secure Authentication**: Managed Identity eliminates credential management
- **📊 Monitoring**: Full Application Insights integration with custom telemetry
- **⚡ Performance**: Intelligent batching and chunking for large datasets
- **🔄 Reliability**: Built-in retry logic and error handling
- **📅 Scheduling**: Configurable daily execution with optimal timing
- **🧪 Testing**: HTTP trigger enables development and manual testing

## 🔧 **Configuration**

### **Environment Variables**

| Variable            | Description                | Example                                |
| ------------------- | -------------------------- | -------------------------------------- |
| `EVENTHUBNAMESPACE` | Event Hub namespace        | `your-eh-namespace`                    |
| `EVENTHUB`          | Event Hub name             | `aad-export-hub`                       |
| `CLIENTID`          | Managed Identity client ID | `12345678-1234-1234-1234-123456789012` |

### **Required Permissions**

The managed identity requires these Microsoft Graph application permissions:

- `User.Read.All` - Read all user profiles
- `Group.Read.All` - Read all groups and group properties  
- `AuditLog.Read.All` - Access audit information (optional)

## 📁 **Project Structure**

```
src/FunctionApp/
├── host.json                          # Function app configuration
├── profile.ps1                        # Startup initialization  
├── requirements.psd1                  # PowerShell dependencies
├── TimerTriggerFunction/              # Scheduled execution
│   ├── function.json                  # Timer configuration (daily @ 1 AM)
│   └── run.ps1                        # Timer entry point
├── HttpTriggerFunction/               # Manual testing
│   ├── function.json                  # HTTP trigger configuration
│   └── run.ps1                        # HTTP entry point
└── modules/                           # Custom PowerShell modules
    ├── AZRest.psd1                   # Module manifest
    ├── AZRest.psm1                   # Module loader
    └── public/                        # Exported functions
        ├── Get-AzureADToken.ps1       # Managed identity authentication
        ├── Send-EventsToEventHub.ps1  # Event Hub integration
        └── [utility functions]
```

## 🔄 **Data Flow**

### **Export Process**

1. **Authentication**: Acquire access token using managed identity
2. **Users Export**: Paginate through all Azure AD users with selected attributes
3. **Groups Export**: Retrieve all groups and collect group IDs
4. **Memberships Export**: For each group, get member relationships
5. **Event Hub Delivery**: Send data in optimally-sized chunks to Event Hub
6. **ADX Ingestion**: Event Hub streams data to Azure Data Explorer

### **Data Structure**

```json
{
  "OdataContext": "users|groups|GroupMembers",
  "GroupID": "group-id-if-applicable", 
  "Data": {
    // Microsoft Graph API response object
  }
}
```

## 🚀 **Usage Examples**

### **Manual Execution (Development)**

```bash
# Trigger via HTTP endpoint
curl -X POST "https://your-function-app.azurewebsites.net/api/HttpTriggerFunction?code=your-function-key"
```

### **Scheduled Execution**

The timer trigger automatically executes daily at 1:00 AM UTC, ensuring fresh data availability for morning analytics and reporting. 

## 📄 **License**

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🏷️ **Version History**

| Version  | Date    | Changes                                              |
| -------- | ------- | ---------------------------------------------------- |
| **v1.0** | Current | Initial release with basic export functionality      |
| **v1.1** | Planned | Refactored architecture with shared core logic       |
| **v1.2** | Planned | Enhanced error handling and performance optimization |

## 📄 **Documentation**

- **📚 Detailed Documentation**: See [docs/](docs/) directory for comprehensive guides
- 
- **📖 API Reference**: See [docs/API-Reference.md](docs/API-Reference.md) for detailed function documentation