<#
    File: Invoke-EnumerateAzureSubDomains.ps1
    Author: Karl Fosaaen (@kfosaaen), NetSPI - 2018
    Description: PowerShell for enumerating Azure/Microsoft hosted resources.
    Parts of the Permutations.txt file borrowed from - https://github.com/brianwarehime/inSp3ctor
#>

<#
        .SYNOPSIS
        PowerShell for enumerating public Azure services.
        .DESCRIPTION
        The function will check for valid Azure subdomains, based off of a base word, via DNS. 
        .PARAMETER Base
        The Base name to prepend/append with permutations.
        .PARAMETER Permutations
        Specific permutations file to use. Default is Invoke-EnumerateAzureSubDomains-permutations.txt (included in this repo)
        .EXAMPLE
        PS C:\> Invoke-EnumerateAzureSubDomains.ps1 -Base test123 -Verbose
		Invoke-EnumerateAzureSubDomains -Base test12345678 -Verbose 
		VERBOSE: Found test12345678.cloudapp.net
		VERBOSE: Found test12345678.scm.azurewebsites.net
		VERBOSE: Found test12345678.onmicrosoft.com
		VERBOSE: Found test12345678.database.windows.net
		VERBOSE: Found test12345678.mail.protection.outlook.com
		VERBOSE: Found test12345678.queue.core.windows.net
		VERBOSE: Found test12345678.blob.core.windows.net
		VERBOSE: Found test12345678.file.core.windows.net
		VERBOSE: Found test12345678.vault.azure.net
		VERBOSE: Found test12345678.table.core.windows.net
		VERBOSE: Found test12345678.azurewebsites.net
		VERBOSE: Found test12345678.documents.azure.com
		VERBOSE: Found test12345678.azure-api.net
		VERBOSE: Found test12345678.sharepoint.com

		Subdomain                                Service                
		---------                                -------                
		test12345678.azure-api.net               API Services           
		test12345678.cloudapp.net                App Services           
		test12345678.scm.azurewebsites.net       App Services           
		test12345678.azurewebsites.net           App Services           
		test12345678.documents.azure.com         Databases-Cosmos DB    
		test12345678.database.windows.net        Databases-MSSQL        
		test12345678.mail.protection.outlook.com Email                  
		test12345678.vault.azure.net             Key Vaults             
		test12345678.onmicrosoft.com             Microsoft Hosted Domain
		test12345678.sharepoint.com              SharePoint             
		test12345678.queue.core.windows.net      Storage Accounts       
		test12345678.blob.core.windows.net       Storage Accounts       
		test12345678.file.core.windows.net       Storage Accounts       
		test12345678.table.core.windows.net      Storage Accounts    
        .LINK
        https://blog.netspi.com/enumerating-azure-services/
#>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,
        ValueFromPipeline = $true,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage="Base name to use.")]
        [string]$Base = "",
        [Parameter(Mandatory=$false,
        HelpMessage="Specific permutations file to use.")]
        [string]$Permutations = "$PSScriptRoot\Invoke-EnumerateAzureSubDomains-permutations.txt",
        [ValidateSet("All", "MicrosoftHostedDomain", "AppServices", "StorageAccount", "Office365", "Databases", "KeyVaults", "CDN", "SearchService", "API", "AzureContainerRegistry")]
        [string]$ReconMode = "All"
    )

    # Domain = Service hashtable for easier lookups
    $subLookupDomain =  @{'onmicrosoft.com'='Microsoft Hosted Domain';
					'scm.azurewebsites.net'='App Services - Management';
					'azurewebsites.net'='App Services';
					'p.azurewebsites.net'='App Services';
					'cloudapp.net'='App Services';
					'file.core.windows.net'='Storage Accounts - Files';
					'blob.core.windows.net'='Storage Accounts - Blobs';
					'queue.core.windows.net'='Storage Accounts - Queues';
					'table.core.windows.net'='Storage Accounts - Tables';
					'mail.protection.outlook.com'='Email';
					'sharepoint.com'='SharePoint';
					'redis.cache.windows.net'='Databases-Redis';
					'documents.azure.com'='Databases-Cosmos DB';
					'database.windows.net'='Databases-MSSQL';
					'vault.azure.net'='Key Vaults';
					'azureedge.net'='CDN';
					'search.windows.net'='Search Appliance';
					'azure-api.net'='API Services';
					'azurecr.io'='Azure Container Registry'
					}
    
    switch ($ReconMode) {
        All {
            $subLookup = $subLookupDomain
        }
        MicrosoftHostedDomain {
            $subLookup = $subLookupDomain | Where-Object { $_.Value -eq 'Microsoft Hosted Domain' }
        }
        AppServices {
            $subLookup = $subLookupDomain | Where-Object { $_.Value -eq 'App Services' -or $_.Value -eq 'App Services - Management' }
        }
        StorageAccount {
            $subLookup = $subLookupDomain | Where-Object { $_.Value -like 'Storage Accounts*' }
        }
        Office365 {
            $subLookup = $subLookupDomain | Where-Object { $_.Value -eq 'Email' -or $_.Value -eq 'SharePoint' }
        }
        Databases {
            $subLookup = $subLookupDomain | Where-Object { $_.Value -like 'Databases*' }
        }
        KeyVaults {
            $subLookup = $subLookupDomain | Where-Object { $_.Value -eq 'Key Vaults' }
        }
        CDN {
            $subLookup = $subLookupDomain | Where-Object { $_.Value -eq 'CDN' }
        }
        SearchService {
            $subLookup = $subLookupDomain | Where-Object { $_.Value -eq 'Search Appliance' }
        }   
        API {
            $subLookup = $subLookupDomain | Where-Object { $_.Value -eq 'API Services' }
        }
        AzureContainerRegistry {
            $subLookup = $subLookupDomain | Where-Object { $_.Value -eq 'Azure Container Registry' }
        }
        Default {
            $subLookup = $subLookupDomain
        }
    }

    $runningList = @()
    $lookupResult = ""

    if ($Permutations -and (Test-Path $Permutations)){
        $PermutationContent = Get-Content $Permutations
        }
    else{Write-Verbose "No permutations file found"}

    # Create data table to house results
    $TempTbl = New-Object System.Data.DataTable 
    $TempTbl.Columns.Add("Subdomain") | Out-Null
    $TempTbl.Columns.Add("Service") | Out-Null

    $iter = 0
    
    # Check Each Subdomain
    $subLookup.Keys | ForEach-Object{

        # Track the progress
        $iter++
        $subprogress = ($iter/$subLookup.Count)*100

        Write-Progress -Status 'Progress..' -Activity "Enumerating $Base subdomains for $_ subdomain" -PercentComplete $subprogress

        # Check the base word
        $lookup = $Base+'.'+$_
        
        try{($lookupResult = Resolve-DnsName $lookup -ErrorAction Stop -Verbose:$false -DnsOnly | select Name | Select-Object -First 1)|Out-Null}catch{}
        if ($lookupResult -ne ""){
            Write-Verbose "Found $lookup"; $runningList += $lookup
            # Add to output table
            $TempTbl.Rows.Add([string]$lookup,[string]$subLookup[$_]) | Out-Null

            }
        $lookupResult = ""


        # Chek Permutations (postpend word, prepend word)
        foreach($word in $PermutationContent){

            # Storage Accounts can't have special characters
            if(($_ -ne 'file.core.windows.net') -or ($_ -ne 'blob.core.windows.net')){
                # Base-Permutation
                $lookup = $Base+"-"+$word+'.'+$_
                try{($lookupResult = Resolve-DnsName $lookup -ErrorAction Stop -Verbose:$false -DnsOnly | select Name | Select-Object -First 1)|Out-Null}catch{}
                if ($lookupResult -ne ""){Write-Verbose "Found $lookup"; $runningList += $lookup; $TempTbl.Rows.Add([string]$lookup,[string]$subLookup[$_]) | Out-Null}
                $lookupResult = ""

                # Permutation-Base
                $lookup = $word+"-"+$Base+'.'+$_
                try{($lookupResult = Resolve-DnsName $lookup -ErrorAction Stop -Verbose:$false -DnsOnly | select Name | Select-Object -First 1)|Out-Null}catch{}
                if ($lookupResult -ne ""){Write-Verbose "Found $lookup"; $runningList += $lookup; $TempTbl.Rows.Add([string]$lookup,[string]$subLookup[$_]) | Out-Null}
                $lookupResult = ""
            }

            # PermutationBase
            $lookup = $word+$Base+'.'+$_
            try{($lookupResult = Resolve-DnsName $lookup -ErrorAction Stop -Verbose:$false -DnsOnly | select Name | Select-Object -First 1)|Out-Null}catch{}
            if ($lookupResult -ne ""){Write-Verbose "Found $lookup"; $runningList += $lookup; $TempTbl.Rows.Add([string]$lookup,[string]$subLookup[$_]) | Out-Null}
            $lookupResult = ""

            # BasePermutation
            $lookup = $Base+$word+'.'+$_
            try{($lookupResult = Resolve-DnsName $lookup -ErrorAction Stop -Verbose:$false -DnsOnly | select Name | Select-Object -First 1)|Out-Null}catch{}
            if ($lookupResult -ne ""){Write-Verbose "Found $lookup"; $runningList += $lookup; $TempTbl.Rows.Add([string]$lookup,[string]$subLookup[$_]) | Out-Null}
            $lookupResult = ""
        }
    }
    $TempTbl | sort Service
