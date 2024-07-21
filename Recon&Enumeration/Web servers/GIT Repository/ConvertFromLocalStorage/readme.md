# Extract-DataFromGitOfflineFolder

Tento skript je navržen pro extrahování souborů z **.git** adresáře a ukládání je do zadaného výstupního adresáře se stejnou strukturou složek. Volitelně může skript provádět analýzu souborů na přítomnost potenciálně nebezpečných řetězců.

## Popis

Skript instaluje Git pomocí winget, pokud není již nainstalován, a poté extrahuje soubory ze zadaného **.git** adresáře. Soubory jsou uloženy do výstupního adresáře se stejnou strukturou složek. Volitelně může skript provádět analýzu souborů ve výstupním adresáři a hledat potenciálně nebezpečné řetězce.

## Použití

### Prerekvizity

- PowerShell
- git
- winget

### Spuštění skriptu

1. Ujistěte se, že máte správně nainstalované prerekvizity.
2. Vytvořte soubor s řetězci pro vyhledávání, například **sensitive_strings.txt**, kde každý řetězec bude na novém řádku.
3. Spusťte skript s následujícím příkazem:

```powershell    
.\Extract-DataFromGitOfflineFolder.ps1 -GitDirectory ".\path\to\.git" -OutputDirectory "output_directory" -Logging -AnalyseFiles -SensitiveStringsFile ".\sensitive_strings.txt" -AnalyseOutput CSV
```

kde:
- **GitDirectory** je cesta k `.git` adresáři.
- **OutputDirectory** je název nebo cesta k výstupnímu adresáři.
- **Logging** je přepínač pro zapnutí logování.
- **AnalyseFiles** je přepínač pro zapnutí analýzy souborů.
- **SensitiveStringsFile** je cesta k souboru s řetězci pro vyhledávání.
- **AnalyseOutput** je formát výstupu analýzy, může být `CSV`, `Console`, nebo `GridView`.

## Ukázka spuštění a výstupu

### Extrakce souborů

```powershell
.\Extract-DataFromGitOfflineFolder.ps1 -GitDirectory ".\path\to\.git" -OutputDirectory "output_directory" -Logging
```

### Analýza souborů s výstupem do CSV

```powershell
.\Extract-DataFromGitOfflineFolder.ps1 -GitDirectory ".\path\to\.git" -OutputDirectory "output_directory" -AnalyseFiles -SensitiveStringsFile ".\sensitive_strings.txt" -AnalyseOutput Console
```


## Důležité upozornění
- Tyto nástroje jsou vytvořeny pro ofenzivní bezpečnostní aktivity a nesmí být nikdy použity k nelegálním účelům.
- Uživatelé přebírají veškerá rizika a odpovědnost za používání těchto nástrojů.
- Autor se zříká veškeré odpovědnosti za jakékoliv zneužití nebo škody způsobené použitím těchto nástrojů.
