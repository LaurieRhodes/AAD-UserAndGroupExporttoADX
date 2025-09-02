<#
  PURPOSE:  Submit JSON to Event Hubs with enhanced error handling
  REQUIRES:

  Function App Environment Variables set for:
	EVENTHUBNAMESPACE
	EVENTHUBNAME  (Note: was EVENTHUB in previous version)
	CLIENTID

  And the user-assigned managed identity needs:
  - Azure Event Hubs Data Sender role on the Event Hub
#>

function Send-EventsToEventHub {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Payload
    )

    # Validate required environment variables - CORRECTED VARIABLE NAMES
    $requiredVars = @{
        'EVENTHUBNAMESPACE' = $env:EVENTHUBNAMESPACE
        'EVENTHUBNAME' = $env:EVENTHUBNAME  # Changed from EVENTHUB to EVENTHUBNAME
        'CLIENTID' = $env:CLIENTID
    }
    
    $missingVars = @()
    $presentVars = @()
    
    foreach ($var in $requiredVars.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace($var.Value)) {
            $missingVars += $var.Key
        } else {
            $presentVars += "$($var.Key)=$($var.Value.Substring(0, [Math]::Min(8, $var.Value.Length)))..."
        }
    }
    
    Write-Information "Event Hub Environment Variables Check:"
    Write-Information "Present: $($presentVars -join ', ')"
    if ($missingVars.Count -gt 0) {
        Write-Information "Missing: $($missingVars -join ', ')"
    }
    
    if ($missingVars.Count -gt 0) {
        $errorMessage = "Missing required environment variables for Event Hub: $($missingVars -join ', '). Cannot proceed with Event Hub data transmission."
        Write-Error $errorMessage
        throw [System.Configuration.ConfigurationErrorsException]::new($errorMessage)
    }

    # Ensure EventHub messages do not exceed the size limit
    $maxPayloadSize = 900KB

    # Parse the JSON payload into an object
    try {
        $PayloadObject = ConvertFrom-Json -InputObject $Payload
        Write-Information "Parsed payload: $($PayloadObject.Count) records"
    }
    catch {
        $errorMessage = "Invalid JSON payload: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw [System.ArgumentException]::new($errorMessage)
    }

    # Initialize variables for chunking
    $chunk = @()
    $messages = @()
    $currentSize = 0

    foreach ($record in $PayloadObject) {
        $recordJson = ConvertTo-Json -InputObject $record -Depth 50
        $recordSize = [System.Text.Encoding]::UTF8.GetByteCount($recordJson)

        if (($currentSize + $recordSize) -ge $maxPayloadSize) {
            $messages += ,@($chunk)
            $chunk = @()
            $currentSize = 0
        }
        
        $chunk += $record
        $currentSize += $recordSize
    }

    # Add remaining chunk if it wasn't sent
    if ($chunk.Count -gt 0) {
        $messages += ,@($chunk)
    }

    # CORRECTED: Use EVENTHUBNAME instead of EVENTHUB
    $EventHubUri = "https://$($env:EVENTHUBNAMESPACE).servicebus.windows.net/$($env:EVENTHUBNAME)/messages"
    Write-Information "Sending $($messages.Count) message chunks to Event Hub: $EventHubUri"

    $successfulChunks = 0
    $totalChunks = $messages.Count

    foreach ($chunk in $messages) {
        try {
            # Get Event Hub Token with enhanced error handling
            Write-Debug "Acquiring Event Hub token for resource: https://eventhubs.azure.net"
            
            $EHtoken = Get-AzureADToken -resource "https://eventhubs.azure.net" -clientId $env:CLIENTID
            
            if ([string]::IsNullOrWhiteSpace($EHtoken)) {
                throw [System.Security.Authentication.AuthenticationException]::new("Event Hub token acquisition returned empty token")
            }
            
            Write-Debug "Event Hub token acquired successfully"

            $jsonPayload = ConvertTo-Json -InputObject $chunk -Depth 50
            $payloadSizeKB = [Math]::Round([System.Text.Encoding]::UTF8.GetByteCount($jsonPayload)/1024, 2)

            $headers = @{
                'content-type'  = 'application/json'
                'authorization' = "Bearer $($EHtoken)"
                'Content-Length' = [System.Text.Encoding]::UTF8.GetByteCount($jsonPayload)
            }

            Write-Information "Sending chunk $($successfulChunks + 1) of $totalChunks (Size: $payloadSizeKB KB)"

            # Send the request
            if ($PSVersionTable.PSEdition -eq 'Core') {
                $Response = Invoke-RestMethod -Uri $EventHubUri -Method Post -Headers $headers -Body $jsonPayload -SkipHeaderValidation -SkipCertificateCheck
            } else {
                $Response = Invoke-RestMethod -Uri $EventHubUri -Method Post -Headers $headers -Body $jsonPayload
            }

            $successfulChunks++
            Write-Information "Successfully sent chunk $successfulChunks of $totalChunks to Event Hub"

        } catch {
            $chunkError = "Event Hub transmission failed for chunk $($successfulChunks + 1) of $totalChunks"
            $exceptionMessage = $_.Exception.Message
            Write-Error "$chunkError - $exceptionMessage"
            
            # Enhanced error diagnostics for Event Hub issues
            if ($exceptionMessage -match "401|unauthorized") {
                Write-Error "EVENT HUB PERMISSION ERROR - This is a FATAL configuration issue"
                Write-Error "1. Managed Identity '$($env:CLIENTID)' needs 'Azure Event Hubs Data Sender' role"
                Write-Error "2. Role assignment on Event Hub Namespace: '$($env:EVENTHUBNAMESPACE)'"
                Write-Error "3. Target Event Hub: '$($env:EVENTHUBNAME)'"
                Write-Error "4. NOTE: Managed identity permissions can take up to 24 hours to propagate"
                Write-Error "5. RECOMMENDATION: Wait 24 hours after role assignment or use alternative authentication"
                
                # This is a fatal error - don't retry
                throw [System.Security.Authentication.AuthenticationException]::new("Event Hub authentication failed - managed identity lacks required permissions", $_.Exception)
            }
            elseif ($exceptionMessage -match "403|forbidden") {
                Write-Error "EVENT HUB AUTHORIZATION ERROR - Managed identity has insufficient permissions"
                throw [System.UnauthorizedAccessException]::new("Event Hub authorization failed - check role assignments", $_.Exception)
            }
            elseif ($exceptionMessage -match "404|not found") {
                Write-Error "EVENT HUB NOT FOUND - Check namespace and Event Hub names"
                Write-Error "Namespace: '$($env:EVENTHUBNAMESPACE)'"
                Write-Error "Event Hub: '$($env:EVENTHUBNAME)'"
                throw [System.ArgumentException]::new("Event Hub configuration error - resource not found", $_.Exception)
            }
            else {
                # For other errors, provide generic guidance
                Write-Error "EVENT HUB COMMUNICATION ERROR: $exceptionMessage"
                throw [System.Net.WebException]::new($chunkError, $_.Exception)
            }
        }
    }

    Write-Information "Successfully transmitted all $successfulChunks chunks to Event Hub"
    return @{
        ChunksSent = $successfulChunks
        TotalChunks = $totalChunks
        Success = ($successfulChunks -eq $totalChunks)
        EventHubUri = $EventHubUri
    }
}