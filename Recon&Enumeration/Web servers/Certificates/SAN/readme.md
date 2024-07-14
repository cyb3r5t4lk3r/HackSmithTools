# Extrakce CN a SAN z certifikátů

Tento skript je navržen pro extrakci Common Name (CN) a Subject Alternative Names (SAN) z certifikátů webových serverů. Vstupní URL adresy jsou načteny ze zadaného vstupního souboru a výsledky jsou uloženy do zadaného výstupního souboru.

## Popis

Skript načte URL adresy z textového souboru, pro každou URL adresu získá SSL/TLS certifikát a extrahuje z něj Common Name (CN) a Subject Alternative Names (SAN). Tyto informace jsou poté zapsány do výstupního souboru.

## Použití

### Prerekvizity

- Bash shell
- OpenSSL
- Timeout (obvykle součástí GNU Coreutils)

### Spuštění skriptu

1. Ujistěte se, že máte správně nainstalované prerekvizity.
2. Vytvořte textový soubor s URL adresami, například `urls.txt`, kde každá URL adresa bude na novém řádku.
3. Spusťte skript s následujícím příkazem:

```bash
./script.sh vstupni_soubor.txt vystupni_soubor.txt
```

kde `vstupni_soubor.txt` je cesta k souboru s URL adresami a `vystupni_soubor.txt` je cesta k souboru, do kterého budou zapsány výsledky.

## Využití při ofensivním testování
Tento skript může být užitečný při ofensivním testování v následujících případech:

- Mapování certifikátů: Rychlé získání seznamu domén a subdomén, které jsou uvedeny v SSL/TLS certifikátech cílových serverů. To může odhalit další povrch pro útok.
- Kontrola konfigurace: Pomocí tohoto skriptu můžete ověřit, zda jsou certifikáty správně nastaveny a zda odpovídají očekávaným doménám.
- Identifikace zranitelných míst: Analýza certifikátů může pomoci identifikovat nesprávně nakonfigurované servery nebo zastaralé certifikáty, které mohou být zranitelné vůči různým typům útoků.

## Ukázka spuštění a výstupu
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/Certs-SAN.gif)

## Důležité upozornění
- Tyto nástroje jsou vytvořeny pro ofenzivní bezpečnostní aktivity a nesmí být nikdy použity k nelegálním účelům.
- Uživatelé přebírají veškerá rizika a odpovědnost za používání těchto nástrojů.
- Autor se zříká veškeré odpovědnosti za jakékoliv zneužití nebo škody způsobené použitím těchto nástrojů.

