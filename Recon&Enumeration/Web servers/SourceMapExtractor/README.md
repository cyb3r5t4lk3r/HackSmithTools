# Sourcemap Site Crawler

Tento nástroj slouží k identifikaci JavaScript souborů na webu a následné kontrole, zda k nim existují dostupné sourcemap soubory. Sourcemapy mohou v některých případech obsahovat původní zdrojový kód frontendové aplikace, například React, Vue, Angular nebo jiné JavaScriptové aplikace sestavené přes bundler.

Cílem skriptu je pomoci při bezpečnostním testování, kontrole produkčního nasazení a ověření, zda nejsou na veřejném webu omylem dostupné vývojové artefakty.

> Skript používejte pouze proti systémům, ke kterým máte oprávnění k testování.

---

## Co skript dělá

Skript provádí rekurzivní průchod webem v rámci zadaného rozsahu a hledá JavaScript soubory. U každého nalezeného JavaScript souboru se pokusí najít odpovídající sourcemap soubor. Současně si u každého JS souboru ukládá i jeho **origin**, takže v reportu vidíte, zda skript pochází přímo z testovaného webu, z CDN, z tag manageru, z tracking domény nebo z jiného statického asset hostu.

Detekce probíhá ve dvou krocích, takže crawler nemusí lézt po celém CDN nebo po cizích webech:

1. Crawler prochází hlavní web a sbírá všechny `<script src="...">`.
2. U každého JS souboru si uloží i jeho origin (například `cdnjs.cloudflare.com`, `gtm.example.com` apod.).
3. Následně zkontroluje sourcemapy i pro externí JS soubory, ale nepokračuje v rekurzivním crawlu na cizích doménách.

Typicky kontroluje například tyto varianty:

```text
https://reactjs.org/static/js/main.abc123.js
https://reactjs.org/static/js/main.abc123.js.map
```

Kromě přímého doplnění koncovky `.map` skript kontroluje také odkazy uvedené přímo v JavaScript souboru, například:

```javascript
//# sourceMappingURL=main.abc123.js.map
```

Skript umí také zpracovat sourcemap soubory, které obsahují pole `sourcesContent`. Pokud je toto pole přítomné, sourcemap může obsahovat přímo původní zdrojové soubory aplikace.

---

## Jak to funguje

Zjednodušený postup je následující:

1. Skript stáhne vstupní stránku, například `https://reactjs.org`.
2. Z HTML získá odkazy na JavaScript soubory ze značek `<script src="...">`.
3. Z HTML získá interní odkazy na další stránky webu.
4. Odkazy normalizuje, takže zvládne absolutní i relativní URL.
5. Rekurzivně pokračuje na další stránky v rámci stejného webu.
6. Všechny nalezené JavaScript soubory deduplikuje a ke každému si uloží jeho origin.
7. Pro každý JavaScript soubor zkusí najít odpovídající sourcemap, a to i u externích JS souborů z povolených originů (CDN, tag manager apod.).
8. Pokud sourcemap existuje, analyzuje její základní strukturu.
9. Volitelně extrahuje obsah `sourcesContent` do lokální složky.
10. Výsledek zapíše do konzole nebo do JSON reportu, včetně přehledu objevených externích originů.

Ve výchozím nastavení skript prochází (crawluje) pouze stejný origin, tedy například při spuštění proti `https://reactjs.org` nebude automaticky chodit po cizích doménách. Externí JS soubory, které stránka reálně načítá, lze zkontrolovat odděleně přes `--include-related-script-origins` nebo přes whitelist `--allowed-origin`, aniž by crawler musel lézt po celém CDN.

---

## Co je sourcemap

Sourcemap je pomocný soubor, který mapuje minifikovaný nebo bundlovaný JavaScript zpět na původní zdrojové soubory. Používá se hlavně pro debugování frontendových aplikací.

Produkční JavaScript může vypadat například takto:

```javascript
(()=>{var e={};function t(){return"hello"}})();
```

Sourcemap může ukázat, že tento kód původně pocházel například ze souborů:

```text
src/App.jsx
src/components/LoginForm.jsx
src/api/client.js
```

Pokud sourcemap obsahuje `sourcesContent`, může v sobě nést i celý původní obsah těchto souborů.

---

## Proč je to bezpečnostně důležité

Dostupné sourcemapy v produkci nejsou automaticky zranitelnost, ale často zvyšují informační hodnotu pro útočníka nebo pentestera.

Mohou odhalit například:

- původní strukturu frontendové aplikace,
- interní názvy komponent a funkcí,
- API endpointy,
- validační logiku,
- komentáře vývojářů,
- debug kód,
- feature flagy,
- chybně vložené tokeny nebo jiné citlivé hodnoty.

Z pohledu bezpečnostního reportu se typicky jedná o nález typu **Information Disclosure**. Závažnost závisí na tom, co sourcemapy reálně obsahují.

---

## Požadavky

Skript je napsaný v Pythonu 3.

Doporučená verze:

```bash
python3 --version
```

Ideálně používejte Python 3.10 nebo novější.

Skript používá běžné knihovny pro HTTP komunikaci a parsování HTML. Před spuštěním je vhodné nainstalovat závislosti do samostatného virtuálního prostředí.

---

## Instalace přes venv

Vytvoření pracovního adresáře:

```bash
mkdir sourcemap-audit
cd sourcemap-audit
```

Zkopírujte do této složky skript:

```text
sourcemap_site_crawler.py
```

Vytvořte virtuální prostředí:

```bash
python3 -m venv .venv
```

Aktivujte virtuální prostředí na Linuxu nebo macOS:

```bash
source .venv/bin/activate
```

Aktivace na Windows PowerShellu:

```powershell
.\.venv\Scripts\Activate.ps1
```

Aktivace na Windows CMD:

```cmd
.venv\Scripts\activate.bat
```

Nainstalujte závislosti:

```bash
pip install --upgrade pip
pip install requests beautifulsoup4
```

Pokud chcete mít závislosti uložené v souboru, můžete vytvořit `requirements.txt`:

```text
requests
beautifulsoup4
```

A následně instalovat takto:

```bash
pip install -r requirements.txt
```

---

## Základní spuštění

Příklad základního spuštění proti ukázkové doméně:

```bash
python3 sourcemap_site_crawler.py https://reactjs.org
```

Skript projde vstupní stránku, najde JavaScript soubory a pokusí se dohledat jejich sourcemapy.

---

## Spuštění s limitem počtu stránek

Pro větší weby je vhodné nastavit limit počtu procházených stránek:

```bash
python3 sourcemap_site_crawler.py https://reactjs.org --max-pages 300
```

Tím se omezí maximální počet HTML stránek, které crawler navštíví.

---

## Spuštění s limitem hloubky

Hloubka určuje, jak daleko od vstupní URL crawler půjde.

```bash
python3 sourcemap_site_crawler.py https://reactjs.org --max-depth 5
```

Příklad:

- hloubka `0` znamená pouze vstupní URL,
- hloubka `1` znamená vstupní URL a odkazy přímo z ní,
- hloubka `2` znamená ještě další úroveň odkazů.

---

## Uložení výstupu do JSON reportu

Pro další zpracování je vhodné uložit výsledek do JSON souboru:

```bash
python3 sourcemap_site_crawler.py https://reactjs.org --max-pages 300 --max-depth 5 --json report.json
```

JSON report může obsahovat například:

- seznam navštívených stránek,
- seznam nalezených JavaScript souborů,
- seznam nalezených sourcemap souborů,
- informaci, zda sourcemap obsahuje `sourcesContent`,
- počet zdrojových souborů uvedených v sourcemapě,
- sekci `related_script_origins_discovered`, která ukazuje, z jakých domén stránka tahá JavaScript a kolik JS souborů z každého originu bylo nalezeno,
- chyby při stahování nebo parsování.

---

## Extrakce zdrojových souborů ze sourcesContent

Pokud sourcemap obsahuje `sourcesContent`, lze zdrojové soubory extrahovat do lokální složky:

```bash
python3 sourcemap_site_crawler.py https://reactjs.org --max-pages 300 --max-depth 5 --extract ./sources --json report.json
```

Výsledkem bude složka například:

```text
sources/
├── static-js-main-abc123-js-map/
│   ├── src_App_jsx
│   ├── src_components_Header_jsx
│   └── src_api_client_js
└── static-js-vendor-def456-js-map/
    └── ...
```

Přesná struktura se může lišit podle toho, jak jsou cesty uvedené v sourcemap souboru.

---

## Kontrola externích JS souborů (CDN, tag manager, tracking)

Moderní weby často načítají JavaScript z externích originů, například z CDN (`cdnjs.cloudflare.com`, `unpkg.com`), tag manageru (`googletagmanager.com`) nebo z dedikovaných asset hostů. Aby crawler pro tyto soubory zkontroloval i sourcemapy, ale **nelezl rekurzivně po cizích webech**, použijte jeden z následujících přepínačů.

### Automatické rozšíření na všechny související originy

```bash
python3 sourcemap_site_crawler.py https://reactjs.org \
  --max-pages 300 \
  --max-depth 8 \
  --include-related-script-origins \
  --extract ./sources \
  --json report.json
```

Skript zkontroluje všechny externí JS soubory, které hlavní web reálně načítá, ale pokračuje v procházení (crawlu) pouze v rámci hlavního originu.

### Bezpečnější varianta s whitelistem originů

Pokud chcete povolit pouze konkrétní externí hosty, použijte opakovaně `--allowed-origin`. Parametr podporuje i wildcard ve tvaru `*.example.com`:

```bash
python3 sourcemap_site_crawler.py https://reactjs.org \
  --max-pages 300 \
  --max-depth 8 \
  --allowed-origin cdnjs.cloudflare.com \
  --allowed-origin "*.examplecdn.com" \
  --extract ./sources \
  --json report.json
```

### Rozdíl oproti `--all-origins`

Je důležité tyto dva přepínače nezaměňovat:

- `--include-related-script-origins` zkontroluje **pouze JavaScript** z externích originů, které hlavní web sám referencuje. Crawler stále prochází jen hlavní web.
- `--all-origins` jde dál a začne procházet i cizí HTML stránky. Tento režim používejte jen výjimečně a pouze v rámci své povolené testovací působnosti.

---

## Doporučené spuštění pro běžný audit

Pro běžnou kontrolu webu doporučuji tento režim:

```bash
python3 sourcemap_site_crawler.py https://reactjs.org --max-pages 300 --max-depth 6 --json report.json
```

Pokud report ukáže dostupné sourcemapy s `sourcesContent`, následně spusťte extrakci:

```bash
python3 sourcemap_site_crawler.py https://reactjs.org --max-pages 300 --max-depth 6 --extract ./sources --json report.json
```

---

## Parametry skriptu

| Parametr | Popis |
|---|---|
| `url` | Vstupní URL adresa webu. |
| `--max-pages` | Maximální počet HTML stránek, které crawler navštíví. |
| `--max-depth` | Maximální hloubka rekurzivního procházení. |
| `--json` | Cesta k souboru, do kterého se uloží JSON report. |
| `--extract` | Složka, do které se extrahuje obsah `sourcesContent`. |
| `--include-related-script-origins` | Zkontroluje sourcemapy i u externích JS souborů, které hlavní web načítá (CDN, tag manager, tracking). Crawler nelézá po cizích webech. |
| `--allowed-origin` | Whitelist konkrétních externích hostů, ze kterých se mají kontrolovat sourcemapy. Lze použít opakovaně, podporuje wildcard `*.example.com`. |
| `--all-origins` | Volitelně povolí procházení (crawl) i cizích HTML stránek. Používat opatrně, jen v rámci povolené působnosti. |

---

## Doporučená interpretace výsledků

### Sourcemap nenalezena

Pokud sourcemap není nalezena, neznamená to automaticky, že neexistuje. Může být:

- uložená pod jiným názvem,
- chráněná autentizací,
- dostupná jen z jiného prostředí,
- generovaná pouze pro staging,
- blokovaná na úrovni serveru nebo CDN.

### Sourcemap nalezena bez sourcesContent

To znamená, že sourcemap obsahuje mapování na původní soubory, ale nemusí obsahovat přímo jejich obsah. I tak může být užitečná, protože odhaluje strukturu aplikace a názvy zdrojových souborů.

### Sourcemap nalezena se sourcesContent

To je z bezpečnostního pohledu nejzajímavější varianta. Znamená to, že sourcemap pravděpodobně obsahuje původní zdrojové soubory. V takovém případě je vhodné provést detailní kontrolu, zda neobsahují citlivé informace.

---

## Co dále kontrolovat ve zdrojových souborech

Při bezpečnostní kontrole extrahovaných zdrojových souborů se zaměřte zejména na:

- API endpointy,
- hardcoded tokeny,
- API klíče,
- interní URL,
- debug nebo testovací logiku,
- zakomentované části kódu,
- názvy interních systémů,
- business logiku,
- validační pravidla,
- autorizační rozhodování prováděné pouze na frontendu.

---

## Doporučení pro nápravu

Pokud jsou sourcemapy dostupné v produkci a nejsou záměrně publikované, doporučuje se:

1. Vypnout generování produkčních sourcemapů.
2. Odstranit již publikované `.map` soubory z produkčního prostředí.
3. Zkontrolovat, zda CDN nebo cache stále neservíruje staré `.map` soubory.
4. Zkontrolovat, zda JavaScript soubory neobsahují odkaz `sourceMappingURL`.
5. Ověřit, zda build pipeline nerozmisťuje sourcemapy automaticky.
6. Pokud jsou sourcemapy potřeba pro monitoring chyb, nahrávat je pouze do interní služby, například do error trackingu, ale nepublikovat je veřejně.

---

## Příklad reportovací formulace

Níže je možné použít základní formulaci do bezpečnostního reportu:

```text
Během testování bylo ověřeno, zda veřejně dostupná frontendová část aplikace neobsahuje odkazy na sourcemap soubory a zda tyto soubory nejsou dostupné bez autentizace. Sourcemap soubory mohou v závislosti na konfiguraci buildu obsahovat mapování minifikovaného JavaScriptu na původní zdrojové soubory a v některých případech také přímo jejich obsah prostřednictvím položky sourcesContent. Dostupnost těchto souborů může útočníkovi usnadnit porozumění interní logice aplikace, identifikaci API endpointů a vyhledávání citlivých informací ve frontendovém kódu.
```

---

## Omezení

Skript není plnohodnotný webový crawler ani DAST nástroj. Neprovádí autentizaci, nespouští JavaScript v prohlížeči a nemusí vidět odkazy nebo JavaScript soubory, které se načítají až po interakci uživatele.

Skript nemusí zachytit například:

- stránky dostupné až po přihlášení,
- odkazy generované dynamicky JavaScriptem,
- soubory načítané až po kliknutí nebo jiné interakci,
- části aplikace dostupné jen přes specifický stav aplikace,
- sourcemapy chráněné pravidly na CDN nebo reverzní proxy.

Pro komplexnější testování je vhodné kombinovat tento přístup s ruční kontrolou v prohlížeči, proxy nástrojem a případně crawlerem, který umí renderovat JavaScript.

---

## Bezpečnostní poznámka

Nástroj je určen pro legitimní bezpečnostní testování a kontrolu vlastních nebo smluvně povolených systémů. Výstupy mohou obsahovat citlivé informace, pokud testovaný web veřejně vystavuje zdrojové kódy nebo jejich části. S uloženými reporty a extrahovanými soubory proto zacházejte jako s citlivými daty.
