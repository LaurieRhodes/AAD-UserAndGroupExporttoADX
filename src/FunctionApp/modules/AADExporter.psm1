#
# AADExporter Module - Azure Active Directory Data Export Module
# Author: Laurie Rhodes
# Version: 3.0
# Created: 2025-08-31
#
# This module provides comprehensive Azure AD data export capabilities
# for integration with Azure Data Explorer via Event Hub.
#

# Import private functions first (if any exist)
$privateFunctions = @(Get-ChildItem -Path $PSScriptRoot\private\*.ps1 -ErrorAction SilentlyContinue)

# Import public functions
$publicFunctions = @(Get-ChildItem -Path $PSScriptRoot\public\*.ps1 -ErrorAction SilentlyContinue)

# Dot source all function files
foreach ($import in @($privateFunctions + $publicFunctions)) {
    try {
        Write-Verbose "Loading function file: $($import.FullName)"
        . $import.FullName
        Write-Verbose "Successfully loaded: $($import.Name)"
    }
    catch {
        Write-Error "Failed to import function $($import.FullName): $($_.Exception.Message)"
        throw
    }
}

# Export only the public functions listed in the manifest
$functionsToExport = @(
    # Core orchestration
    'Invoke-AADDataExport',
    
    # Data export modules
    'Export-AADUsers',
    'Export-AADGroups', 
    'Export-AADGroupMemberships',
    
    # Authentication
    'Get-AzureADToken',
    
    # Event Hub integration
    'Send-EventsToEventHub',
    
    # Error handling and resilience
    'Invoke-WithRetry',
    'Invoke-GraphAPIWithRetry',
    'Get-ErrorType',
    'Test-ShouldRetry',
    'Get-HttpStatusCode',
    
    # Telemetry and monitoring
    'Write-CustomTelemetry',
    'Write-DependencyTelemetry',
    'Write-ExportProgress',
    'New-CorrelationContext',
    
    # Storage utilities
    'Get-AzTableStorageData',
    'Set-AzTableStorageData',
    'Get-Events',
    'Get-StorageTableValue',
    'Push-StorageTableValue'
)

# Only export functions that actually exist to avoid errors
$availableExports = @()
foreach ($functionName in $functionsToExport) {
    if (Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue) {
        $availableExports += $functionName
        Write-Verbose "Function available for export: $functionName"
    }
    else {
        Write-Warning "Function not found and will not be exported: $functionName"
    }
}

Write-Information "AADExporter module loaded. Exporting $($availableExports.Count) functions."
Export-ModuleMember -Function $availableExports