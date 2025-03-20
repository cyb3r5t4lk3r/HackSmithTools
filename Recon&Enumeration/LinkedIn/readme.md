# LinkedIn Company People Scraper

Tento PowerShell skript je navržen pro extrakci informací o osobách přidružených ke konkrétní společnosti na LinkedIn. Skript automatizuje proces vyhledávání a extrakce dat bez nutnosti používat LinkedIn API.

## Popis

LinkedIn People Scraper extrahuje následující informace o každé osobě:
- Jméno
- Pozice v společnosti
- Lokalita
- URL profilu
- Profilový obrázek

Všechny tyto informace jsou následně uloženy ve formátech JSON a CSV. Profilové obrázky jsou staženy do samostatného adresáře.

## Použití

### Prerekvizity
- Windows s PowerShell 5.1 nebo novější
- Microsoft Edge prohlížeč
- Přístup k internetu
- Účet na LinkedIn (Premium) a nastavenou češtinu

### Instalace
1. Stáhněte soubor `LinkedInPeopleScraper.ps1`
2. Ujistěte se, že máte nainstalovaný Microsoft Edge

Skript automaticky nainstaluje potřebné PowerShell moduly:
- Selenium (pro ovládání prohlížeče)
- ImportExcel (pro zpracování dat)

### Spuštění skriptu

Skript lze spustit s následujícími parametry:

```powershell
.\LinkedInPeopleScraper.ps1 -CompanyId "000000" -ManualLogin -Visible
```

#### Parametry:
- `-CompanyId` (povinný): ID společnosti na LinkedIn (např. "660532" pro "pro.med.cs")
- `-ManualLogin` (volitelný): Přepínač pro manuální přihlášení uživatelem (podporuje MFA)
- `-Visible` (volitelný): Přepínač pro zobrazení prohlížeče během scrapování

### Jak zjistit ID společnosti

1. Navštivte stránku společnosti na LinkedIn
2. URL bude mít formát: `https://www.linkedin.com/company/[ID nebo název]/`
3. ID společnosti je číslo v této URL adrese

## Výstup

Skript vytvoří následující strukturu:

```
LinkedInData_[CompanyID]/
├── linkedin_people_[CompanyID]_[Timestamp].json
├── linkedin_people_[CompanyID]_[Timestamp].csv
└── images/
    ├── [Jméno1].jpg
    ├── [Jméno2].jpg
    └── ...
```

## Průběh extrakce

1. Skript inicializuje prohlížeč Microsoft Edge
2. Čeká na manuální přihlášení uživatele do LinkedIn (pokud je použit parametr `-ManualLogin`). První přihlášení musí být vždy manuální
3. Automaticky přejde na stránku s výsledky vyhledávání lidí pracujících v zadané společnosti
4. Extrahuje informace o každé osobě včetně profilových obrázků
5. Ukládá všechna data do JSON a CSV souborů
6. Stahuje profilové obrázky do adresáře images

## Příklad výstupu

### JSON formát
```json
[
  {
    "Name": "Jan Novak",
    "Position": "Software Engineer",
    "Country": "Praha, Česká republika",
    "ProfileURL": "https://www.linkedin.com/in/jan-novak-123456789/",
    "Picture": "https://media.licdn.com/dms/image/..."
  },
  ...
]
```

### CSV formát
```
"Name","Position","Country","ProfileURL","Picture"
"Jan Novak","Software Engineer","Praha, Česká republika","https://www.linkedin.com/in/jan-novak-123456789/","https://media.licdn.com/dms/image/..."
...
```

## Omezení a upozornění

- Tento nástroj je určen pouze pro legitimní použití například v rámci OSINT
- Používání tohoto nástroje může být v rozporu s podmínkami používání služby LinkedIn
- Autor nenese žádnou odpovědnost za případné zneužití tohoto nástroje nebo za BAN účtu od LinkedIn
- LinkedIn může změnit svou strukturu stránky, což může způsobit, že skript přestane fungovat
- Nadměrné používání může vést k dočasnému zablokování vašeho LinkedIn účtu


## Důležité upozornění

- Tento nástroj je vytvořen pro legitimní účely a nesmí být nikdy použit k nelegálním aktivitám
- Uživatelé přebírají veškerá rizika a odpovědnost za používání tohoto nástroje
- Autor se zříká veškeré odpovědnosti za jakékoliv zneužití nebo škody způsobené použitím tohoto nástroje