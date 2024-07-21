<#
.SYNOPSIS
    Script to detect the existence of specific files and directories on a web server.

.DESCRIPTION
    This script checks for the existence of specific files and directories in the root of a website.
    You can specify either a single domain or a file containing a list of domains.
    The script supports output to the console, to a file, or both. Additionally, it can download content from .git directories if directory browsing is enabled.

.PARAMETER domain
    Single domain to be checked.

.PARAMETER domainFile
    File containing a list of domains to be checked.

.PARAMETER outputType
    Type of output: "console" (output to console), "file" (output to file), "both" (output to both console and file).

.PARAMETER logging
    Boolean switch to enable or disable logging to the console for each checked address.

.PARAMETER dumpcontent
    Boolean switch to download the content of the .git directory if found and directory browsing is enabled.

.PARAMETER downloadDir
    Directory to download the .git content if dumpcontent is enabled.

.EXAMPLE
    ./Find-RepositoryOnWebSites.ps1 -domain "example.com" -outputType "both" -logging -dumpcontent -downloadDir "downloads"
    This command checks the domain "example.com" for the existence of specific files and directories, logs the output to both the console and a file, and prints progress to the console. If .git directory is found and directory browsing is enabled, it downloads the content to the specified directory.

.EXAMPLE
    ./Find-RepositoryOnWebSites.ps1 -domainFile "domains.txt" -outputType "file" -logging -dumpcontent -downloadDir "downloads"
    This command checks the domains listed in the file "domains.txt" for the existence of specific files and directories, logs the output to a file, and prints progress to the console. If .git directory is found and directory browsing is enabled, it downloads the content to the specified directory.
#>

param (
    [string]$domain = "",
    [string]$domainFile = "",
    [ValidateSet("console", "file", "both")]
    [string]$outputType = "console",
    [switch]$logging,
    [switch]$dumpcontent,
    [string]$downloadDir = "downloads"
)

$downloadDir = "$($downloadDir)_$($domain.Replace('.', '_'))"

# List of directories and files to detect
$pathsToCheck = @(
    ".git",
    ".gitkeep",
    ".git-rewrite",
    ".gitreview",
    ".git/HEAD",
    ".gitconfig",
    ".git/index",
    ".git/logs",
    ".svnignore",
    ".gitattributes",
    ".gitmodules",
    ".svn/entries"
)

# Function to check the existence of specific files and directories
function CheckPaths {
    param (
        [string]$baseUrl
    )

    $results = @()
    $gitFound = $false
    foreach ($path in $pathsToCheck) {
        $url = "$($baseUrl)/$($path)"
        try {
            $response = Invoke-WebRequest -Uri $url -Method Head -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                $results += [PSCustomObject]@{ Protocol = $baseUrl.Split('://')[0]; Domain = $baseUrl; Path = $path; StatusCode = $response.StatusCode; Result = "Found" }
                if ($logging) {
                    Write-Host "[+] $($baseUrl): $($path) found (Status: $($response.StatusCode))" -ForegroundColor Green
                }
                if ($path -eq ".git") {
                    $gitFound = $true
                }
            } else {
                $results += [PSCustomObject]@{ Protocol = $baseUrl.Split('://')[0]; Domain = $baseUrl; Path = $path; StatusCode = $response.StatusCode; Result = "Not Found" }
                if ($logging) {
                    Write-Host "[-] $($baseUrl): $($path) not found (Status: $($response.StatusCode))" -ForegroundColor Red
                }
            }
        } catch {
            $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.Value__ } else { "notResponding" }
            $results += [PSCustomObject]@{ Protocol = $baseUrl.Split('://')[0]; Domain = $baseUrl; Path = $path; StatusCode = $statusCode; Result = "Not Found" }
            if ($logging) {
                Write-Host "[-] $($baseUrl): $($path) not found (Status: $($statusCode))" -ForegroundColor Red
            }
        }
    }
    if ($gitFound -and $dumpcontent) {
        if (-not (Test-Path -Path $downloadDir)) {
            New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
            Write-Host "[+] Created directory: $downloadDir" -ForegroundColor Green
        }
        DumpGitContent -baseUrl $baseUrl -downloadDir $downloadDir
    }
    return $results
}

# Function to log results
function LogResults {
    param (
        [PSCustomObject[]]$results,
        [string]$outputType
    )

    if ($outputType -eq "file" -or $outputType -eq "both") {
        $results | Export-Csv -Path "scan_results.csv" -Append -NoTypeInformation
    }

    if (-not $logging -and ($outputType -eq "console" -or $outputType -eq "both")) {
        $results | Format-Table -Property Protocol, Domain, Path, StatusCode, Result -AutoSize
    }
}

# Function to dump content of .git directory
function DumpGitContent {
    param (
        [string]$baseUrl,
        [string]$downloadDir
    )

    $gitUrl = "$baseUrl/.git/"
    $response = Invoke-WebRequest -Uri $gitUrl -ErrorAction Stop

    if ($response.Content -match "Index of") {
        Write-Host "Directory browsing is enabled. Downloading content from $($gitUrl) to $($downloadDir)" -ForegroundColor Cyan
        $downloadDirCount = (Get-ChildItem "./$($downloadDir)" -Recurse).count
        if ($downloadDirCount -eq 0){
            DownloadContent -baseUrl $gitUrl -downloadDir $downloadDir
        }else{
            Write-Host "The content has already been downloaded from the page $($gitUrl)." -ForegroundColor Yellow
        }
    } else {
        Write-Host "For extracting content from the GIT directory, use the GIT-Dumper tools available at the following URL" -ForegroundColor Yellow
    }
}

# Function to download content recursively using Start-BitsTransfer
function DownloadContent {
    param (
        [string]$baseUrl,
        [string]$downloadDir
    )

    $response = Invoke-WebRequest -Uri $baseUrl
    $links = $response.Links | Where-Object { ($_.Href -notmatch "^\.\.?$") -and ($_.Href -notmatch "C=") -and ($_.outerText -notmatch "Parent Directory")}

    foreach ($link in $links) {
        $url = "$($baseUrl)$($link.Href)"
        $targetPath = Join-Path $downloadDir $link.Href.Replace('/', '\')
        
        
        if ($link.TagName -eq 'a' -and $link.InnerText -match "/$") {
            if (-not (Test-Path $targetPath)) {
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            }
            DownloadContent -baseUrl $url -downloadDir $targetPath
        } else {
            try {
                    Start-BitsTransfer -Source $url -Destination $targetPath
                    Write-Host "[+] Downloaded: $url" -ForegroundColor Green
            } catch {
                Write-Host "[-] Failed to download: $url" -ForegroundColor Red
            }
        }
    }
}

# Main script
Write-Host "Starting script..." -ForegroundColor Cyan

$allResults = @()

if ($domain -ne "") {
    # Check a single domain
    $protocols = @("http", "https")
    foreach ($protocol in $protocols) {
        $baseUrl = "$($protocol)://$($domain)"
        Write-Host "Checking $($baseUrl)" -ForegroundColor Cyan
        $results = CheckPaths -baseUrl $baseUrl
        $allResults += $results
    }
} elseif ($domainFile -ne "") {
    # Load and check domains from file
    $domains = Get-Content -Path $domainFile
    foreach ($domain in $domains) {
        $protocols = @("http", "https")
        foreach ($protocol in $protocols) {
            $baseUrl = "$($protocol)://$($domain)"
            Write-Host "Checking $($baseUrl)" -ForegroundColor Cyan
            $results = CheckPaths -baseUrl $baseUrl
            $allResults += $results
        }
    }
} else {
    Write-Host "Please specify a domain or a domain file." -ForegroundColor Cyan
}

LogResults -results $allResults -outputType $outputType

Write-Host "Script completed." -ForegroundColor Cyan

