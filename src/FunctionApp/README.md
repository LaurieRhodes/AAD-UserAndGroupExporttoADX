## Deployment Guide

### Prerequisites

1. **Azure Resources Setup**:
   
   - User-Assigned Managed Identity
   - Event Hub Namespace and Event Hub
   - Azure Data Explorer cluster or EventHouse service.

2. **Managed Identity Permissions Configuration**:
   
   ```
   User-Assigned Managed Identity requires:
   - Target Subscription: Reader
   - Target Subscription: User Access Administrator  
   - Event Hub: Azure Event Hubs Data Sender
   ```

**IMPORTANT** User Assigned Managed Identities may take 24 hours for permissions to become active!  Ensure that the Identity and Permissions are assigned well in advance of expecting the project to work.


3. **Customise Bicep**: 




  

### Deployment Steps

1. **Configure Environment Variables** in Azure Function App:
   
   ```
   CLIENTID=<your-managed-identity-client-id>
   EVENTHUBNAMESPACE=<your-eventhub-namespace>
   EVENTHUBNAME=<your-eventhub-name>
   APPLICATIONINSIGHTS_CONNECTION_STRING=<optional>
   ```

2. **Deploy Function Code**:
   
   - Upload all files maintaining directory structure
   - Ensure `AADExporter` module loads correctly via `profile.ps1`

3. **Test Deployment**:
   
   ```http
   GET https://<function-app>.azurewebsites.net/api/HttpTriggerFunction
   ```