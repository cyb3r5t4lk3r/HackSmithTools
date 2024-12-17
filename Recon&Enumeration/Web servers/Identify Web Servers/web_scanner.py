#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Web Server Scanner
-----------------
Author: [Jméno autora]
Version: 1.4.1
Last update: 2024-12-17

Description:
    Skript pro skenování webových serverů na základě NMAP grepovatelného výstupu.
    Kontroluje dostupnost HTTP/HTTPS služeb a získává title ze stránek.
    Sleduje přesměrování a poskytuje detailní informace o nalezených webových serverech.
    Automaticky filtruje známé porty pro jiné služby než web servery.
    Podporuje paralelní zpracování a komplexní logování.
"""

import requests
import concurrent.futures
from urllib3.exceptions import InsecureRequestWarning
from bs4 import BeautifulSoup
import socket
from typing import List, Tuple, Optional, Set, Dict
import pandas as pd
import argparse
import logging
import sys
from datetime import datetime
import os
import re
from tabulate import tabulate
from colorama import init, Fore, Back, Style
import json

# Inicializace colorama pro Windows
init()

# Vypnutí varování pro necertifikované HTTPS
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

# Seznam portů, které chceme ignorovat
IGNORED_PORTS = {21, 22, 23, 135, 139, 445, 3389}

def setup_logging(verbose: bool = False, debug: bool = False) -> None:
    """Nastavení logování na základě úrovně detailů."""
    log_format = '%(asctime)s - %(levelname)s - %(message)s'
    
    if not os.path.exists('logs'):
        os.makedirs('logs')
    
    log_file = f'logs/web_scanner_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log'
    
    if debug:
        log_level = logging.DEBUG
    elif verbose:
        log_level = logging.INFO
    else:
        log_level = logging.WARNING
    
    logging.basicConfig(
        level=log_level,
        format=log_format,
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler(sys.stdout)
        ]
    )

def parse_nmap_output(filename: str) -> Tuple[List[Tuple[str, int, str]], Dict[str, str]]:
    """Parsuje NMAP grepovatelný výstup a vrací seznam IP adres, portů a hostname."""
    targets = []
    hosts_info: Dict[str, str] = {}
    
    try:
        with open(filename, 'r') as f:
            lines = f.readlines()
            
        for line in lines:
            line = line.strip()
            
            if 'Status: Up' in line:
                parts = line.split()
                ip = parts[1]
                hostname = parts[2].strip('()')
                hosts_info[ip] = hostname
                print(f"Nalezen host: {ip} ({hostname})")
            
            elif 'Ports:' in line:
                ip = line.split()[1]
                ports_section = line.split('Ports: ')[1]
                hostname = hosts_info.get(ip, '')
                
                port_entries = ports_section.split(',')
                
                for entry in port_entries:
                    if '/open/tcp//' in entry:
                        port = int(entry.split('/')[0])
                        if port not in IGNORED_PORTS:
                            targets.append((ip, port, hostname))
                            print(f"Nalezen otevřený port: {ip} ({hostname}) : {port}")
    
    except FileNotFoundError:
        logging.error(f"Vstupní soubor {filename} nebyl nalezen")
        sys.exit(1)
    except Exception as e:
        logging.error(f"Chyba při parsování NMAP výstupu: {str(e)}")
        sys.exit(1)
    
    print(f"\nCelkem nalezeno {len(targets)} potenciálních webových serverů k otestování")
    return targets, hosts_info

def get_web_title(ip: str, port: int, hostname: str, timeout: int = 5) -> Optional[dict]:
    """Zkontroluje webový server pomocí HTTP hlaviček."""
    print(f"\nKontroluji {ip}:{port} ({hostname})")
    
    result = {
        'ip': ip,
        'hostname': hostname,
        'port': port,
        'is_web': False,
        'protocol': None,
        'title': None,
        'server': None,
        'redirect_url': None,
        'final_url': None,
        'status_code': None,
        'headers': None,
        'error': None
    }
    
    protocols = ['https', 'http']
    session = requests.Session()
    session.verify = False
    
    headers = {
        'User-Agent': 'curl/7.88.1',
        'Accept': '*/*',
        'Accept-Encoding': 'gzip, deflate'
    }
    
    for protocol in protocols:
        url = f"{protocol}://{ip}:{port}"
        print(f"  Zkouším {url}")
        
        try:
            initial_response = session.get(
                url,
                timeout=timeout,
                allow_redirects=False,
                headers=headers
            )
            
            print(f"    ← Získána odpověď: HTTP {initial_response.status_code}")
            
            if initial_response.status_code:
                result.update({
                    'is_web': True,
                    'protocol': protocol,
                    'status_code': initial_response.status_code,
                    'headers': dict(initial_response.headers),
                    'server': initial_response.headers.get('Server', 'Unknown')
                })
                
                if initial_response.status_code in [301, 302, 303, 307, 308]:
                    redirect_url = initial_response.headers.get('Location')
                    if redirect_url:
                        if redirect_url.startswith('/'):
                            redirect_url = f"{protocol}://{ip}:{port}{redirect_url}"
                        elif not redirect_url.startswith(('http://', 'https://')):
                            redirect_url = f"{protocol}://{ip}:{port}/{redirect_url}"
                        
                        print(f"    → Přesměrování na: {redirect_url}")
                        result['redirect_url'] = redirect_url
                        
                        try:
                            redirect_response = session.get(
                                redirect_url,
                                timeout=timeout,
                                allow_redirects=True,
                                headers=headers
                            )
                            
                            print(f"    ← Odpověď z přesměrování: HTTP {redirect_response.status_code}")
                            result['final_url'] = redirect_response.url
                            
                            if 'text/html' in redirect_response.headers.get('Content-Type', '').lower():
                                try:
                                    soup = BeautifulSoup(redirect_response.text, 'html.parser')
                                    title = soup.title.string if soup.title else "No title found"
                                    result['title'] = title.strip() if title else None
                                except:
                                    result['title'] = "Cannot parse title"
                        except Exception as e:
                            print(f"    ✗ Nelze následovat přesměrování: {str(e)}")
                else:
                    result['final_url'] = url
                
                print(f"\n  ✓ Nalezen webový server ({protocol})")
                print(f"    Status: {result['status_code']}")
                print(f"    Server: {result['server']}")
                if result['title']:
                    print(f"    Title: {result['title']}")
                
                return result
                
        except requests.exceptions.SSLError:
            print(f"    → SSL Error")
            continue
        except requests.exceptions.ConnectionError:
            print(f"    ✗ Connection Error")
            result['error'] = "Connection Error"
        except requests.exceptions.Timeout:
            print(f"    ✗ Timeout")
            result['error'] = "Timeout"
        except Exception as e:
            print(f"    ✗ Neočekávaná chyba: {str(e)}")
            result['error'] = f"Other Error: {str(e)}"
    
    return result

def scan_targets(targets: List[Tuple[str, int, str]], max_workers: int = 5) -> pd.DataFrame:
    """Skenuje všechny cíle paralelně."""
    results = []
    print(f"\nZačínám skenování {len(targets)} cílů s {max_workers} vlákny")
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_ip = {
            executor.submit(get_web_title, ip, port, hostname): (ip, port, hostname) 
            for ip, port, hostname in targets
        }
        
        for future in concurrent.futures.as_completed(future_to_ip):
            result = future.result()
            results.append(result)
    
    print("\nSkenování dokončeno")
    return pd.DataFrame(results)

def format_table_row(row: pd.Series) -> List[str]:
    """Formátuje řádek tabulky s barevným zvýrazněním."""
    is_web = row['is_web']
    has_redirect = bool(row['redirect_url'])
    has_error = bool(row['error'])
    
    if is_web:
        color = Fore.GREEN
    elif has_error:
        color = Fore.RED
    else:
        color = Fore.WHITE
    
    formatted_row = [
        f"{color}{row['ip']}{Style.RESET_ALL}",
        f"{color}{row['hostname'] if pd.notna(row['hostname']) else ''}{Style.RESET_ALL}",
        f"{color}{row['port']}{Style.RESET_ALL}",
        f"{color}{row['protocol'] if pd.notna(row['protocol']) else ''}{Style.RESET_ALL}",
        f"{Fore.GREEN}✓{Style.RESET_ALL}" if is_web else f"{Fore.RED}✗{Style.RESET_ALL}",
        f"{color}{str(row['status_code']) if pd.notna(row['status_code']) else ''}{Style.RESET_ALL}",
        f"{color}{row['title'] if pd.notna(row['title']) else ''}{Style.RESET_ALL}",
        f"{color}{row['final_url'] if pd.notna(row['final_url']) else ''}{Style.RESET_ALL}",
    ]
    
    return formatted_row

def print_results_table(df: pd.DataFrame) -> None:
    """Vytiskne výsledky jako formátovanou tabulku."""
    table_data = []
    for _, row in df.iterrows():
        table_data.append(format_table_row(row))
    
    headers = ['IP', 'Hostname', 'Port', 'Protocol', 'Web', 'Status', 'Title', 'Final URL']
    
    print("\nVýsledky skenování:")
    print(tabulate(table_data, headers=headers, tablefmt='grid'))

def main():
    parser = argparse.ArgumentParser(description='Web Server Scanner')
    parser.add_argument('-i', '--input', required=True, help='Vstupní soubor s NMAP výstupem')
    parser.add_argument('-o', '--output', required=True, help='Výstupní CSV soubor')
    parser.add_argument('-v', '--verbose', action='store_true', help='Zapne podrobné logování')
    parser.add_argument('-d', '--debug', action='store_true', help='Zapne debug mód')
    parser.add_argument('-w', '--workers', type=int, default=5, help='Počet paralelních vláken')
    parser.add_argument('-t', '--timeout', type=int, default=5, help='Timeout pro připojení v sekundách')
    
    args = parser.parse_args()
    
    setup_logging(args.verbose, args.debug)
    
    print("=== Web Server Scanner ===")
    print(f"Vstupní soubor: {args.input}")
    print(f"Výstupní soubor: {args.output}")
    print(f"Počet vláken: {args.workers}")
    print(f"Timeout: {args.timeout}s")
    print("=" * 24 + "\n")
    
    targets, hosts_info = parse_nmap_output(args.input)
    
    if not targets:
        print("Nebyly nalezeny žádné potenciální webové servery")
        sys.exit(1)
    
    results_df = scan_targets(targets, args.workers)
    
    # Setřídění a uložení výsledků
    output_columns = [
        'ip', 'hostname', 'port', 'protocol', 'is_web', 'status_code',
        'title', 'final_url', 'redirect_url', 'headers'
    ]
    
    # Konverze headers na string pro CSV export
    results_df['headers'] = results_df['headers'].apply(lambda x: json.dumps(x) if x else None)
    
    results_df[output_columns].to_csv(args.output, index=False)
    print(f"\nVýsledky byly uloženy do souboru {args.output}")
    
    # Výpis souhrnných statistik
    web_servers = results_df['is_web'].sum()
    redirects = results_df['redirect_url'].notna().sum()
    total_servers = len(results_df)
    
    # Zobrazení výsledků v tabulce
    print_results_table(results_df)
    
    print(f"\n{Fore.CYAN}Souhrnné statistiky:{Style.RESET_ALL}")
    print(f"- Celkem zkontrolováno: {total_servers} serverů")
    print(f"- Nalezeno webových serverů: {Fore.GREEN}{web_servers}{Style.RESET_ALL}")
    print(f"- Počet přesměrování: {Fore.YELLOW}{redirects}{Style.RESET_ALL}")

if __name__ == "__main__":
    main()