# Azure Service Enumeration Tool

## Co skript dělá
Powershell script pro enumeraci (ověření existence) služeb v rámci prostředí Microsoft Azure

### Možnosti použití
- **Base**: Základ pro jméno služby, která bude permutována pro potřeby enumerace služeb.
- **Permutations**: Seznam permutačních jmen oddělených na jednotlivé řádky, které se budou přidávat k base jménu a bude se kontrolovat jejich existence.
- **ReconMode**: Můžete nastavit na jakou službu konkrétně cílíte a na výběr máte z těchto: "All", "MicrosoftHostedDomain", "AppService", "StorageAccount", "Office365", "Databases", "KeyVaults", "CDN", "SearchService", "API", "AzureContainerRegistry"
- **Verbose**: Zapnutí detailního výpisu do konzole.

## Příklad použití
```powershell
Invoke-EnumerateAzureSubDomains.ps1 -Base firma -Permutations .\Invoke-EnumerateAzureSubDomains-permutations.txt -ReconMode All -Verbose
```

Tento příkaz se pokusí připojit k zadanému SQL Serveru pomocí uživatelských jmen a hesel z poskytnutých souborů v režimu Pitchfork s autentizací SQL.

# Ofenzivní použití
Skript lze použít k:

- Enumeraci služeb běžících v prostředí Microsoft Azure.
- Simulaci útoků za účelem zlepšení bezpečnostních opatření.
- Kontrole detekčních mechanismů, které odhalí přípravu možného útoku.

# Důležité upozornění
- Během provádění testování se vaše veřejná IP adresa může dostat na blacklist společnosti Microsoft
- Během testování může dojít ke ztrátě internetového připojení v důsledku odesílání vysokého množství požadavků
- Tyto nástroje jsou vytvořeny pro ofensivní bezpečnostní aktivity a nesmí být nikdy použity k nelegálním účelům.
- Uživatelé přebírají veškerá rizika a odpovědnost za používání těchto nástrojů.
- Autor se zříká veškeré odpovědnosti za jakékoliv zneužití nebo škody způsobené použitím těchto nástrojů.

# Ukázka výstupu
![Alt text]([Media/Azure-Recon.gif](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Azure-Recon.gif))

# Vzorek základní detekce pomocí Kusto Query Language
```kusto
AzureDiagnostics
```

## Speciální poděkování
Rádi bychom vyjádřili speciální poděkování autorům projektu [MicroBurst](https://github.com/NetSPI/MicroBurst) za některé scripty a inspiraci. Jejich práce byla neocenitelná při vývoji a zdokonalování těchto nástrojů pro testování služeb Azure.
