# Azure App Service Testing Tools

Tento adresář obsahuje nástroje a zranitelné aplikace zaměřené na testování a hodnocení bezpečnosti **Azure App Services**. Nástroje zde obsažené jsou určeny pro profesionály v oblasti kybernetické bezpečnosti, penetrační testery a etické hackery, kteří se zaměřují na ofenzivní testování cloudových služeb. Obsah adresáře bude postupně doplňován o další nástroje, které usnadní testování Azure App Services na platformách **Linux** i **Windows**.

## Co zde najdete:

### 1. Damn Vulnerable ASP.NET Core App
Tato zranitelná aplikace napsaná v ASP.NET Core 8.0 demonstruje útoky typu **command injection**. Aplikace je určena pro nasazení na **Linux kontejner** v Azure App Service. Obsahuje jedno vstupní pole, které umožňuje injekci příkazů přes HTTP GET metodu.

- URL aplikace: `http://<server_or_app_service_url>/ExecuteCommand`
- Zranitelnost: Command injection (logováno na straně serveru).
- Nasazení: Pro více informací a nasazení postupujte podle pokynů v přiloženém [README](./DamnVulnerableApp/README.md).

### Další nástroje (bude doplněno později)

## Důležité upozornění:

Tyto nástroje jsou vytvořeny pro ofenzivní bezpečnostní aktivity a nesmí být nikdy použity k nelegálním účelům. Uživatelé přebírají veškerá rizika a odpovědnost za používání těchto nástrojů. Autor se zříká veškeré odpovědnosti za jakékoliv zneužití nebo škody způsobené použitím těchto nástrojů.