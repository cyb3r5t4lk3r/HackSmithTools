# Detekce a vytěžení souborů z veřejně přístupného adresáře .git

Tento skript je navržen pro detekci existence specifických souborů a adresářů na webovém serveru, zejména pro vytěžení obsahu z veřejně přístupného adresáře `.git`. Skript umožňuje kontrolu jedné domény nebo načítání a kontrolu domén ze souboru (zde mohou být umístěny i pod adresáře jedné site). Podporuje výstup do konzole, souboru nebo obojího a může stahovat obsah adresáře `.git`, pokud je povolen directory browsing jinak je vyžadováno stažení pomocí dalších open source nástrojů, jako například GitTools nebo Git-Dumper.

## Popis

Skript kontroluje existenci specifických souborů a adresářů v rootu webu, zaměřuje se především na adresář `.git`. Můžete zadat jednu doménu nebo soubor obsahující seznam domén. Skript podporuje výstup do konzole, souboru nebo obojího. Pokud je povolen directory browsing, skript může stahovat obsah adresáře `.git` do určeného adresáře.

## Veřejná identifikace dostupných adresářů .git s Directory Browsing zranizelností

V rámci techniky Google Dorking je možné provádět veřejné vyhledávání přístupných adresářů .git, a to následujícím Google Search výrazem `Google Dorking intext:"index of /.git" "parent directory"`

## Použití

### Prerekvizity

- PowerShell
- Curl (volitelné, pokud se používají externí nástroje)

### Spuštění skriptu

1. Ujistěte se, že máte správně nainstalované prerekvizity.
2. Vytvořte textový soubor s doménami, například `domains.txt`, kde každá doména bude na novém řádku nebo uveďte jen jednu doménu.
3. Spusťte skript s následujícím příkazem:

```powershell
./Find-RepositoryOnWebSites.ps1 -domain "example.com" -outputType "both" -logging -dumpcontent -downloadDir "downloads"

./Find-RepositoryOnWebSites.ps1 -domainFile "domains.txt" -outputType "both" -logging -dumpcontent -downloadDir "downloads"
```

    kde:
    - `-domain "example.com"` je doména, kterou chcete kontrolovat.
    - `-domainFile "domains.txt"` je cesta k souboru s doménami (alternativní volba).
    - `-outputType "console"`, `-outputType "file"` nebo `-outputType "both"` určuje typ výstupu.
    - `-logging` zapne nebo vypne logování do konzole.
    - `-dumpcontent` povolí stahování obsahu `.git` adresáře.
    - `-downloadDir "downloads"` je cesta k adresáři, kam bude stahován obsah.

## Ukázka spuštění a výstupu
#### Identifikace v rámci jedné nebo více web aplikací
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Git-Identification.gif)

#### Stažení z přístupného úložiště
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Git_Download_Files.gif)


## Důležité upozornění

- Tento nástroj je vytvořen pro ofenzivní bezpečnostní aktivity a nesmí být nikdy použit k nelegálním účelům.
- Uživatelé přebírají veškerá rizika a odpovědnost za používání tohoto nástroje.
- Autor se zříká veškeré odpovědnosti za jakékoliv zneužití nebo škody způsobené použitím tohoto nástroje.
