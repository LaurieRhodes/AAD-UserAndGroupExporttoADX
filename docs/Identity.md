# Managed Identity Configuration

Version 1.0  
Last Modified: 2025-10-01

## Overview

The AAD User and Group Export to ADX Function App uses a user-assigned managed identity for password-less authentication to Microsoft Graph API and Azure Event Hubs.

## Required Permissions

### Microsoft Graph API Permissions

The managed identity requires the following Microsoft Graph application permissions:

| Permission             | Purpose                               | Scope    |
| ---------------------- | ------------------------------------- | -------- |
| `User.Read.All`        | Read all user profiles and properties | Required |
| `Group.Read.All`       | Read all groups and group properties  | Required |
| `GroupMember.Read.All` | Read group membership relationships   | Required |

**Note:** These are **application permissions** (not delegated permissions) and require admin consent.

### Azure Event Hubs Permissions

The managed identity requires the following Azure RBAC role:

| Role                           | Scope                                     | Purpose                    |
| ------------------------------ | ----------------------------------------- | -------------------------- |
| `Azure Event Hubs Data Sender` | Event Hub namespace or specific Event Hub | Send messages to Event Hub |

## Setup Instructions

### Step 1: Create User-Assigned Managed Identity

#### Option A: Azure Portal

1. Navigate to **Managed Identities** in the Azure Portal
2. Select **Create**
3. Configure:
   - **Subscription**: Select your subscription
   - **Resource group**: Select or create resource group
   - **Region**: Select deployment region (e.g., Australia East)
   - **Name**: Provide meaningful name (e.g., `aad-export-identity`)
4. Select **Review + Create**
5. Select **Create**
6. After creation, note the following values:
   - **Object (principal) ID**: Required for permission assignment
   - **Client ID**: Required for Function App configuration

#### Option B: Azure CLI

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

echo "Identity ID: $IDENTITY_ID"
echo "Client ID: $CLIENT_ID"
echo "Principal ID: $PRINCIPAL_ID"
```

### Step 2: Assign Microsoft Graph Permissions

**Prerequisites:**

- Azure AD Global Administrator or Privileged Role Administrator role
- PowerShell 7.4 or later
- Microsoft Graph PowerShell SDK

#### Option A: Microsoft Graph PowerShell (Recommended)

```powershell
# Install Microsoft Graph module (if not already installed)
Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force

# Connect to Microsoft Graph with required scopes
Connect-MgGraph -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All"

# Get managed identity service principal
$managedIdentityObjectId = "YOUR-MANAGED-IDENTITY-OBJECT-ID-HERE"
$managedIdentitySP = Get-MgServicePrincipal -Filter "id eq '$managedIdentityObjectId'"

# Get Microsoft Graph service principal
$graphSP = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Define required permissions with their App Role IDs
$permissions = @(
    @{
        Name = "User.Read.All"
        Id = "df021288-bdef-4463-88db-98f22de89214"
    },
    @{
        Name = "Group.Read.All"
        Id = "5b567255-7703-4780-807c-7be8301ae99b"
    },
    @{
        Name = "GroupMember.Read.All"
        Id = "98830695-27a2-44f7-8c18-0c3ebc9698f6"
    }
)

# Assign each permission
foreach ($permission in $permissions) {
    try {
        $params = @{
            ServicePrincipalId = $managedIdentitySP.Id
            PrincipalId = $managedIdentitySP.Id
            ResourceId = $graphSP.Id
            AppRoleId = $permission.Id
        }

        New-MgServicePrincipalAppRoleAssignment @params
        Write-Host "✓ Successfully assigned $($permission.Name)" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Message -like "*Permission being assigned already exists*") {
            Write-Host "⚠ $($permission.Name) already assigned" -ForegroundColor Yellow
        }
        else {
            Write-Error "✗ Failed to assign $($permission.Name): $($_.Exception.Message)"
        }
    }
}

Write-Host "`nPermission assignment complete." -ForegroundColor Cyan
Write-Host "Note: Permissions may take up to 24 hours to fully propagate." -ForegroundColor Yellow
```

#### Option B: Azure AD PowerShell (Legacy)

```powershell
# Install Azure AD module (if not already installed)
Install-Module -Name AzureAD -Force

# Connect to Azure AD
Connect-AzureAD

# Get managed identity service principal
$MIObjectId = 'YOUR-MANAGED-IDENTITY-OBJECT-ID-HERE'
$MI = Get-AzureADServicePrincipal -ObjectId $MIObjectId

# Get Microsoft Graph service principal
$MSGraphAppId = '00000003-0000-0000-c000-000000000000'
$MSGraphServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$MSGraphAppId'"

# Assign User.Read.All permission
$UserReadPermission = 'User.Read.All'
$UserAppRole = $MSGraphServicePrincipal.AppRoles | 
    Where-Object {$_.Value -eq $UserReadPermission -and $_.AllowedMemberTypes -contains 'Application'}

if ($UserAppRole) {
    New-AzureADServiceAppRoleAssignment `
        -ObjectId $MI.ObjectId `
        -PrincipalId $MI.ObjectId `
        -ResourceId $MSGraphServicePrincipal.ObjectId `
        -Id $UserAppRole.Id
    Write-Host "✓ Successfully assigned $UserReadPermission" -ForegroundColor Green
} else {
    Write-Error "✗ Could not find $UserReadPermission role"
}

# Assign Group.Read.All permission
$GroupReadPermission = 'Group.Read.All'
$GroupAppRole = $MSGraphServicePrincipal.AppRoles | 
    Where-Object {$_.Value -eq $GroupReadPermission -and $_.AllowedMemberTypes -contains 'Application'}

if ($GroupAppRole) {
    New-AzureADServiceAppRoleAssignment `
        -ObjectId $MI.ObjectId `
        -PrincipalId $MI.ObjectId `
        -ResourceId $MSGraphServicePrincipal.ObjectId `
        -Id $GroupAppRole.Id
    Write-Host "✓ Successfully assigned $GroupReadPermission" -ForegroundColor Green
} else {
    Write-Error "✗ Could not find $GroupReadPermission role"
}

# Assign GroupMember.Read.All permission
$GroupMemberPermission = 'GroupMember.Read.All'
$GroupMemberAppRole = $MSGraphServicePrincipal.AppRoles | 
    Where-Object {$_.Value -eq $GroupMemberPermission -and $_.AllowedMemberTypes -contains 'Application'}

if ($GroupMemberAppRole) {
    New-AzureADServiceAppRoleAssignment `
        -ObjectId $MI.ObjectId `
        -PrincipalId $MI.ObjectId `
        -ResourceId $MSGraphServicePrincipal.ObjectId `
        -Id $GroupMemberAppRole.Id
    Write-Host "✓ Successfully assigned $GroupMemberPermission" -ForegroundColor Green
} else {
    Write-Error "✗ Could not find $GroupMemberPermission role"
}

Write-Host "`nPermission assignment complete." -ForegroundColor Cyan
Write-Host "Note: Permissions may take up to 24 hours to fully propagate." -ForegroundColor Yellow
```

### Step 3: Assign Event Hub Permissions

#### Option A: Azure Portal

1. Navigate to your **Event Hub namespace**
2. Select **Access control (IAM)**
3. Select **Add role assignment**
4. Select role: **Azure Event Hubs Data Sender**
5. Select **Managed identity** as the member type
6. Select your managed identity
7. Select **Review + assign**

#### Option B: Azure CLI

```bash
# Get managed identity principal ID
PRINCIPAL_ID=$(az identity show \
  --name aad-export-identity \
  --resource-group your-rg \
  --query principalId -o tsv)

# Assign Event Hubs Data Sender role
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Azure Event Hubs Data Sender" \
  --scope "/subscriptions/{subscription-id}/resourceGroups/your-rg/providers/Microsoft.EventHub/namespaces/your-eh-namespace"

echo "✓ Event Hub permissions assigned"
echo "Note: Role assignments may take up to 30 minutes to propagate."
```

#### Option C: Azure PowerShell

```powershell
# Get managed identity details
$identity = Get-AzUserAssignedIdentity `
    -ResourceGroupName "your-rg" `
    -Name "aad-export-identity"

# Get Event Hub namespace
$eventHubNamespace = Get-AzEventHubNamespace `
    -ResourceGroupName "your-rg" `
    -Name "your-eh-namespace"

# Assign role
New-AzRoleAssignment `
    -ObjectId $identity.PrincipalId `
    -RoleDefinitionName "Azure Event Hubs Data Sender" `
    -Scope $eventHubNamespace.Id

Write-Host "✓ Event Hub permissions assigned" -ForegroundColor Green
Write-Host "Note: Role assignments may take up to 30 minutes to propagate." -ForegroundColor Yellow
```

## Verification

### Verify Microsoft Graph Permissions

#### Portal Verification

1. Navigate to **Azure Active Directory** > **Enterprise applications**
2. Search for your managed identity by **Client ID**
3. Select **Permissions**
4. Verify the following permissions are listed with status **Granted for {tenant}**:
   - User.Read.All
   - Group.Read.All
   - GroupMember.Read.All

#### PowerShell Verification

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.Read.All"

# Get managed identity
$managedIdentityObjectId = "YOUR-OBJECT-ID"
$managedIdentitySP = Get-MgServicePrincipal -Filter "id eq '$managedIdentityObjectId'"

# Get assigned app roles
$appRoleAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentitySP.Id

# Get Graph service principal for name resolution
$graphSP = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Display assigned permissions
Write-Host "`nAssigned Microsoft Graph Permissions:" -ForegroundColor Cyan
foreach ($assignment in $appRoleAssignments) {
    if ($assignment.ResourceId -eq $graphSP.Id) {
        $appRole = $graphSP.AppRoles | Where-Object { $_.Id -eq $assignment.AppRoleId }
        Write-Host "  ✓ $($appRole.Value)" -ForegroundColor Green
    }
}
```

### Verify Event Hub Permissions

```bash
# List role assignments for managed identity
az role assignment list \
  --assignee $PRINCIPAL_ID \
  --all \
  --query "[?roleDefinitionName=='Azure Event Hubs Data Sender'].{Role:roleDefinitionName, Scope:scope}" \
  --output table
```

### Test Authentication

Test managed identity authentication from Function App:

```powershell
# Test Graph API token acquisition
$token = Get-AzureADToken -resource "https://graph.microsoft.com" -clientId $env:CLIENTID

if ($token) {
    Write-Host "✓ Graph API authentication successful" -ForegroundColor Green
} else {
    Write-Error "✗ Graph API authentication failed"
}

# Test Event Hub token acquisition
$ehToken = Get-AzureADToken -resource "https://eventhubs.azure.net" -clientId $env:CLIENTID

if ($ehToken) {
    Write-Host "✓ Event Hub authentication successful" -ForegroundColor Green
} else {
    Write-Error "✗ Event Hub authentication failed"
}
```

## Troubleshooting

### Permission Assignment Failures

**Symptom:** `Insufficient privileges to complete the operation`

**Resolution:**

- Verify you have Global Administrator or Privileged Role Administrator role
- Ensure you're connected to the correct tenant
- Try using Microsoft Graph PowerShell instead of Azure AD PowerShell

**Symptom:** `Permission being assigned already exists`

**Resolution:**

- This is informational, not an error
- Permission is already assigned correctly
- No action required

### Authentication Failures

**Symptom:** 401 Unauthorized errors when calling Graph API

**Resolution:**

1. Verify permissions are assigned (see Verification section above)
2. Wait 24 hours after permission assignment for propagation
3. Restart Function App after permission changes
4. Verify CLIENTID environment variable matches managed identity Client ID

**Symptom:** 403 Forbidden errors when sending to Event Hub

**Resolution:**

1. Verify Event Hub role assignment exists
2. Wait 30 minutes after role assignment for propagation
3. Verify EVENTHUBNAMESPACE and EVENTHUBNAME environment variables are correct
4. Check Event Hub exists and is active

### Propagation Delays

**Microsoft Permissions with Managed Identities:**

- Typical: 5-10 minutes
- Maximum: Up to 24 hours with User Defined Managed Identities!!!!

## Security Considerations

### Least Privilege

The assigned permissions follow the principle of least privilege:

- **User.Read.All**: Required to read user objects and properties
- **Group.Read.All**: Required to read group objects and properties
- **GroupMember.Read.All**: Required to read group membership relationships

No write or delete permissions are granted.

### Permission Scope

All permissions are **application-level** (not delegated):

- Function executes with managed identity's permissions
- No user context required
- Suitable for automated background processes

# 

## Reference

### Microsoft Graph Permission IDs

| Permission           | App Role ID                          |
| -------------------- | ------------------------------------ |
| User.Read.All        | df021288-bdef-4463-88db-98f22de89214 |
| Group.Read.All       | 5b567255-7703-4780-807c-7be8301ae99b |
| GroupMember.Read.All | 98830695-27a2-44f7-8c18-0c3ebc9698f6 |

### Microsoft Graph Service Principal

- **App ID**: 00000003-0000-0000-c000-000000000000
- **Display Name**: Microsoft Graph
- **App Owner Tenant ID**: f8cdef31-a31e-4b4a-93e4-5f571e91255a

## Complete Setup Script

```powershell
<#
.SYNOPSIS
    Complete managed identity setup for AAD User and Group Export to ADX
.DESCRIPTION
    Creates managed identity and assigns all required permissions for Graph API and Event Hubs
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$ManagedIdentityName,

    [Parameter(Mandatory=$true)]
    [string]$EventHubNamespaceName,

    [Parameter(Mandatory=$true)]
    [string]$Location = "australiaeast"
)

Write-Host "=== AAD Export Managed Identity Setup ===" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName"
Write-Host "Identity Name: $ManagedIdentityName"
Write-Host "Event Hub Namespace: $EventHubNamespaceName"
Write-Host "Location: $Location`n"

# Step 1: Create managed identity
Write-Host "Step 1: Creating managed identity..." -ForegroundColor Yellow
$identity = New-AzUserAssignedIdentity `
    -ResourceGroupName $ResourceGroupName `
    -Name $ManagedIdentityName `
    -Location $Location

Write-Host "✓ Managed identity created" -ForegroundColor Green
Write-Host "  Object ID: $($identity.PrincipalId)"
Write-Host "  Client ID: $($identity.ClientId)`n"

# Step 2: Assign Microsoft Graph permissions
Write-Host "Step 2: Assigning Microsoft Graph permissions..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All"

$managedIdentitySP = Get-MgServicePrincipal -Filter "id eq '$($identity.PrincipalId)'"
$graphSP = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

$permissions = @(
    @{ Name = "User.Read.All"; Id = "df021288-bdef-4463-88db-98f22de89214" },
    @{ Name = "Group.Read.All"; Id = "5b567255-7703-4780-807c-7be8301ae99b" },
    @{ Name = "GroupMember.Read.All"; Id = "98830695-27a2-44f7-8c18-0c3ebc9698f6" }
)

foreach ($permission in $permissions) {
    try {
        New-MgServicePrincipalAppRoleAssignment `
            -ServicePrincipalId $managedIdentitySP.Id `
            -PrincipalId $managedIdentitySP.Id `
            -ResourceId $graphSP.Id `
            -AppRoleId $permission.Id
        Write-Host "  ✓ $($permission.Name)" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Message -like "*already exists*") {
            Write-Host "  ⚠ $($permission.Name) already assigned" -ForegroundColor Yellow
        }
        else {
            Write-Error "  ✗ $($permission.Name): $($_.Exception.Message)"
        }
    }
}

# Step 3: Assign Event Hub permissions
Write-Host "`nStep 3: Assigning Event Hub permissions..." -ForegroundColor Yellow
$eventHubNamespace = Get-AzEventHubNamespace `
    -ResourceGroupName $ResourceGroupName `
    -Name $EventHubNamespaceName

New-AzRoleAssignment `
    -ObjectId $identity.PrincipalId `
    -RoleDefinitionName "Azure Event Hubs Data Sender" `
    -Scope $eventHubNamespace.Id `
    -ErrorAction SilentlyContinue

Write-Host "✓ Event Hub permissions assigned`n" -ForegroundColor Green

Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host "`nIMPORTANT NOTES:" -ForegroundColor Yellow
Write-Host "1. Microsoft Graph permissions may take up to 24 hours to propagate"
Write-Host "2. Event Hub permissions may take up to 30 minutes to propagate"
Write-Host "3. Save the following values for Function App configuration:"
Write-Host "   - Client ID: $($identity.ClientId)"
Write-Host "   - Object ID: $($identity.PrincipalId)"
Write-Host "   - Resource ID: $($identity.Id)"
```

## Version History

| Version | Date       | Changes                                      |
| ------- | ---------- | -------------------------------------------- |
| 1.0     | 2025-10-01 | Initial documentation for AAD export project |
