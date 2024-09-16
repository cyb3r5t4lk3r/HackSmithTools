# Define parameters for mode, output, domain, API key, CSE ID, and output file name
param (
    [ValidateSet("passive", "active")]
    [string]$mode = "passive",  # "passive" or "active"
    
    [ValidateSet("blind", "targeted")]
    [string]$searchType = "blind",  # "blind" or "targeted" for passive mode
    
    [ValidateSet("console", "out-gridview", "csv")]
    [string]$output = "console",  # "console", "out-gridview", "csv"
    
    [string]$domain = "",  # Domain for "targeted" searchType
    [string]$apiKey,  # API key for Google Search
    [string]$cseId,  # CSE ID for Google Custom Search Engine
    [string]$outputFile  # Output file name
)

# Define the base URL for Google Search API
$searchUrl = "https://www.googleapis.com/customsearch/v1"
Write-Host "Searching for .git repositories using Google Dorking..." -ForegroundColor Yellow

# Define the search query
if ($mode -eq "passive" -and $searchType -eq "targeted" -and $domain) {
    Write-Host "Google Dorking Query for Targeted search is intext:`"index of .git`" site:$($domain)" -ForegroundColor Green
    $query = "intext:`"index of .git`" site:$($domain)"
} else {
    Write-Host "Google Dorking Query for Blind search is intext:`"index of .git`" site:$($domain)" -ForegroundColor Green
    $query = "intext:`"index of .git`""
}

# Create a function for searching
function Search-Google {
    param (
        [string]$query,
        [string]$apiKey,
        [string]$cseId,
        [int]$startIndex = 1
    )

    $params = @{
        q = $query
        key = $apiKey
        cx = $cseId
        start = $startIndex
    }

    Write-Host "Your CSE key is: $($cseId)" -ForegroundColor Yellow
    Write-Host "Your API key is: $($apiKey)" -ForegroundColor Yellow
    $response = Invoke-RestMethod -Uri $searchUrl -Method Get -Body $params
    return $response
}

# Create a function to extract information from .git/config
function Get-GitConfigInfo {
    param (
        [string]$url
    )

    $configUrl = "$($url)/.git/config"

    try {
        $configContent = Invoke-RestMethod -Uri $configUrl -Method Get
        $configLines = $configContent -split "`n"

        $coreInfo = ""
        $remoteInfo = ""
        $inCore = $false
        $inRemote = $false

        foreach ($line in $configLines) {
            if ($line -match "^\[core\]") {
                $inCore = $true
                $inRemote = $false
                continue
            }
            if ($line -match "^\[remote `"origin`"\]") {
                $inCore = $false
                $inRemote = $true
                continue
            }
            if ($line -match "^\[.*\]") {
                $inCore = $false
                $inRemote = $false
                continue
            }

            if ($inCore) {
                $coreInfo += $line + "`n"
            }
            if ($inRemote) {
                $remoteInfo += $line + "`n"
            }
        }

        return [pscustomobject]@{
            URL = $url
            CoreInfo = $coreInfo
            RemoteInfo = $remoteInfo
        }
    } catch {
        Write-Host "Could not retrieve .git/config from $($url)"
        return $null
    }
}

# Search and process results
$results = @()
$startIndex = 1
do {
    $response = Search-Google -query $query -apiKey $apiKey -cseId $cseId -startIndex $startIndex
        $response.urls
    if ($null -ne $response.items) {
        foreach ($item in $response.items) {
            $uri = [System.Uri]$item.link
            $domainInfo = [pscustomobject]@{
                Domain = $uri.Host
                URL = $item.link
            }

            if ($mode -eq "active") {
                $gitConfigInfo = Get-GitConfigInfo -url $item.link
                if ($gitConfigInfo) {
                    $domainInfo | Add-Member -MemberType NoteProperty -Name CoreInfo -Value $gitConfigInfo.CoreInfo
                    $domainInfo | Add-Member -MemberType NoteProperty -Name RemoteInfo -Value $gitConfigInfo.RemoteInfo
                }
            }

            $results += $domainInfo
        }
        $startIndex += 10
    }

} while ($null -ne $response.items -and $startIndex -le $response.searchInformation.totalResults)

# Output results based on the chosen mode
switch ($output) {
    "console" {
        $results | Format-Table -AutoSize
    }
    "out-gridview" {
        $results | Out-GridView
    }
    "csv" {
        $results | Export-Csv -Path "$($outputFile).csv" -NoTypeInformation
        Write-Host "Results exported to $($outputFile).csv"
    }
    default {
        Write-Host "Invalid output option. Please choose 'console', 'out-gridview', or 'csv'."
    }
}
