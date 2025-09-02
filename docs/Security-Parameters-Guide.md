# Security Guide - Parameters and Deployment Configuration

## Overview

This guide outlines security practices for managing deployment parameters and configuration files containing sensitive information like resource IDs, subscription details, and connection strings.

## Protected Files

### Primary Protection
The `.gitignore` file protects these sensitive parameter files:

```
infrastructure/parameters.json              # Your actual deployment parameters
infrastructure/parameters.*.json            # Environment-specific parameters  
infrastructure/local.parameters.json        # Local development parameters
infrastructure/dev.parameters.json          # Development environment
infrastructure/prod.parameters.json         # Production environment
infrastructure/test.parameters.json         # Test environment
```

### Example File (Safe to Commit)
```
infrastructure/parameters.example.json      # ✅ Template with placeholder values
```

## Creating Your Parameters File

### Step 1: Copy the Example
```bash
# Create your actual parameters file from the example
cd infrastructure
cp parameters.example.json parameters.json
```

### Step 2: Update with Real Values
Edit `parameters.json` with your actual Azure resource information:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "Australia SouthEast"
    },
    "resourceGroupID": {
      "value": "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-aad-export-prod"
    },
    "functionAppName": {
      "value": "func-aad-export-prod-001"
    },
    "storageAccountName": {
      "value": "staadexportprod001"
    },
    "applicationInsightsName": {
      "value": "appi-aad-export-prod"
    },
    "userAssignedIdentityResourceId": {
      "value": "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-identity/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-aad-export"
    },
    "eventHubNamespace": {
      "value": "evhns-security-prod"
    },
    "eventHubName": {
      "value": "evh-aad-data"
    }
  }
}
```

### Step 3: Verify Protection
```bash
# Check that your parameters file is ignored
git status
# Should NOT show infrastructure/parameters.json as untracked

# Verify gitignore is working
git check-ignore infrastructure/parameters.json
# Should return: infrastructure/parameters.json
```

## Multi-Environment Management

### Environment-Specific Files
Create separate parameter files for each environment:

```bash
# Development environment
infrastructure/parameters.dev.json

# Production environment  
infrastructure/parameters.prod.json

# Test environment
infrastructure/parameters.test.json
```

### Deployment Commands
```bash
# Deploy to development
az deployment group create --resource-group rg-aad-export-dev --template-file main.bicep --parameters @parameters.dev.json

# Deploy to production
az deployment group create --resource-group rg-aad-export-prod --template-file main.bicep --parameters @parameters.prod.json
```

## Additional Security Measures

### Local Settings Protection
The `.gitignore` also protects Function App local settings:

```
local.settings.json              # Function App local configuration
*.local.settings.json           # Environment-specific local settings
```

### Environment Variables
For local development, use environment variables instead of hardcoded values:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "powershell",
    "CLIENTID": "your-managed-identity-client-id",
    "EVENTHUBNAMESPACE": "your-eventhub-namespace",
    "EVENTHUBNAME": "your-eventhub-name"
  }
}
```

## Verification Commands

### Check Git Status
```bash
# Verify no sensitive files are tracked
git status --ignored

# Show what files are being ignored
git ls-files --others --ignored --exclude-standard
```

### Test Protection
```bash
# Try to add a parameters file (should be ignored)
echo '{"test":"sensitive"}' > infrastructure/parameters.json
git add infrastructure/parameters.json
# Should show: "The following paths are ignored by one of your .gitignore files"
```

## Best Practices

### File Naming Conventions
- ✅ **Use**: `parameters.example.json` (template)
- ✅ **Use**: `parameters.dev.json` (environment-specific)
- ❌ **Avoid**: `parameters-real.json` (not protected by gitignore)
- ❌ **Avoid**: `my-parameters.json` (not protected by gitignore)

### Documentation Updates
When adding new parameters to the example file:

1. **Add to example**: Update `parameters.example.json` with placeholder
2. **Document purpose**: Add comments explaining the parameter
3. **Update security guide**: Note any security considerations

### Team Collaboration
- **Share example file**: Commit changes to `parameters.example.json`
- **Never share actual files**: Keep `parameters.json` local only
- **Document requirements**: Update README with parameter descriptions
- **Use secure channels**: Share sensitive values via secure methods (Azure Key Vault, encrypted channels)

## Emergency Procedures

### If Sensitive Data Is Accidentally Committed

#### Immediate Actions
```bash
# 1. Remove the sensitive file
git rm --cached infrastructure/parameters.json

# 2. Commit the removal
git commit -m "Remove sensitive parameters file"

# 3. Push immediately
git push origin main
```

#### Clean Git History (If Necessary)
```bash
# WARNING: This rewrites history and affects all collaborators
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch infrastructure/parameters.json' \
  --prune-empty --tag-name-filter cat -- --all

# Force push (coordinate with team first)
git push origin --force --all
```

#### Rotate Affected Resources
1. **Change subscription keys** if exposed
2. **Rotate managed identity** if Client ID was exposed  
3. **Review access logs** for any unauthorized access
4. **Update team** about the security incident

## Monitoring and Compliance

### Regular Security Reviews
- **Monthly**: Review `.gitignore` effectiveness
- **Before releases**: Verify no sensitive files in commits
- **After onboarding**: Train new team members on parameter security

### Compliance Checks
```bash
# Audit script to check for sensitive files
git log --name-only --oneline | grep -E "(parameters\.json|local\.settings\.json|\.env)" | head -20
# Should only show example/template files
```

This security approach ensures sensitive deployment parameters are never accidentally committed while maintaining a collaborative development environment with proper template files for team reference.
