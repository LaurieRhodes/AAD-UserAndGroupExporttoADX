<#
.SYNOPSIS
    Deployment script for AAD-UserAndGroupExporttoADX Function App.

.DESCRIPTION
    Deploys Azure infrastructure using Bicep and uploads Function App code.
    Reads configuration from parameters.json with flat error handling.

.PARAMETER SkipInfrastructure
    Skip infrastructure deployment, only deploy code.

.PARAMETER ValidateOnly
    Only validate Bicep template without deploying.

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -SkipInfrastructure
    .\deploy.ps1 -ValidateOnly

.NOTES
    Author: Laurie Rhodes
    Version: 3.4 - Clean Rewrite
    Uses flat error handling - no nested try/catch blocks
#>

[CmdletBinding()]
param (
    [switch]$SkipInfrastructure
)

$ErrorActionPreference = "Stop"

$configFile = ".\infrastructure\parameters.json"
$bicepTemplate = ".\infrastructure\main.bicep"
$sourceCode = ".\src\FunctionApp"

Write-Host "AAD Export Function App Deployment" -ForegroundColor Cyan

if (-not (Test-Path $configFile)) {
    Write-Error "❌ Configuration file not found: $configFile"
    exit 1
}

$config = (Get-Content $configFile | ConvertFrom-Json).parameters
$resourceGroupName = ($config.resourceGroupID.value -split '/resourceGroups/')[1]
$functionAppName = $config.functionAppName.value
$subscriptionId = ($config.resourceGroupID.value -split '/')[2]

az account set --subscription $subscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set Azure subscription context"
    exit 1
}

if (-not $SkipInfrastructure) {
    Write-Host "Deploying infrastructure..." -ForegroundColor Blue
    
    $deployCmd = if ($ValidateOnly) { "validate" } else { "create" }
    
    az deployment group $deployCmd --resource-group $resourceGroupName --template-file $bicepTemplate --parameters $configFile --name "aadexport-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Infrastructure deployment failed"
        exit 1
    }
    
    Write-Host "Infrastructure operation completed" -ForegroundColor Green
}


    Write-Host "Deploying code..." -ForegroundColor Blue
    
    if (-not (Get-Module -ListAvailable Az.Websites)) {
        Write-Error "Az.Websites module required. Install with: Install-Module Az.Websites"
        exit 1
    }
    
    Import-Module Az.Websites
    
    $azContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $azContext) {
        Connect-AzAccount -Subscription $subscriptionId | Out-Null
    }
    
    $functionApp = Get-AzWebApp -ResourceGroupName $resourceGroupName -Name $functionAppName -ErrorAction SilentlyContinue
    if (-not $functionApp) {
        Write-Error "Function App $functionAppName not found"
        exit 1
    }
    
    $tempZip = "$env:TEMP\functionapp-$(Get-Date -Format 'HHmmss').zip"
    if (Test-Path $tempZip) {
        Remove-Item $tempZip -Force
    }
    
    Compress-Archive -Path "$sourceCode\*" -DestinationPath $tempZip -Force
    
    $publishProfile = Get-AzWebAppPublishingProfile -ResourceGroupName $resourceGroupName -Name $functionAppName
    $xmlProfile = [xml]$publishProfile
    $creds = $xmlProfile.SelectSingleNode("//publishProfile[@publishMethod='MSDeploy']")
    
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($creds.userName):$($creds.userPWD)"))
    $headers = @{ Authorization = "Basic $auth"; 'Content-Type' = "application/zip" }
    $deployUrl = "https://$functionAppName.scm.azurewebsites.net/api/zipdeploy"
    
    Invoke-RestMethod -Uri $deployUrl -Headers $headers -Method POST -InFile $tempZip -TimeoutSec 180
    
    Remove-Item $tempZip -Force
    
    $syncUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Web/sites/$functionAppName/syncfunctiontriggers?api-version=2024-11-01"
    $token = (Get-AzAccessToken).Token
    $syncHeaders = @{ 'Authorization' = "Bearer $token" }
    
    $ErrorActionPreference = "SilentlyContinue"
    Invoke-RestMethod -Uri $syncUrl -Headers $syncHeaders -Method POST -TimeoutSec 30
    if ($Error[0]) {
        Write-Host "Trigger sync failed, restarting Function App..." -ForegroundColor Yellow
        Restart-AzWebApp -ResourceGroupName $resourceGroupName -Name $functionAppName
    }
    $ErrorActionPreference = "Stop"
    
    Write-Host "Code deployed" -ForegroundColor Green

Write-Host "Deployment completed!" -ForegroundColor Green
