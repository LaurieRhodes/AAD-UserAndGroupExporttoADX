# Deployment Guide

Version 1.0  
Last Modified: 2025-10-01

## 1. Prerequisites

### 1.1 Azure Requirements

- Azure subscription with Contributor role
- Azure AD tenant with Global Administrator or equivalent
- Resource group (existing or to be created)
- Available quota for:
  - 1 Function App (Consumption plan)
  - 1 Storage Account (Standard LRS)
  - 1 Application Insights instance
  - 1 Event Hub namespace (existing)
  - 1 User-assigned managed identity (existing)

### 1.2 Local Development Tools

**Required:**

- PowerShell 7.4 or later
- Azure CLI 2.50.0 or later, OR Azure PowerShell 10.0.0 or later
- Azure Functions Core Tools 4.x

**Optional:**

- Visual Studio Code with Azure Functions extension
- Git client

### 1.3 Permissions Required

**Azure Subscription:**

- Contributor on resource group

**Azure AD:**

- Application Administrator (to grant API permissions)
- Privileged Role Administrator (to assign managed identity permissions)

## 2. Pre-Deployment Setup

### 2.1 Create User-Assigned Managed Identity

```bash
# Create managed identity
az identity create \
  --name aad-export-identity \
  --resource-group your-rg \
  --location australiaeast

# Capture identity details
IDENTITY_ID=$(az identity show \
  --name aad-export-identity \
  --resource-group your-rg \
  --query id -o tsv)

CLIENT_ID=$(az identity show \
  --name aad-export-identity \
  --resource-group your-rg \
  --query clientId -o tsv)

PRINCIPAL_ID=$(az identity show \
  --name aad-export-identity \
  --resource-group your-rg \
  --query principalId -o tsv)
```

### 2.2 Grant Microsoft Graph Permissions

**Option A: Azure Portal**

1. Navigate to Azure Active Directory → Enterprise Applications
2. Search for the managed identity by client ID
3. Select Permissions
4. Add permissions:
   - `User.Read.All` (Application)
   - `Group.Read.All` (Application)
   - `GroupMember.Read.All` (Application)
5. Grant admin consent

**Option B: PowerShell**

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.ReadWrite.All"

# Get Graph service principal
$graphSP = Get-MgServicePrincipal -Filter "displayName eq 'Microsoft Graph'"

# Get managed identity service principal
$managedIdentitySP = Get-MgServicePrincipal -Filter "displayName eq 'aad-export-identity'"

# Define required permissions
$permissions = @(
    @{ Id = "df021288-bdef-4463-88db-98f22de89214"; Type = "Role" }  # User.Read.All
    @{ Id = "5b567255-7703-4780-807c-7be8301ae99b"; Type = "Role" }  # Group.Read.All
    @{ Id = "98830695-27a2-44f7-8c18-0c3ebc9698f6"; Type = "Role" }  # GroupMember.Read.All
)

# Grant permissions
foreach ($permission in $permissions) {
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $managedIdentitySP.Id `
        -PrincipalId $managedIdentitySP.Id `
        -ResourceId $graphSP.Id `
        -AppRoleId $permission.Id
}
```

### 2.3 Create Event Hub Resources

```bash
# Create Event Hub namespace (if not existing)
az eventhubs namespace create \
  --name your-eh-namespace \
  --resource-group your-rg \
  --location australiaeast \
  --sku Standard

# Create Event Hub
az eventhubs eventhub create \
  --name aad-export \
  --namespace-name your-eh-namespace \
  --resource-group your-rg \
  --partition-count 4 \
  --message-retention 1

# Grant managed identity access to Event Hub
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Azure Event Hubs Data Sender" \
  --scope "/subscriptions/{subscription-id}/resourceGroups/your-rg/providers/Microsoft.EventHub/namespaces/your-eh-namespace"
```

**Note:** Role assignments can take up to 24 hours to propagate. Plan deployment accordingly.

## 3. Infrastructure Deployment

### 3.1 Prepare Parameters File

Copy example parameters:

```bash
cp infrastructure/example.parameters.json infrastructure/parameters.json
```

Edit `infrastructure/parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "functionAppName": {
      "value": "func-aad-export-prod"
    },
    "storageAccountName": {
      "value": "staadexportprod"
    },
    "userAssignedIdentityResourceId": {
      "value": "/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aad-export-identity"
    },
    "applicationInsightsName": {
      "value": "appi-aad-export-prod"
    },
    "eventHubNamespace": {
      "value": "your-eh-namespace"
    },
    "eventHubName": {
      "value": "aad-export"
    },
    "resourceGroupID": {
      "value": "/subscriptions/{sub-id}/resourceGroups/{rg}"
    }
  }
}
```

**Naming Constraints:**

- Function App name: 2-60 characters, alphanumeric and hyphens, globally unique
- Storage account name: 3-24 characters, lowercase alphanumeric only, globally unique
- Application Insights name: 1-260 characters

### 3.2 Validate Deployment

```bash
az deployment group validate \
  --resource-group your-rg \
  --template-file infrastructure/main.bicep \
  --parameters @infrastructure/parameters.json
```

### 3.3 Deploy Infrastructure

```bash
az deployment group create \
  --resource-group your-rg \
  --template-file infrastructure/main.bicep \
  --parameters @infrastructure/parameters.json \
  --name "aad-export-deployment-$(date +%Y%m%d-%H%M%S)"
```

Deployment typically completes in 2-5 minutes.

### 3.4 Verify Infrastructure

```bash
# List created resources
az resource list \
  --resource-group your-rg \
  --output table

# Verify Function App configuration
az functionapp config appsettings list \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --output table
```

## 4. Code Deployment

### 4.1 Option A: Azure Functions Core Tools

**From project root:**

```bash
cd src/FunctionApp

# Deploy
func azure functionapp publish func-aad-export-prod
```

**Expected output:**

```
Getting site publishing info...
Preparing archive...
Uploading 2.45 MB
Upload completed successfully.
Deployment completed successfully.
Syncing triggers...
Functions in func-aad-export-prod:
    HttpTriggerFunction - [httpTrigger]
        Invoke url: https://func-aad-export-prod.azurewebsites.net/api/HttpTriggerFunction

    TimerTriggerFunction - [timerTrigger]
        Schedule: 0 0 1 * * *
```

### 4.2 Option B: Deployment Script

**From project root:**

```powershell
.\deploy.ps1 `
  -FunctionAppName "func-aad-export-prod" `
  -ResourceGroup "your-rg"
```

The script:

1. Validates local PowerShell version
2. Checks Function App exists
3. Packages code
4. Deploys to Azure
5. Verifies deployment
6. Displays function URLs

### 4.3 Option C: CI/CD Pipeline

**GitHub Actions workflow:**

```yaml
name: Deploy Function App

on:
  push:
    branches: [ main ]
  workflow_dispatch:

env:
  AZURE_FUNCTIONAPP_NAME: func-aad-export-prod
  AZURE_FUNCTIONAPP_PACKAGE_PATH: 'src/FunctionApp'

jobs:
  deploy:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup PowerShell
        uses: azure/powershell@v1
        with:
          azPSVersion: 'latest'

      - name: Login to Azure
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Deploy Function App
        run: |
          cd ${{ env.AZURE_FUNCTIONAPP_PACKAGE_PATH }}
          func azure functionapp publish ${{ env.AZURE_FUNCTIONAPP_NAME }}
```

## 5. Post-Deployment Verification

### 5.1 Check Function App Health

```bash
# Get Function App status
az functionapp show \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --query "state" -o tsv

# Expected: Running
```

### 5.2 Verify Module Loading

Navigate to Function App in Azure Portal:

1. Select "Console" under Development Tools
2. Run:

```powershell
Get-Module -ListAvailable AADExporter
```

Expected output showing module version 3.0.

### 5.3 Test HTTP Trigger

```bash
# Get function key
FUNCTION_KEY=$(az functionapp keys list \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --query "functionKeys.default" -o tsv)

# Invoke function
curl -X POST \
  "https://func-aad-export-prod.azurewebsites.net/api/HttpTriggerFunction?code=$FUNCTION_KEY" \
  -H "Content-Type: application/json"
```

Expected: HTTP 200 with export statistics.

### 5.4 Monitor Execution

**Application Insights:**

```bash
# Get Application Insights instrumentation key
AI_KEY=$(az monitor app-insights component show \
  --app appi-aad-export-prod \
  --resource-group your-rg \
  --query "instrumentationKey" -o tsv)
```

Navigate to Application Insights in portal and check:

- Live Metrics Stream (real-time monitoring)
- Failures (any errors during execution)
- Performance (execution duration)
- Custom Events (AADExportStarted, AADExportCompleted)

### 5.5 Verify Event Hub Delivery

```bash
# Check Event Hub metrics
az monitor metrics list \
  --resource "/subscriptions/{sub-id}/resourceGroups/your-rg/providers/Microsoft.EventHub/namespaces/your-eh-namespace/eventhubs/aad-export" \
  --metric "IncomingMessages" \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1M \
  --output table
```

Expected: Non-zero incoming messages after function execution.

## 6. Configuration Adjustments

### 6.1 Modify Timer Schedule

Edit `src/FunctionApp/TimerTriggerFunction/function.json`:

```json
{
  "bindings": [
    {
      "name": "Timer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 30 2 * * *"
    }
  ]
}
```

Common schedules:

- `0 0 1 * * *` - Daily at 01:00 UTC
- `0 0 */6 * * *` - Every 6 hours
- `0 0 1 * * 1` - Weekly on Monday at 01:00 UTC

Redeploy after changes.

### 6.2 Adjust Function Timeout

Edit `src/FunctionApp/host.json`:

```json
{
  "functionTimeout": "00:15:00"
}
```

Maximum values by plan:

- Consumption: 10 minutes (default: 5 minutes)
- Premium: Unlimited (default: 30 minutes)
- Dedicated: Unlimited (default: 30 minutes)

### 6.3 Enable Extended User Properties

Update environment variable:

```bash
az functionapp config appsettings set \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --settings "INCLUDE_EXTENDED_PROPERTIES=true"
```

Modify timer trigger to pass parameter:

```powershell
# In run.ps1
$exportResult = Invoke-AADDataExport `
  -TriggerContext "TimerTrigger" `
  -IncludeExtendedUserProperties:$([bool]::Parse($env:INCLUDE_EXTENDED_PROPERTIES))
```

## 7. Scaling Considerations

### 7.1 Upgrade to Premium Plan

For large tenants (>50,000 users):

```bash
# Create Premium plan
az functionapp plan create \
  --name plan-aad-export-premium \
  --resource-group your-rg \
  --location australiaeast \
  --sku EP1 \
  --is-linux false

# Update Function App to use Premium plan
az functionapp update \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --plan plan-aad-export-premium
```

### 7.2 Increase Event Hub Throughput

```bash
# Increase partition count
az eventhubs eventhub update \
  --name aad-export \
  --namespace-name your-eh-namespace \
  --resource-group your-rg \
  --partition-count 8

# Upgrade namespace SKU
az eventhubs namespace update \
  --name your-eh-namespace \
  --resource-group your-rg \
  --sku Premium \
  --capacity 2
```

### 7.3 Enable VNet Integration

For enhanced security:

```bash
# Create VNet and subnet
az network vnet create \
  --name vnet-functions \
  --resource-group your-rg \
  --address-prefix 10.0.0.0/16 \
  --subnet-name subnet-functions \
  --subnet-prefix 10.0.1.0/24

# Enable VNet integration
az functionapp vnet-integration add \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --vnet vnet-functions \
  --subnet subnet-functions
```

## 8. Security Hardening

### 8.1 Disable Public Access

```bash
# Enable private endpoints
az functionapp update \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --set publicNetworkAccess=Disabled
```

### 8.2 Enable Managed Identity for Storage

Remove storage account keys from configuration:

```bash
az functionapp config appsettings delete \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --setting-names "AzureWebJobsStorage" "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING"

# Grant managed identity access to storage
STORAGE_ID=$(az storage account show \
  --name staadexportprod \
  --resource-group your-rg \
  --query id -o tsv)

az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage Blob Data Owner" \
  --scope $STORAGE_ID

# Update Function App to use managed identity
az functionapp config appsettings set \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --settings "AzureWebJobsStorage__accountName=staadexportprod"
```

### 8.3 Implement IP Restrictions

```bash
az functionapp config access-restriction add \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --rule-name "AllowCorporateNetwork" \
  --priority 100 \
  --action Allow \
  --ip-address "203.0.113.0/24"
```

## 9. Monitoring Setup

### 9.1 Create Alert Rules

**Export Failure Alert:**

```bash
az monitor metrics alert create \
  --name "AAD Export Failed" \
  --resource-group your-rg \
  --scopes "/subscriptions/{sub-id}/resourceGroups/your-rg/providers/Microsoft.Insights/components/appi-aad-export-prod" \
  --condition "count customEvents where name == 'AADExportFailed' > 0" \
  --window-size 5m \
  --evaluation-frequency 5m \
  --action-group alert-action-group
```

**Long Execution Duration Alert:**

```bash
az monitor metrics alert create \
  --name "AAD Export Slow" \
  --resource-group your-rg \
  --scopes "/subscriptions/{sub-id}/resourceGroups/your-rg/providers/Microsoft.Web/sites/func-aad-export-prod" \
  --condition "avg FunctionExecutionTime > 480000" \
  --window-size 5m \
  --evaluation-frequency 5m
```

### 9.2 Configure Log Analytics

```bash
# Create Log Analytics workspace
az monitor log-analytics workspace create \
  --workspace-name law-aad-export \
  --resource-group your-rg \
  --location australiaeast

# Link Application Insights
az monitor app-insights component update \
  --app appi-aad-export-prod \
  --resource-group your-rg \
  --workspace "/subscriptions/{sub-id}/resourceGroups/your-rg/providers/Microsoft.OperationalInsights/workspaces/law-aad-export"
```

### 9.3 Create Dashboard

Import dashboard template from `infrastructure/dashboard.json` (if provided) or create custom dashboard with:

- Export success rate over time
- Average execution duration
- Record counts by type (users, groups, memberships)
- Error frequency
- Event Hub throughput

## 10. Backup and Disaster Recovery

### 10.1 Export Function App Configuration

```bash
# Export app settings
az functionapp config appsettings list \
  --name func-aad-export-prod \
  --resource-group your-rg \
  > backup/appsettings-$(date +%Y%m%d).json

# Export ARM template
az group export \
  --name your-rg \
  --resource-ids "/subscriptions/{sub-id}/resourceGroups/your-rg/providers/Microsoft.Web/sites/func-aad-export-prod" \
  > backup/function-app-$(date +%Y%m%d).json
```

### 10.2 Secondary Region Deployment

Deploy to secondary region for disaster recovery:

```bash
# Deploy infrastructure to secondary region
az deployment group create \
  --resource-group your-rg-secondary \
  --template-file infrastructure/main.bicep \
  --parameters @infrastructure/parameters-secondary.json

# Deploy code
func azure functionapp publish func-aad-export-prod-secondary
```

Configure Traffic Manager or Front Door for automatic failover.

## 11. Troubleshooting Deployment Issues

### 11.1 Permission Propagation Delays

**Symptom:** 401/403 errors immediately after deployment

**Solution:**

- Microsoft Graph permissions can take up to 24 hours to propagate
- Event Hub role assignments can take up to 30 minutes
- Wait required duration or use service principal with immediate effect

### 11.2 Module Loading Failures

**Symptom:** "Invoke-AADDataExport command not found"

**Solution:**

```powershell
# Verify module files deployed
Get-ChildItem D:\home\site\wwwroot\modules -Recurse

# Check profile.ps1 executes
Get-Content D:\home\site\wwwroot\profile.ps1

# Manually load module
Import-Module D:\home\site\wwwroot\modules\AADExporter.psm1 -Force -Verbose
```

### 11.3 Storage Account Access Issues

**Symptom:** "Storage account connection failed"

**Solution:**

```bash
# Verify storage account exists
az storage account show --name staadexportprod

# Regenerate keys
az storage account keys renew \
  --account-name staadexportprod \
  --key primary

# Update Function App settings
az functionapp config appsettings set \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --settings "AzureWebJobsStorage=DefaultEndpointsProtocol=https;AccountName=staadexportprod;AccountKey={new-key}"
```

### 11.4 Event Hub Connection Failures

**Symptom:** "Event Hub transmission failed - 401 unauthorised"

**Solution:**

```bash
# Verify role assignment
az role assignment list \
  --assignee $PRINCIPAL_ID \
  --scope "/subscriptions/{sub-id}/resourceGroups/your-rg/providers/Microsoft.EventHub/namespaces/your-eh-namespace" \
  --query "[?roleDefinitionName=='Azure Event Hubs Data Sender']"

# If missing, create role assignment
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Azure Event Hubs Data Sender" \
  --scope "/subscriptions/{sub-id}/resourceGroups/your-rg/providers/Microsoft.EventHub/namespaces/your-eh-namespace"

# Wait 30 minutes for propagation
```

## 12. Rollback Procedures

### 12.1 Code Rollback

```bash
# List deployment history
az functionapp deployment list \
  --name func-aad-export-prod \
  --resource-group your-rg

# Rollback to previous deployment
az functionapp deployment source show \
  --name func-aad-export-prod \
  --resource-group your-rg \
  --deployment-id {previous-id}
```

### 12.2 Infrastructure Rollback

```bash
# List deployment history
az deployment group list \
  --resource-group your-rg \
  --query "[].{name:name, timestamp:properties.timestamp, state:properties.provisioningState}"

# Redeploy previous version
az deployment group create \
  --resource-group your-rg \
  --template-file backup/main-previous.bicep \
  --parameters @backup/parameters-previous.json
```

## 13. Decommissioning

### 13.1 Disable Function

```bash
# Stop Function App
az functionapp stop \
  --name func-aad-export-prod \
  --resource-group your-rg
```

### 13.2 Remove Resources

```bash
# Delete Function App
az functionapp delete \
  --name func-aad-export-prod \
  --resource-group your-rg

# Delete supporting resources
az resource delete \
  --ids $(az resource list \
    --resource-group your-rg \
    --query "[?tags.project=='aad-export'].id" -o tsv)
```

### 13.3 Revoke Permissions

```bash
# Remove Graph API permissions
# (Manual step in Azure Portal → Enterprise Applications)

# Remove Event Hub role assignment
az role assignment delete \
  --assignee $PRINCIPAL_ID \
  --role "Azure Event Hubs Data Sender" \
  --scope "/subscriptions/{sub-id}/resourceGroups/your-rg/providers/Microsoft.EventHub/namespaces/your-eh-namespace"
```

## 14. Deployment Checklist

### Pre-Deployment

- [ ] Azure subscription access confirmed
- [ ] Resource group created
- [ ] User-assigned managed identity created
- [ ] Graph API permissions granted and consented
- [ ] Event Hub namespace and hub created
- [ ] Event Hub role assignment created
- [ ] Parameters file configured
- [ ] Bicep template validated

### Deployment

- [ ] Infrastructure deployed successfully
- [ ] Function App running
- [ ] Application Insights operational
- [ ] Code deployed to Function App
- [ ] Environment variables verified

### Post-Deployment

- [ ] HTTP trigger tested successfully
- [ ] Timer trigger schedule confirmed
- [ ] Module loading verified
- [ ] Event Hub message delivery confirmed
- [ ] Application Insights telemetry visible
- [ ] Alert rules configured
- [ ] Documentation updated with environment details

### Production Readiness

- [ ] Security hardening applied
- [ ] Monitoring dashboard created
- [ ] Backup procedures documented
- [ ] Disaster recovery plan defined
- [ ] Runbooks created for operations team
- [ ] Performance baseline established

## 15. Version History

| Version | Date       | Changes                  |
| ------- | ---------- | ------------------------ |
| 1.0     | 2025-10-01 | Initial deployment guide |
