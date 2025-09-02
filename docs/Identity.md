## Permissions

One of the following permissions iare required to call the Graph APIs.

| Permission type | Permission             | Permission display name                                              |
| --------------- | ---------------------- | -------------------------------------------------------------------- |
| Application     | Vulnerability.Read.All | 'Read Threat and Vulnerability Management vulnerability information' |
| Application     | Machine.Read.All       | 'Read all machine profiles'                                          |

### Step 1: Create User Assigned Managed Identity

1. Within the Azure Portal select **Managed Identities**.

2. Select **Create**.

3. Provide a meaningful name for the Identity
   
   1. Select a Resource Group for the deployment
   
   2. Select a Region for the deployment

4. Select **Review + Create**.

### Step 2: Assign to Microsoft Graph Roles

1. **Install Azure AD Module (if not already installed) or use Azure cloud shell:**

```powershell
Install-Module -Name AzureAD
```

2. **Connect to Azure AD:**

```powershell
Connect-AzureAD
```

All Microsoft applications exist in Entra as 'Enterprise Applications'

[Microsoft-Owned-Enterprise-Applications/Microsoft Owned Enterprise Applications Overview.md at main · emilyvanputten/Microsoft-Owned-Enterprise-Applications · GitHub](https://github.com/emilyvanputten/Microsoft-Owned-Enterprise-Applications/blob/main/Microsoft%20Owned%20Enterprise%20Applications%20Overview.md)

This Function App will utilise roles from the WindowsDefenderATP application.

| DisplayName     | AppId                                | AppOwnerTenantId                     |
| --------------- | ------------------------------------ | ------------------------------------ |
| Microsoft Graph | 00000003-0000-0000-c000-000000000000 | f8cdef31-a31e-4b4a-93e4-5f571e91255a |

3. **Get the Service Principal for the created Managed Identity:**

```powershell
# 'Enter your managed identity Object (principal) ID'
$MIObjectId = 'YOUR-MANAGED-IDENTITY-OBJECT-ID-HERE'

$MI = Get-AzureADServicePrincipal -ObjectId $MIGuid

# Microsoft Graph App ID is a constant
$MSGraphAppId = '00000003-0000-0000-c000-000000000000'
```

5. **Assign User.Read.All Role to the Managed Identity:**

Find the `AppRole` ID for `User.Read.All and then assign it to the managed identity.

```powershell
# Assign User.Read.All and Group.Read.All roles to the Managed Identity
$MSGraphServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$MSGraphAppId'"

# Assign User.Read.All permission
$UserReadPermission = 'User.Read.All'
$UserAppRole = $MSGraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $UserReadPermission -and $_.AllowedMemberTypes -contains 'Application'}

if ($UserAppRole) {
    New-AzureADServiceAppRoleAssignment -ObjectId $MI.ObjectId -PrincipalId $MI.ObjectId -ResourceId $MSGraphServicePrincipal.ObjectId -Id $UserAppRole.Id
    Write-Host "Successfully assigned $UserReadPermission to Managed Identity" -ForegroundColor Green
} else {
    Write-Error "Could not find $UserReadPermiss Identity:
}
```

6. **Assign Group.Read.All Role to the Managed Identity:**

Find the `AppRole` ID for Group.Read.All` and then assign it to the managed identity.

```powershell
$GroupReadPermission = 'Group.Read.All'
$GroupAppRole = $MSGraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $GroupReadPermission -and $_.AllowedMemberTypes -contains 'Application'}

if ($GroupAppRole) {
    New-AzureADServiceAppRoleAssignment -ObjectId $MI.ObjectId -PrincipalId $MI.ObjectId -ResourceId $MSGraphServicePrincipal.ObjectId -Id $GroupAppRole.Id
    Write-Host "Successfully assigned $GroupReadPermission to Managed Identity" -ForegroundColor Green
} else {
    Write-Error "Could not find $GroupReadPermission role"
}
```

7. **Assign AuditLog.Read.All Role to the Managed Identity:**

Find the `AppRole` ID for `AuditLog.Read.All' and then assign it to the managed identity.

```powershell
# Assign AuditLog.Read.All permission for accessing audit details
$AuditLogPermission = 'AuditLog.Read.All'
$AuditLogAppRole = $MSGraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $AuditLogPermission -and $_.AllowedMemberTypes -contains 'Application'}

if ($AuditLogAppRole) {
    New-AzureADServiceAppRoleAssignment -ObjectId $MI.ObjectId -PrincipalId $MI.ObjectId -ResourceId $MSGraphServicePrincipal.ObjectId -Id $AuditLogAppRole.Id
    Write-Host "Successfully assigned $AuditLogPermission to Managed Identity" -ForegroundColor Green
} else {
    Write-Error "Could not find $AuditLogPermission role"
}
```

``

8. **Assign CustomSecurityAttributes.Read.All Role to the Managed Identity:**

Find the `AppRole` ID for `CustomSecurityAttributes.Read.All' and then assign it to the managed identity.

```powershell
# Assign AuditLog.Read.All permission for accessing audit details
$AuditLogPermission = 'CustomSecurityAttributes.Read.All'
$AuditLogAppRole = $MSGraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $AuditLogPermission -and $_.AllowedMemberTypes -contains 'Application'}

if ($AuditLogAppRole) {
    New-AzureADServiceAppRoleAssignment -ObjectId $MI.ObjectId -PrincipalId $MI.ObjectId -ResourceId $MSGraphServicePrincipal.ObjectId -Id $AuditLogAppRole.Id
    Write-Host "Successfully assigned $AuditLogPermission to Managed Identity" -ForegroundColor Green
} else {
    Write-Error "Could not find $AuditLogPermission role"
}
```

### Example Script

Here’s a complete example script that performs all the necessary steps:

```powershell
# Assign permissions to a Managed Identity for reading user and group information from Azure AD/Entra

# 1. Install Azure AD Module (if not already installed) or use Azure Cloud Shell
Install-Module -Name AzureAD -Force -AllowClobber

# 2. Connect to Azure AD
Connect-AzureAD

# 3. Get the Serice Principal for the created Managed Identity
# Replae with your actual Managed Identity Object (Principal) ID
$MIObjectId = 'YOUR-MANAGED-IDENTITY-OBJECT-ID-HERE'

$MI = Get-AzureADServicePrincipal -ObjectId $MIObjectId

# 4. For reading user and group information, use Microsoft Graph API
# Microsoft Graph App ID is a constant
$MSGraphAppId = '00000003-0000-0000-c000-000000000000'

# 5. Assign User.Read.All and Group.Read.All roles to the Managed Identity
$MSGraphServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$MSGraphAppId'"

# Assign User.Read.All permission
$UserReadPermission = 'User.Read.All'
$UserAppRole = $MSGraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $UserReadPermission -and $_.AllowedMemberTypes -contains 'Application'}

if ($UserAppRole) {
    New-AzureADServiceAppRoleAssignment -ObjectId $MI.ObjectId -PrincipalId $MI.ObjectId -ResourceId $MSGraphServicePrincipal.ObjectId -Id $UserAppRole.Id
    Write-Host "Successfully assigned $UserReadPermission to Managed Identity" -ForegroundColor Green
} else {
    Write-Error "Could not find $UserReadPermission role"
}

# Assign Group.Read.All permission
$GroupReadPermission = 'Group.Read.All'
$GroupAppRole = $MSGraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $GroupReadPermission -and $_.AllowedMemberTypes -contains 'Application'}

if ($GroupAppRole) {
    New-AzureADServiceAppRoleAssignment -ObjectId $MI.ObjectId -PrincipalId $MI.ObjectId -ResourceId $MSGraphServicePrincipal.ObjectId -Id $GroupAppRole.Id
    Write-Host "Successfully assigned $GroupReadPermission to Managed Identity" -ForegroundColor Green
} else {
    Write-Error "Could not find $GroupReadPermission role"
}

# 6. Assign AuditLog.Read.All role to the Managed Identity
# for accessing audit details
$AuditLogPermission = 'AuditLog.Read.All'
$AuditLogAppRole = $MSGraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $AuditLogPermission -and $_.AllowedMemberTypes -contains 'Application'}

if ($AuditLogAppRole) {
    New-AzureADServiceAppRoleAssignment -ObjectId $MI.ObjectId -PrincipalId $MI.ObjectId -ResourceId $MSGraphServicePrincipal.ObjectId -Id $AuditLogAppRole.Id
    Write-Host "Successfully assigned $AuditLogPermission to Managed Identity" -ForegroundColor Green
} else {
    Write-Error "Could not find $AuditLogPermission role"
}

# Assign AuditLog.Read.All permission for accessing audit details
$AuditLogPermission = 'CustomSecurityAttributes.Read.All'
$AuditLogAppRole = $MSGraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $AuditLogPermission -and $_.AllowedMemberTypes -contains 'Application'}

if ($AuditLogAppRole) {
    New-AzureADServiceAppRoleAssignment -ObjectId $MI.ObjectId -PrincipalId $MI.ObjectId -ResourceId $MSGraphServicePrincipal.ObjectId -Id $AuditLogAppRole.Id
    Write-Host "Successfully assigned $AuditLogPermission to Managed Identity" -ForegroundColor Green
} else {
    Write-Error "Could not find $AuditLogPermission role"
}
```

### 
