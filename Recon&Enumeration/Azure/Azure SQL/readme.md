# Brute Force Attack on Azure SQL Server

## Co skript dělá
Tento skript se pokouší připojit k Azure SQL Serveru pomocí kombinace uživatelských jmen a hesel z poskytnutých souborů. Podporuje různé režimy útoku a typy připojení.

### Možnosti použití
- **Server**: Název nebo IP adresa Azure SQL Database serveru, na který je útok veden.
- **Port**: Číslo portu, na který se má připojit (výchozí je 1433).
- **InitialCatalogueFile**: Soubor obsahující seznam výchozích databází, ke kterým se má připojit, každá na novém řádku.
- **InitialCatalogue**: Výchozí databáze, ke které se má připojit.
- **UsernamesFile**: Soubor obsahující seznam uživatelských jmen, každé na novém řádku.
- **PasswordsFile**: Soubor obsahující seznam hesel, každé na novém řádku.
- **AttackMode**: Režim útoku ("Pitchfork" nebo "ClusterBomb").
  - **Pitchfork**: Každé uživatelské jméno je spojeno s heslem na stejném řádku.
  - **ClusterBomb**: Každé uživatelské jméno je spojeno s každým heslem, což vede k mnoha pokusům pro jedno uživatelské jméno, než se přejde k dalšímu.
  - **PasswordSpray**: Jedno heslo je vyzkoušeno na všechna uživatelská jména, než se přejde k dalšímu heslu.
- **ConnectionMode**: Typ připojení dle povoleného způsobu autentizace pro SQL databázi ("EntraPasswordless", "SQL", "EntraPassword", nebo "EntraIntegrated").

## Příklad použití
```powershell
.\Access-AzureSQLDatabase.ps1 -Server "sqlserver.database.windows.net" -Port 1433 -InitialCatalogueFile "initialCatalogue.txt" -UsernamesFile "usernames.txt" -PasswordsFile "passwords.txt" -AttackMode "Pitchfork" -ConnectionMode "SQL"
```

Tento příkaz se pokusí připojit k zadanému SQL Serveru pomocí uživatelských jmen a hesel z poskytnutých souborů v režimu Pitchfork s autentizací SQL.

# Ofenzivní použití
Skript lze použít k:
- Testování odolnosti Azure SQL Serveru vůči brute force útokům.
- Simulaci útoků za účelem zlepšení bezpečnostních opatření.
- Identifikaci slabých míst v autentizačních mechanismech.

# Důležité upozornění
- Tyto nástroje jsou vytvořeny pro ofensivní bezpečnostní aktivity a nesmí být nikdy použity k nelegálním účelům.
- Uživatelé přebírají veškerá rizika a odpovědnost za používání těchto nástrojů.
- Autor se zříká veškeré odpovědnosti za jakékoliv zneužití nebo škody způsobené použitím těchto nástrojů.

# Ukázka výstupu
[Zde vložte ukázku výstupu skriptu nebo odkaz na video]
