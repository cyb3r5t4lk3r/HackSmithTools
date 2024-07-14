#!/bin/bash

# Název: Extrakce CN a SAN z certifikátů
# Popis: Tento skript načte URL adresy ze zadaného vstupního souboru,
#        extrahuje Common Name (CN) a Subject Alternative Names (SAN) 
#        z certifikátů pomocí OpenSSL a uloží výsledky do zadaného 
#        výstupního souboru.
# Použití: ./certs.sh vstupni_soubor.txt vystupni_soubor.txt

# Kontrola správného počtu argumentů
if [ "$#" -ne 2 ]; then
    echo "Použití: $0 vstupni_soubor.txt vystupni_soubor.txt"
    exit 1
fi

# Cesta k vstupnímu souboru s URL adresami
urls_file="$1"

# Cesta k výstupnímu souboru
output_file="$2"

# Smazání obsahu výstupního souboru, pokud již existuje
> "$output_file"

# Načtení adres z souboru do proměnné, přeskočení prázdných řádků
mapfile -t urls < <(grep -v '^$' "$urls_file")

# Iterace přes každou adresu
for url in "${urls[@]}"; do
    echo "Zpracovávám: $url"
    # Odstranění 'https://' a extrakce hostitele a portu
    host=$(echo "$url" | sed 's|https://||g' | cut -d':' -f1)
    port=$(echo "$url" | sed 's|https://||g' | cut -s -d':' -f2)
    port=${port:-443} # Použití výchozího portu 443, pokud není specifikován

    # Získání certifikátu pomocí openssl s timeoutem a potlačení chybových zpráv
    cert=$(timeout 10 openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>&1 | openssl x509 -noout -text 2>/dev/null)

    # Kontrola, zda byl certifikát úspěšně získán
    if [ $? -ne 0 ]; then
        echo "Nepodařilo se získat certifikát pro $url nebo byl překročen timeout"
        continue
    fi

    # Extrahování Common Name (CN) z certifikátu
    cn=$(echo "$cert" | grep "Subject:" | sed -n 's/.*CN\s*=\s*\([^,]*\).*/\1/p')

    # Kontrola a zápis Common Name do souboru
    if [ ! -z "$cn" ]; then
        echo "$url, $cn" >> "$output_file"
    fi

    # Extrahování Subject Alternative Names (SAN)
    sans=$(echo "$cert" | grep "X509v3 Subject Alternative Name:" -A1 | tail -n1 | sed -e 's/DNS://g' -e 's/, /\n/g')

    # Zápis Subject Alternative Names do souboru
    while read -r san; do
        if [ ! -z "$san" ]; then
            echo "$url, $san" >> "$output_file"
        fi
    done <<< "$sans"
done

echo "Skript dokončil zápis Common Names a Subject Alternative Names do $output_file."
