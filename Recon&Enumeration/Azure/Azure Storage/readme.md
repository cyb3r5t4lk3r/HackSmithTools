# Přístup a stahování dat z blobů z Azure Storage Account

## Co skript dělá
Tento skript se připojuje k Azure Storage Account pomocí poskytnutých connection stringů, identifikuje dostupné kontejnery a stáhne zadaný počet blobů z každého kontejneru.

### Možnosti použití
- **connectionStringsFile**: Cesta k souboru obsahujícímu connection stringy, každý na novém řádku.
- **blobsToDownloadCount**: Počet blobů, které se mají stáhnout z každého identifikovaného kontejneru.

### Příklad použití
```powershell
.\Access-AzureStorageAccount.ps1 -connectionStringsFile "connectionStrings.txt" -blobsToDownloadCount 5
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
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Azure-Storage.gif)

## Detekce v Microsoft Sentinel pomocí Kusto Query Language

#### Detekce v rámci TimeLine vyšetřování
```kusto
//KQL detection Query 1 - Time Series Analysis
StorageBlobLogs
| where TimeGenerated > ago(4h)
| where OperationName !in("CreateContainer","PutBlob","RenewBlobLease","SetBlobMetadata")
| where OperationName !in("ListBlobs","GetBlobProperties")
| summarize count() by OperationName, bin(TimeGenerated,1m)
| render columnchart 
```

![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Azure-Storage-KQL-TimeLine.gif)

#### Zobrazení tabulky výsledku stažených souborů
```kusto
//KQL detection Query 2 - Grid view for downloaded files
StorageBlobLogs
| where TimeGenerated > ago(4h)
| where OperationName == "GetBlob"
| extend FileName = tostring(array_reverse(split(ObjectKey,"/"))[0])
| extend SourceIP = tostring(split(CallerIpAddress,":")[0])
| project TimeGenerated, AccountName, AuthenticationType, SourceIP, FileName, Category, OperationName, UserAgentHeader
| summarize count() by FileName, SourceIP
| extend LocationCountry = geo_info_from_ip_address(SourceIP)["country"]
```
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Azure-Storage-KQL-GridView.gif)