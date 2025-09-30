# Load required .NET assemblies
Add-Type -AssemblyName 'System.Net.Http'
Add-Type -AssemblyName 'System.Net'
Add-Type -AssemblyName 'System.Net.Primitives'
Add-Type -AssemblyName 'System.Web'

function Get-AzureADToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$resource,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$clientId,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$apiVersion = "2019-08-01"
    )

    begin {
        #$DebugPreference = "Continue"
        Write-Debug "[Get-AzureADToken] Starting token acquisition for resource: $resource"

        if (-not $env:IDENTITY_ENDPOINT) {
            throw "IDENTITY_ENDPOINT environment variable is not set"
        }
        if (-not $env:IDENTITY_HEADER) {
            throw "IDENTITY_HEADER environment variable is not set"
        }
    }

    process {
        try {
            # Build query parameters
            $queryParams = [ordered]@{
                resource = $resource
                client_id = $clientId
                'api-version' = $apiVersion
            }

            # Construct query string properly
            $queryString = ($queryParams.GetEnumerator() | ForEach-Object {
                "{0}={1}" -f [System.Web.HttpUtility]::UrlEncode($_.Key), [System.Web.HttpUtility]::UrlEncode($_.Value)
            }) -join '&'

            $url = "$($env:IDENTITY_ENDPOINT)?$queryString"
            Write-Debug "[Get-AzureADToken] Request URL: $url"

            # Prepare headers
            $headers = @{
                'Metadata' = 'True'
                'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER
            }

            # Make the request with timeout and retry logic
            $maxRetries = 3
            $retryCount = 0
            $retryDelaySeconds = 2

            do {
                try {
                    $response = Invoke-RestMethod -Uri $url -Method 'GET' -Headers $headers -TimeoutSec 30
                    break
                }
                catch {
                    $retryCount++
                    if ($retryCount -eq $maxRetries) {
                        throw
                    }
                    Write-Warning "[Get-AzureADToken] Attempt $retryCount failed. Retrying in $retryDelaySeconds seconds..."
                    Start-Sleep -Seconds $retryDelaySeconds
                    $retryDelaySeconds *= 2  # Exponential backoff
                }
            } while ($retryCount -lt $maxRetries)

            # Validate response
            if (-not $response.access_token) {
                throw "No access token found in response"
            }

            Write-Debug "[Get-AzureADToken] Successfully acquired token"
            return $response.access_token
        }
        catch {
            $errorMessage = "[Get-AzureADToken] Failed to acquire token: $($_.Exception.Message)"
            if ($_.Exception.InnerException) {
                $errorMessage += " Inner Exception: $($_.Exception.InnerException.Message)"
            }
            Write-Error $errorMessage
            throw $errorMessage
        }
    }
}