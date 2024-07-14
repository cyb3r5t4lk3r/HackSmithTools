#!/bin/bash

# Název: Kontrola přesměrování URL
# Popis: Tento skript načte URL adresy ze zadaného vstupního souboru,
#        provede HTTP request pomocí curl a zapíše výsledky (včetně finálního URL)
#        do zadaného výstupního souboru.
# Použití: ./script.sh vstupni_soubor.txt vystupni_soubor.txt

# Kontrola správného počtu argumentů
if [ "$#" -ne 2 ]; then
    echo "Použití: $0 vstupni_soubor.txt vystupni_soubor.txt"
    exit 1
fi

# Cesta k vstupnímu souboru s URL adresami
inputFile="$1"

# Cesta k výstupnímu souboru
outputFile="$2"

# Kontrola, zda vstupní soubor existuje
if [ ! -f "$inputFile" ]; then
    echo "Soubor $inputFile neexistuje."
    exit 1
fi

# Vymazání obsahu výstupního souboru, pokud existuje, nebo jeho vytvoření
> "$outputFile"

# Čtení URL adres ze souboru a jejich zpracování
while IFS= read -r url; do
  if [ -n "$url" ]; then # Přeskočit prázdné řádky
    echo "Zpracovávám: $url"

    # Použití curl s timeoutem pro získání HTTP kódu, finálního URL a ověření odpovědi
    response=$(curl -Ls --connect-timeout 10 -o /dev/null -w "%{http_code} %{url_effective}" "$url")

    http_code=$(echo $response | cut -d' ' -f1)
    final_url=$(echo $response | cut -d' ' -f2-)

    # Kontrola, zda stránka odpověděla
    if [ "$http_code" == "000" ]; then
      echo "$url -> not responding" >> "$outputFile"
    else
      echo "$url $http_code -> $final_url" >> "$outputFile"
    fi
  fi
done < "$inputFile"

echo "Zpracování dokončeno. Výsledky jsou uloženy v souboru $outputFile."
