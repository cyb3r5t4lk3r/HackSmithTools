# Check Well-Known Files
Tento skript je navržen pro automatizovanou kontrolu přítomnosti standardních a well-known souborů na webových serverech. Nástroj je součástí kolekce Web Testing & Automation Tools a slouží k základnímu průzkumu webových aplikací v rámci bezpečnostního testování.

## Obecný popis:
- Automatizovaná kontrola přítomnosti důležitých souborů jako security.txt, robots.txt, humans.txt a sitemap.xml
- Podpora kontroly souborů v root adresáři i ve standardizované složce .well-known
- Detekce správného formátu obsahu kontrolovaných souborů
- Validace kontaktních informací v security.txt
- Paralelní zpracování více webů současně
- Barevně označený výstup pro lepší čitelnost výsledků
- Export výsledků do JSON formátu pro další zpracování

## Funkce:
- Kontrola existence a validace obsahu standardních webových souborů
- Podpora HTTP i HTTPS protokolu
- Zpracování seznamu webů ze vstupního souboru
- Detailní reporting včetně HTTP stavových kódů
- Detekce kontaktních e-mailů v security.txt
- Validace formátu robots.txt, humans.txt a sitemap.xml

## Použití:

```bash
python3 check_well_known_files.py input_file.txt output_results.json
```

## Požadavky:
- Python 3.x
- Knihovny: requests, colorama, concurrent.futures, json, re, argparse

## Výstup:
- Přehledná tabulka výsledků v terminálu
- Detailní JSON report obsahující všechny nalezené informace
- Barevně označené výsledky pro rychlou orientaci

## Bezpečnostní poznámka:
Tento nástroj je určen pro bezpečnostní profesionály a etické hackery k legitimnímu testování webových aplikací. Použití musí být v souladu s platnými zákony a se souhlasem vlastníka testovaného systému.

## Důležité upozornění:
- Nástroj je určen výhradně pro legitimní bezpečnostní testování.
- Používejte pouze na systémech, ke kterým máte oprávnění.
- Autor nenese odpovědnost za případné zneužití nástroje.