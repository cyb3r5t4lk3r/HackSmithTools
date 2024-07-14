# Přístup a stahování dat z blobů z Azure Storage Account

## Co skript dělá
Tento skript se připojuje k Azure Storage Account pomocí poskytnutých connection stringů nebo na základě definice veřejného přístupu, identifikuje dostupné kontejnery a stáhne zadaný počet blobů z každého kontejneru. V případě PublicMode stahuje všechny soubory přístupné v blobu, což je identifikováno pomocí odpovědního XML v otevřeném blobu.

### Možnosti použití
- **ReconMode**: Nastavení módu skenování blobů ve Storage Accountu
    - **AuthenticateMode**: Vyžaduje, aby existoval soubor s connections (SAS nebo Access Key), které se budou zkoušet při testování.
    - **PublicMode**: Testuje se vždy jeden název Azure Storage Accountu a musí být doplněn seznam s názvy blobů, které se budou testovat.
- **connectionStringsFile**: Cesta k souboru obsahujícímu connection stringy, každý na novém řádku.
- **blobsToDownloadCount**: Počet blobů, které se mají stáhnout z každého identifikovaného kontejneru.
- **StorageAccountName**: Název storage accountu, který se bude testovat v rámci PublicMode
- **DictionaryFile**: Název souboru, který obsahuje slovník názvů blobů, které se budou v kontejneru testovat


### Příklad použití
```powershell
.\Access-AzureStorageAccount.ps1 -ReconMode AuthenticateMode -connectionStringsFile "connectionStrings.txt" -blobsToDownloadCount 5

.\Access-AzureStorageAccount.ps1 -ReconMode PublicMode -StorageAccountName publicstorageaccount -DictionaryFile .\small.txt

```

## Ofenzivní použití
Skript lze použít k:
- Testování přístupnosti a bezpečnosti Azure Storage Accountů.
- Simulaci útoků za účelem identifikace slabých míst a zlepšení bezpečnostních opatření.
- Stažení dat z úložiště za účelem analýzy nebo jiných účelů.

## Důležité upozornění
- Tyto nástroje jsou vytvořeny pro ofenzivní bezpečnostní aktivity a nesmí být nikdy použity k nelegálním účelům.
- Uživatelé přebírají veškerá rizika a odpovědnost za používání těchto nástrojů.
- Autor se zříká veškeré odpovědnosti za jakékoliv zneužití nebo škody způsobené použitím těchto nástrojů.

## Ukázka výstupu
### Autentizovaný sken
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Azure-Storage-Authenticate.gif)

### Neautentizovaný sken do public storage
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Azure-Storage-Public.gif)

## Detekce v Microsoft Sentinel pomocí Kusto Query Language

#### Detekce anonymního přístupu do Storage Accountu a stažení obsahu
```kusto
let var_TimeWindow = 15m;
let tb_PotentialAttackerIp = 
    StorageBlobLogs
    | where TimeGenerated > ago(var_TimeWindow)
    | where AuthenticationType contains "anonymous"
    | where Uri contains "?restype=container&comp=list" //caller IP enumerate XML with files in storage
    | distinct CallerIpAddress
;
StorageBlobLogs
| where TimeGenerated > ago(var_TimeWindow)
| where CallerIpAddress in(tb_PotentialAttackerIp)
| where AuthenticationType contains "anonymous"
| project TimeGenerated, AccountName, OperationName, StatusCode, StatusText, ObjectKey, CallerIpAddress, Category
```
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Azure-Storage-KQL-Public-Access.png)

#### Detekce ověřeného přístupu a stažení dat v rámci TimeLine vyšetřování
```kusto
StorageBlobLogs
| where TimeGenerated > ago(4h)
| where OperationName !in("CreateContainer","PutBlob","RenewBlobLease","SetBlobMetadata")
| where OperationName !in("ListBlobs","GetBlobProperties")
| summarize count() by OperationName, bin(TimeGenerated,1m)
| render columnchart 
```

![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Azure-Storage-KQL-TimeLine.png)

#### Zobrazení tabulky výsledku stažených souborů skrze ověřený přístup
```kusto
let var_TimeWindow = 4h;
StorageBlobLogs
| where TimeGenerated > ago(var_TimeWindow)
| where OperationName == "GetBlob"
| extend FileName = tostring(array_reverse(split(ObjectKey,"/"))[0])
| extend SourceIP = tostring(split(CallerIpAddress,":")[0])
| where StatusText contains "success"
| project TimeGenerated, AccountName, AuthenticationType, SourceIP, FileName, Category, OperationName, UserAgentHeader
| summarize count() by AccountName, FileName, SourceIP
| extend LocationCountry = geo_info_from_ip_address(SourceIP)["country"]
```
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Azure-Storage-KQL-GridView.png)