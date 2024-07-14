# Kontrola přesměrování URL

Tento skript je navržen pro kontrolu přesměrování URL adres. Načte URL adresy ze zadaného vstupního souboru, provede HTTP request pomocí curl, a zapíše výsledky (včetně finálního URL) do zadaného výstupního souboru.

## Popis

Skript načte URL adresy z textového souboru, pro každou URL adresu provede HTTP request a zaznamená HTTP kód odpovědi a finální URL po přesměrování. Výsledky jsou uloženy do výstupního souboru.

## Použití

### Prerekvizity

- Bash shell
- Curl

### Spuštění skriptu

1. Ujistěte se, že máte správně nainstalované prerekvizity.
2. Vytvořte textový soubor s URL adresami, například `urls.txt`, kde každá URL adresa bude na novém řádku.
3. Spusťte skript s následujícím příkazem:

    ```bash
    ./check-url-redirect.sh vstupni_soubor.txt vystupni_soubor.txt
    ```

    kde `vstupni_soubor.txt` je cesta k souboru s URL adresami a `vystupni_soubor.txt` je cesta k souboru, do kterého budou zapsány výsledky.

## Ukázka spuštění a výstupu
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/url-redirects.gif)

## Důležité upozornění
- Tyto nástroje jsou vytvořeny pro ofenzivní bezpečnostní aktivity a nesmí být nikdy použity k nelegálním účelům.
- Uživatelé přebírají veškerá rizika a odpovědnost za používání těchto nástrojů.
- Autor se zříká veškeré odpovědnosti za jakékoliv zneužití nebo škody způsobené použitím těchto nástrojů.