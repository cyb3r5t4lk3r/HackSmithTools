# Damn Vulnerable ASP.NET Core App

Tato aplikace je jednoduchá zranitelná aplikace napsaná v ASP.NET Core 8.0, která je určena pro trénink a demonstraci útoků typu command injection. Aplikace obsahuje jedno vstupní pole, které umožňuje injekci příkazů a jejich vykonání na serveru. Command injection je prováděn pomocí metody GET, takže všechny příkazy jsou detekovatelné v logu serveru.

## URL aplikace
Aplikace je dostupná na adrese: 
`http://<server_or_app_service_url>/ExecuteCommand`

## Požadavky

- **ASP.NET Core 8.0 Runtime**: Pro spuštění aplikace je potřeba mít nainstalovaný runtime verze 8.0.
- **Visual Studio Code**: Doporučený nástroj pro práci s aplikací.
- **Azure App Service Extension**: Nutný doplněk ve Visual Studio Code pro nasazení aplikace do Azure.
- **Azure App Service**: Aplikace musí být nasazena na **Linux kontejner** s podporou ASP.NET Core 8.0.

## Zranitelnost

Aplikace obsahuje vstupní pole pro command injection, které je zneužitelné pomocí HTTP GET požadavků. Zadané příkazy jsou prováděny na serveru, přičemž všechny příkazy jsou zaznamenávány do serverových logů.

## Postup nasazení na Azure App Service

### 1. Příprava aplikace

Otevřete terminál ve složce s aplikací a zadejte následující příkazy:

```bash
cd <slozka_s_aplikaci>
dotnet clean   # Tento příkaz vyčistí předchozí buildy a připraví projekt na nové sestavení.
dotnet restore # Stáhne a obnoví všechny závislosti projektu.
dotnet build   # Sestaví aplikaci ze zdrojových kódů.
dotnet publish -c Release # Publikuje aplikaci pro produkční prostředí ve verzi Release.
```

### 2. Nasazení do Azure App Service pomocí Visual Studio Code

- Otevřete Visual Studio Code ve složce s aplikací a následujte tyto kroky:
```bash
code .   # Otevře aktuální složku s projektem ve Visual Studio Code.
```
- Stiskněte kombinaci kláves CTRL + SHIFT + P pro otevření příkazové palety.
- Najděte a vyberte možnost Azure App Service: Deploy to WebApp.
- Ověřte se do svého Azure účtu.
- Vyberte aplikaci a nasazení do Azure App Service.

### 3. Ověření nasazení
Po úspěšném nasazení by měla být aplikace dostupná na zadané URL adrese. Ujistěte se, že je App Service nakonfigurována pro ASP.NET Core 8.0 a běží na Linux kontejneru.

## Poznámky
Při nasazení aplikace na IIS je nutné zajistit, aby byl doinstalován runtime ASP.NET Core 8.0 na server.
Všechny příkazy provedené přes injekční vstup jsou viditelné v logu serveru, což umožňuje jejich detekci a zpětnou analýzu.

## Varování
Tato aplikace je určena pouze pro ofenzivní bezpečnostní testování a trénink. Nesmí být použita na produkčních serverech nebo pro nelegální účely. Uživatelé jsou zodpovědní za jakékoliv škody vzniklé nesprávným nebo neoprávněným použitím aplikace.
