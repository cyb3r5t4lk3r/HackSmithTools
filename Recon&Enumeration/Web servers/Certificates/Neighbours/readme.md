# Extrakce CN z certifikátů (quick skener pro subnet sken)

Tento one-liner skenuje celý subnet a hledá certifikáty na serverech. Do příkazu je možné vložit vlastní porty pro HTTPS. Pomocí příkazu je možné v jednom vlákně skenovat velké množství IP adres s tím, že se vám vrátí název z certifikátu a hodnoty CN.

## Popis

Skript .

## Použití

### Prerekvizity

- Bash shell
- OpenSSL
- Timeout (obvykle součástí GNU Coreutils)

### Spuštění skriptu

1. Nastavte si název souboru a IP adresu pro CIDR /24.
2. nastavte případně timeout, který je nyní nastaven na 1 sec.
3. Spusťte příkaz následovně:

```bash
for i in {1..255};do outfile=output_111_111_111.txt;output=$(curl -m 1 --insecure -vvI https://111.111.111.$i:443 2>&1 | grep -e "Trying" -e "subject: CN=" | awk 'BEGIN{ ORS="" } { print $0 }' | sed 's/*   Trying //g' | sed 's/*  subject: CN=/|/g'); echo $output >> $outfile;clear;echo "Certificate scanner";cat $outfile; done
```

Výsledek je pak možné parsovat následovně
```bash
cat output_* | grep "|"
```

výsledek můžete pak očištit a ponechat jen názvy serverů bez větších detailů


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

