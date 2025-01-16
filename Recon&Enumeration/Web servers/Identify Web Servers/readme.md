# Kontrola a identifikace webových serverů z NMAP skenu

## Popis

Skript pro skenování webových serverů na základě NMAP grepovatelného výstupu. Kontroluje dostupnost HTTP/HTTPS služeb a získává title ze stránek. Sleduje přesměrování a poskytuje detailní informace o nalezených webových serverech. Automaticky filtruje známé porty pro jiné služby než web servery. Podporuje paralelní zpracování a komplexní logování.

## Použití

### Prerekvizity

- Bash shell
- Curl
- pip install requests beautifulsoup4 pandas tabulate colorama

### Spuštění skriptu

1. Ujistěte se, že máte správně nainstalované prerekvizity.
2. Spusťte skript s následujícím příkazem:

    ```bash
    ./python web_scanner.py -i <nmap_grepable_output_file> -o <output_file> [-v] [-d] [-w workers] [-t timeout]
    ```

3. Parsujte výsledky pomocí

    ```bash
    final_URL after redirection:
        awk -F',' '$5 == "True" {print $9}' input.csv | grep -v "^final_url"
    urls from protocol, ip, port:
        awk -F',' '$5 == "True" {printf "%s://%s:%s\n", $4, $1, $3}' input.csv | grep -v "^protocol"
    ```
### Parametry scriptu
    -i, --input     : Vstupní soubor s NMAP grepovatelným výstupem
    -o, --output    : Výstupní CSV soubor s výsledky
    -v, --verbose   : Zapne podrobné logování
    -d, --debug     : Zapne debug mód
    -w, --workers   : Počet paralelních vláken (default: 5)
    -t, --timeout   : Timeout pro připojení v sekundách (default: 5)

## Ukázka spuštění a výstupu
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/none.gif)

## Důležité upozornění
- Tyto nástroje jsou vytvořeny pro ofenzivní bezpečnostní aktivity a nesmí být nikdy použity k nelegálním účelům.
- Uživatelé přebírají veškerá rizika a odpovědnost za používání těchto nástrojů.
- Autor se zříká veškeré odpovědnosti za jakékoliv zneužití nebo škody způsobené použitím těchto nástrojů.