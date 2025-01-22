#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Check Well-Known Files Scanner
============================

Tento skript slouží k automatizované kontrole přítomnosti standardních a well-known souborů 
na webových serverech. Je určen pro bezpečnostní profesionály a etické hackery k legitimnímu 
testování webových aplikací.

Funkce:
    - Kontrola existence security.txt, robots.txt, humans.txt a sitemap.xml
    - Podpora kontroly v root adresáři i ve složce .well-known
    - Validace obsahu nalezených souborů
    - Detekce kontaktních e-mailů
    - Export výsledků do JSON formátu

Použití:
    python3 check_well_known_files.py input_file.txt output_results.json

Požadavky:
    - Python 3.x
    - requests
    - colorama
    - concurrent.futures
    - json
    - re
    - argparse

Autor: Daniel Hejda | Cyber Rangers s.r.o.
Verze: 1.0.0

Bezpečnostní upozornění:
    Tento nástroj je určen pouze pro legitimní bezpečnostní testování
    a musí být používán v souladu s platnými zákony a se souhlasem
    vlastníka testovaného systému.
"""

import requests
from concurrent.futures import ThreadPoolExecutor
import json
import re
import argparse
from colorama import init, Fore, Style

# Inicializace Colorama
init(autoreset=True)

# Definice souborů, které chceme kontrolovat
files_to_check = [
    "security.txt",
    "robots.txt",
    ".well-known/security.txt",
    ".well-known/robots.txt",
    "humans.txt",
    "sitemap.xml",
]

# Skupiny souborů, které mohou být v rootu nebo ve .well-known
file_groups = {
    "security.txt": ["security.txt", ".well-known/security.txt"],
    "robots.txt": ["robots.txt", ".well-known/robots.txt"],
}

# Popisy souborů a míra rizika jejich neexistence
file_descriptions = {
    "security.txt": ("Tento soubor poskytuje informace o tom, jak nahlásit bezpečnostní zranitelnosti.", "Absence může ztížit rychlé nahlášení zranitelností."),
    "robots.txt": ("Tento soubor říká vyhledávačům, které části webu nemají indexovat. Správným nastavením lze zakázat známým AI modelům indexování a čtení obsahu jejich stránek.", "Vyhledávače mohou indexovat citlivé části webu, což může zvýšit riziko úniku citlivých informací."),
    ".well-known/security.txt": ("Tento soubor poskytuje standardizované umístění pro informace o bezpečnostních zranitelnostech.", "Standardizace usnadňuje nalezení informací o bezpečnosti."),
    ".well-known/robots.txt": ("Alternativní umístění pro robots.txt pro lepší viditelnost.", "Standardizace zlepšuje viditelnost pro vyhledávače."),
    "humans.txt": ("Tento soubor obsahuje informace o autorech webu.", "Poskytuje informace o tvůrcích webu pro lidské návštěvníky."),
    "sitemap.xml": ("Tento soubor poskytuje vyhledávačům mapu webu pro lepší indexaci.", "Absence může vést k horší indexaci a návštěvnosti z vyhledávačů."),
}

# Funkce pro kontrolu existence souboru na dané URL a zkontrolování jeho obsahu
def check_file(url, file_type):
    try:
        response = requests.get(url, timeout=5, allow_redirects=True)
        status_code = response.history[0].status_code if response.history else response.status_code
        if response.status_code == 200:
            content = response.text
            if file_type == "security.txt":
                if "Contact:" in content or "contact:" in content:
                    email_match = re.search(r'[\w\.-]+@[\w\.-]+', content)
                    email = email_match.group(0) if email_match else None
                    print(Fore.GREEN + "[+] " + Fore.RESET + f"Kontrola souboru na {url} (HTTP Status: {status_code})")
                    return True, email, status_code
            elif file_type == "robots.txt":
                if "User-agent:" in content or "user-agent:" in content:
                    print(Fore.GREEN + "[+] " + Fore.RESET + f"Kontrola souboru na {url} (HTTP Status: {status_code})")
                    return True, None, status_code
            elif file_type == "humans.txt":
                if "Team:" in content or "team:" in content:
                    print(Fore.GREEN + "[+] " + Fore.RESET + f"Kontrola souboru na {url} (HTTP Status: {status_code})")
                    return True, None, status_code
            elif file_type == "sitemap.xml":
                if "<?xml" in content and "<urlset" in content:
                    print(Fore.GREEN + "[+] " + Fore.RESET + f"Kontrola souboru na {url} (HTTP Status: {status_code})")
                    return True, None, status_code
        print(Fore.RED + "[-] " + Fore.RESET + f"Kontrola souboru na {url} (HTTP Status: {status_code})")
        return False, None, status_code
    except requests.RequestException as e:
        status_code = e.response.status_code if e.response else 'N/A'
        print(Fore.RED + "[-] " + Fore.RESET + f"Kontrola souboru na {url} (HTTP Status: {status_code})")
        return False, None, status_code

# Hlavní funkce pro kontrolu všech souborů pro daný web
def check_all_files_for_site(base_url):
    results = []
    for file, paths in file_groups.items():
        exists = False
        email = None
        status_code = None
        for path in paths:
            file_exists, found_email, status_code = check_file(f"{base_url}/{path}", file)
            if file_exists:
                exists = True
                email = found_email
                break
        description, risk = file_descriptions.get(file, ("N/A", "N/A"))
        results.append({
            "file": file,
            "exists": exists,
            "description": description,
            "risk": risk,
            "email": email,
            "status_code": status_code
        })
    
    # Kontrola ostatních souborů
    for file in files_to_check:
        if file not in file_groups:
            exists, _, status_code = check_file(f"{base_url}/{file}", file)
            description, risk = file_descriptions.get(file, ("N/A", "N/A"))
            results.append({
                "file": file,
                "exists": exists,
                "description": description,
                "risk": risk,
                "email": None,
                "status_code": status_code
            })
    
    return results

# Funkce pro načtení seznamu webů ze souboru
def load_websites_from_file(file_path):
    with open(file_path, "r") as file:
        return [line.strip() for line in file]

# Hlavní funkce pro kontrolu všech webů
def check_websites(input_file):
    websites = load_websites_from_file(input_file)
    all_results = {}

    for site in websites:
        print(Fore.LIGHTMAGENTA_EX + f"Kontrola webové stránky {site}")
        site_results = []
        for protocol in ["http://", "https://"]:
            base_url = f"{protocol}{site}"
            results = check_all_files_for_site(base_url)
            for result in results:
                site_results.append({
                    "protocol": protocol,
                    "file": result["file"],
                    "exists": result["exists"],
                    "description": result["description"],
                    "risk": result["risk"],
                    "email": result["email"],
                    "status_code": result["status_code"]
                })
        all_results[site] = site_results

    return all_results

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Check for the presence of security-related files on websites.')
    parser.add_argument('input_file', type=str, help='Path to the input file containing a list of websites')
    parser.add_argument('output_file', type=str, help='Path to the output JSON file to save results')
    args = parser.parse_args()

    results = check_websites(args.input_file)

    # Uložit výsledky do JSON souboru
    with open(args.output_file, "w") as json_file:
        json.dump(results, json_file, indent=4)

    # Výpis výsledků do terminálu ve formě tabulky
    print(f"{'Web':<50} {'File':<30} {'Exists':<10} {'Email':<30} {'Status':<10}")
    print("="*150)
    for site, files in results.items():
        for file_info in files:
            full_site = f"{file_info['protocol']}{site}"
            email = file_info['email'] if file_info['email'] else "N/A"
            status_code = file_info['status_code'] if file_info['status_code'] else "N/A"
            if file_info['exists']:
                print(Fore.GREEN + "[+] " + Fore.RESET + f"{full_site:<50} {file_info['file']:<30} {str(file_info['exists']):<10} {email:<30} {status_code:<10}")
            else:
                print(Fore.RED + "[-] " + Fore.RESET + f"{full_site:<50} {file_info['file']:<30} {str(file_info['exists']):<10} {email:<30} {status_code:<10}")
