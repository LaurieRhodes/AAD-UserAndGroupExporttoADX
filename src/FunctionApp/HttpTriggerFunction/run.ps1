param($httpobj)

# Set up logging preferences
$DebugPreference = "Continue"
$InformationPreference = "Continue"

# Initialize HTTP execution context
$requestId = [System.Guid]::NewGuid().ToString()
Write-Information "=============================================="
Write-Information "HTTP Trigger Function Started - Core Export Mode"
Write-Information "Request ID: $requestId"
Write-Information "Method: $($httpobj.Method)"
Write-Information "Current Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
Write-Information "=============================================="

try {
    # Validate HTTP method
    if ($httpobj.Method -notin @('GET', 'POST')) {
        Write-Warning "Unsupported HTTP method: $($httpobj.Method)"
        
        return @{
            statusCode = 405
            headers = @{
                'Content-Type' = 'application/json'
            }
            body = @{
                error = "Method Not Allowed"
                message = "Only GET and POST methods are supported"
                requestId = $requestId
            } | ConvertTo-Json
        }
    }

    # For GET requests, return status information
    if ($httpobj.Method -eq 'GET') {
        Write-Information "GET request - returning function status"
        
        $statusInfo = @{
            status = "ready"
            message = "HTTP Trigger Function is operational - Core properties export mode"
            requestId = $requestId
            functionVersion = "2.1-Core"
            timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            mode = "CorePropertiesOnly"
            note = "Extended properties disabled to avoid Graph API URL construction issues"
        }
        
        return @{
            statusCode = 200
            headers = @{
                'Content-Type' = 'application/json'
            }
            body = ($statusInfo | ConvertTo-Json -Depth 3)
        }
    }
    
    # For POST requests, execute AAD data export with core properties only
    Write-Information "POST request - invoking AAD Data Export (Core Properties Mode)"
    
    # Execute the main AAD data export with extended properties disabled
    Write-Information "Starting AAD Data Export via HTTP trigger - Core Properties Only"
    $exportResult = Invoke-AADDataExport -TriggerContext "HTTPTrigger" -IncludeExtendedUserProperties:$false
    
    if ($exportResult.Success) {
        Write-Information "HTTP Trigger completed successfully"
        
        return @{
            statusCode = 202
            headers = @{
                'Content-Type' = 'application/json'
            }
            body = @{
                status = "success"
                message = "AAD data export completed successfully (core properties only)"
                requestId = $requestId
                exportId = $exportResult.ExportId
                mode = "CorePropertiesOnly"
                statistics = @{
                    users = $exportResult.Statistics.Users
                    groups = $exportResult.Statistics.Groups
                    memberships = $exportResult.Statistics.Memberships
                    totalRecords = $exportResult.Statistics.TotalRecords
                    eventHubBatches = $exportResult.Statistics.EventHubBatches
                    duration = @{
                        totalMinutes = $exportResult.Statistics.Duration
                        stages = $exportResult.Statistics.StageTimings
                    }
                }
                execution = @{
                    startTime = $exportResult.StartTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    endTime = $exportResult.EndTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    triggerContext = "HTTPTrigger"
                    architecture = "Modular"
                    graphApiVersion = "v1.0"
                }
                note = "Extended user properties skipped - can be enabled after fixing Graph API URL construction"
            } | ConvertTo-Json -Depth 4
        }
        
    } else {
        Write-Error "HTTP Trigger processing failed"
        
        return @{
            statusCode = 500
            headers = @{
                'Content-Type' = 'application/json'
            }
            body = @{
                status = "export_failed"
                message = "AAD data export encountered errors"
                requestId = $requestId
                exportId = $exportResult.ExportId
                error = @{
                    message = $exportResult.Error.ErrorMessage
                    type = $exportResult.Error.ErrorType
                    timestamp = $exportResult.Error.Timestamp
                }
                troubleshooting = @{
                    correlationId = $exportResult.ExportId
                    recommendation = "Check Application Insights for detailed error information"
                }
            } | ConvertTo-Json -Depth 4
        }
    }
    
} catch {
    Write-Error "Critical error in HTTP Trigger execution: $($_.Exception.Message)"
    
    return @{
        statusCode = 500
        headers = @{
            'Content-Type' = 'application/json'
        }
        body = @{
            status = "critical_error"
            message = "Unhandled exception in HTTP trigger"
            requestId = $requestId
            error = @{
                message = $_.Exception.Message
                type = $_.Exception.GetType().Name
                timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
            troubleshooting = @{
                requestId = $requestId
                recommendation = "Check Function App logs for detailed investigation"
            }
        } | ConvertTo-Json -Depth 3
    }
}