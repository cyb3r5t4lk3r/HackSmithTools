# FileSystem Analyzer
Tento PowerShell skript je navržen pro detailní analýzu souborového systému s důrazem na vysoký výkon a práci s velkými objemy dat. Skript rekurzivně prochází adresářovou strukturu, shromažďuje metadata o souborech a ukládá je do JSON formátu pro další zpracování.

## Popis
FileSystem Analyzer je primárně určen ke sběru dat z různých umístění s cílem vypsat všechny dostupné soubory, které je možné dále analyzovat pomocí metadat nebo názvů souborů. V rámci Red team operací umožňuje efektivně identifikovat citlivé soubory během offline analýz.
Skript dokáže zpracovávat až 4000 souborů za sekundu a exportuje data do JSON souboru. Jednoduchými úpravami lze dosáhnout extrakce do SQL databáze, případně data importovat do Azure Data Explorer clusteru a analyzovat pomocí Kusto Query Language (KQL).

## Shromažďovaná metadata o souborech zahrnují:
Název souboru a jeho základní název
Velikost souboru
Umístění (adresářová cesta)
Atributy souboru (pouze ke čtení, atd.)
Úplná cesta k souboru
Přípona souboru
Časové údaje (vytvoření, poslední přístup, poslední úprava)
Další atributy souborového systému

## Použití
### Prerekvizity
- Windows s PowerShell 5.1 nebo novější
- PowerShell modul WriteAscii (skript jej automaticky nainstaluje, pokud chybí)

### Instalace
- Stáhněte soubor Get-FileSystemAnalysis_v2.ps1
- Spusťte PowerShell s oprávněními pro instalaci modulů (pokud nemáte nainstalován modul WriteAscii)

### Spuštění skriptu
Skript lze spustit s následujícími parametry:

```powershell
.\Get-FileSystemAnalysis_v2.ps1 -FolderPath "C:\Cesta\K\Adresáři" -JsonFilePath "C:\Výstup\soubor.json" -ErrorLogFilePath "C:\Výstup\nedostupne_soubory.txt" -BlockSize 100 -MemDebug -PerfMon
```
#### Parametry:
- FolderPath (výchozí: "C:\Your\Folder\Path"): Cesta k adresáři, který má být analyzován
- JsonFilePath (výchozí: "C:\Your\Output\File.json"): Cesta pro uložení výstupního JSON souboru
- ErrorLogFilePath (výchozí: "C:\Your\Output\InaccessibleFiles.txt"): Cesta pro uložení logu nedostupných souborů
- BlockSize (výchozí: 100): Počet souborů ke zpracování v jednom bloku před zápisem do JSON souboru a uvolněním paměti
- VerboseLog (přepínač): Povolí podrobné logování procesu
- DebugLog (přepínač): Povolí ladící výpisy pro řešení problémů
- MemDebug (přepínač): Povolí detailní monitorování paměti a proměnných
- PerfMon (přepínač): Povolí sledování výkonu během zpracování

## Výstup
Skript vytvoří následující výstupy:
- JSON soubor obsahující metadata o všech zpracovaných souborech
- Textový soubor s seznamem nedostupných souborů a chybových hlášení

### Příklad struktury JSON výstupu:
```json
[
  {
    "Name": "dokument.docx",
    "BaseName": "dokument",
    "Length": 24500,
    "DirectoryName": "C:\\Users\\jmeno\\Dokumenty",
    "IsReadOnly": false,
    "Exist": true,
    "FullName": "C:\\Users\\jmeno\\Dokumenty\\dokument.docx",
    "Extension": ".docx",
    "CreationTimeUtc": "2023-01-15T10:30:45Z",
    "LastAccessTimeUtc": "2023-02-20T14:25:10Z",
    "LastWriteTimeUtc": "2023-02-20T14:25:10Z",
    "Attributes": "Archive"
  },
  ...
]
```

## Možná rozšíření
Integrace s databázovými systémy pro přímý export
Analýza oprávnění k souborům a adresářům
Výpočet hash hodnot souborů pro deduplikaci
Detekce potenciálně citlivých souborů na základě přípony nebo obsahu

## Pokročilé funkce
### Správa paměti
- Skript implementuje efektivní správu paměti pomocí blokového zpracování a čištění kolekcí
- Automatické uvolňování paměti po zpracování každého bloku souborů
- Optimalizace pro zpracování velkých adresářových stromů

### Výkonnostní monitoring
- Sledování využití procesoru, paměti a diskové aktivity během běhu
- Průběžné zobrazování statistik o rychlosti zpracování
- Podrobné ladící informace při použití přepínače -MemDebug

### Robustní zpracování chyb
- Odolnost vůči problémům s oprávněními nebo nedostupnými soubory
- Protokolování všech problémů pro pozdější analýzu
- Ošetření Unicode problémů při zápisu do výstupních souborů

### Použití výsledků analýzy
Výstupní JSON soubor lze dále zpracovat mnoha způsoby:
- Importovat do analytických nástrojů (Power BI, Tableau)
- Provést dotazy pomocí jq nebo PowerShell pro rychlé vyhledávání konkrétních souborů
- Nahrát do databáze pro komplexnější analýzu
- Importovat do Azure Data Explorer a analyzovat pomocí KQL

## Omezení a upozornění
Tento nástroj je určen pouze pro legitimní použití, například bezpečnostní audit, forenzní analýzu nebo správu souborových systémů
Pro zpracování velmi velkých souborových systémů (miliony souborů) může být potřeba zvýšit velikost parametru BlockSize
Skript vyžaduje odpovídající oprávnění pro čtení analyzovaných adresářů a souborů

## Důležité upozornění
Tento nástroj je vytvořen pro legitimní účely a nesmí být použit k nelegálním aktivitám
Uživatelé přebírají veškerá rizika a odpovědnost za používání tohoto nástroje
Při analýze firemních systémů vždy získejte příslušná povolení před spuštěním

