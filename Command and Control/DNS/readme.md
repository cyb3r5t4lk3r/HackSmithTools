# DNS Tunnel C2 Simulation Tool (Python/Rust)

Tento projekt implementuje jednoduchý **reverzní Command and Control (C2) systém využívající DNS tunelování**. Je navržen primárně pro **vzdělávací účely, simulaci aktivit a testování** schopností bezpečnostních dohledových center (SOC) detekovat a reagovat na tento typ komunikace v kontrolovaném prostředí.

## Popis

Nástroj se skládá ze dvou hlavních komponent: serveru napsaného v Pythonu a klienta napsaného v Rustu. Klient (běžící na Windows) se připojuje k serveru (běžícímu na Linuxu) pomocí DNS dotazů maskovaných jako běžný DNS provoz. Server může klientovi posílat příkazy (pro `cmd.exe` nebo `powershell.exe`), které klient vykoná a výsledky pošle zpět na server, opět pomocí DNS tunelování.

Hlavním cílem je poskytnout funkční, ale přitom relativně jednoduchý nástroj pro pochopení principů DNS C2 a pro generování síťového provozu, který může být použit pro testování a validaci bezpečnostních monitorovacích systémů.

## Architektura

### **Server (Python):**
    - Běží na Linuxovém systému (doporučeno).
    - Naslouchá na UDP portu 53 (vyžaduje práva roota).
    - Přijímá DNS dotazy od klientů (`register`, `getcommand`, `response`).
    - Udržuje seznam připojených klientů.
    - Poskytuje interaktivní konzoli pro správu klientů a zadávání příkazů.
    - Přijímá a zobrazuje výsledky příkazů od klientů.
    - Podporuje volitelný DEBUG režim pro podrobné logování komunikace.
### **Klient (Rust):**
    - Navržen pro běh na **Windows**.
    - Po spuštění běží na pozadí bez viditelného okna nebo výstupu.
    - Automaticky se registruje u C2 serveru na nakonfigurované IP adrese.
    - Periodicky se dotazuje serveru na nové příkazy (`getcommand`).
    - Přijímá a sestavuje vícedílné příkazy.
    - Spouští příkazy pomocí `cmd.exe` (výchozí) nebo `powershell.exe` (lze přepnout příkazem ze serveru).
    - Shromažďuje `stdout` a `stderr` z provedeného příkazu.
    - Odesílá surové bajty výsledku (zakódované v Base64 a rozdělené na části) zpět na server pomocí DNS dotazů (`response`).
    - Nevytváří lokální logovací soubory ve finální verzi.
    - Obsahuje základní úpravy pro snížení pravděpodobnosti detekce AV (stripování symbolů, konstanty jako bajty).

## Klíčové vlastnosti

- **DNS Tunelování:** Veškerá komunikace mezi klientem a serverem je zapouzdřena do DNS dotazů a odpovědí (přes TXT záznamy a názvy domén), což umožňuje obejít běžné síťové filtry a firewally.
- **Reverzní spojení:** Klient aktivně navazuje spojení se serverem, což usnadňuje komunikaci přes NAT a firewally z klientské strany.
- **Přepínatelný Shell:** Server může klientovi nařídit, aby pro spouštění příkazů použil buď standardní `cmd.exe`, nebo `powershell.exe`.
- **Základní "Stealth" klienta:** Klient běží skrytě, nevytváří logy a má odstraněné debugovací symboly.
- **Interaktivní server:** Jednoduchá konzole pro správu více klientů a interakci s nimi.

## Použití

### Server (Python)

#### **Soubor:** `server.py`

##### **Prerekvizity:**

    - Linuxový systém (doporučeno, kvůli oprávněním a síťovým nástrojům).
    - Python 3.x.
    - Knihovna `dnslib`: `pip install dnslib` nebo `pip3 install dnslib`.
    - Práva roota (pro naslouchání na portu 53): Spouštět pomocí `sudo`.

##### **Konfigurace:**

    - Otevři soubor `dnsserver.py` v textovém editoru.
    - Najdi konstantu `LISTEN_IP` (na začátku souboru).
    - **Změň hodnotu `"VASE_VEREJNA_IP_ADRESA"` na skutečnou veřejnou IP adresu tvého serveru**, na které bude server naslouchat a na kterou se budou klienti připojovat. **Nenechávej zde `"0.0.0.0"` ani `"127.0.0.1"`**, pokud na serveru běží lokální DNS resolver (např. `systemd-resolved`), jinak server nenastartuje kvůli konfliktu portů.

##### **Spuštění:**

    ```bash
    sudo python3 dnsserver.py
    ```

##### **Příkazy konzole:**

    - `list`: Zobrazí seznam aktuálně připojených (registrovaných) klientů, jejich IP a čas posledního kontaktu.
    - `use <id_klienta | ip_klienta>`: Vybere klienta pro interakci. Můžeš použít ID klienta (např. `win_xxxxxx`) nebo jeho IP adresu. Prompt se změní na `C2 Server (id_klienta)>`.
    - `back`: Zruší výběr klienta. Prompt se vrátí na `C2 Server (Žádný klient)>`.
    - `status`: Zobrazí souhrnný stav serveru, včetně fronty příkazů a stavu jejich zpracování.
    - `debug`: Přepne (zapne/vypne) podrobný debugovací výstup na konzoli serveru. Užitečné pro ladění komunikace.
    - `exit`: Ukončí C2 server.
    - `help`: Zobrazí nápovědu k příkazům.
    - `<jakýkoli_příkaz>`: Pokud je vybrán klient (`use <id>`), jakýkoli jiný zadaný text je považován za příkaz, který se má odeslat tomuto klientovi a provést v jeho aktuálně nastaveném shellu.
    - `shell::ps` nebo `shell::powershell`: Speciální příkaz pro vybraného klienta, který mu nařídí přepnout na používání `powershell.exe` pro další příkazy (po vybrání klienta).
    - `shell::cmd`: Speciální příkaz pro vybraného klienta, který mu nařídí přepnout zpět na používání `cmd.exe` (výchozí) (po vybrání klienta).

### Klient (Rust)

#### **Soubor:** `src/main.rs` (a `Cargo.toml`)

#### **Cílová platforma:** Windows

#### **Prerekvizity (Kompilace):**

    - Nainstalované **Rust** vývojové prostředí (např. pomocí `rustup` z [https://rustup.rs/](https://rustup.rs/)).
    - **Cargo** (Rust package manager, instaluje se s `rustup`).
    - Pro kompilaci na Windows může být potřeba "Build Tools for Visual Studio" nebo MinGW (pokud ještě nejsou nainstalovány) - `rustup` by měl nabídnout instalaci potřebných součástí.
    - Inicializace projektu ve složce s projektem pomocí `cargo init --bin`

#### **Konfigurace:**

    - Otevři soubor `src/main.rs`.
    - Najdi konstantu `C2_IP` (na začátku souboru).
    - **Změň hodnotu IP adresy na veřejnou IP adresu tvého C2 serveru**, ke kterému se má klient připojovat. Musí to být stejná adresa, na které naslouchá server.

#### **Kompilace:**

    1.  Otevři příkazový řádek nebo terminál ve složce projektu (kde jsou `Cargo.toml` a složka `src`).
    2.  Spusť příkaz pro kompilaci optimalizované release verze:
        ```bash
        cargo build --release
        ```
    3.  Cargo stáhne potřebné závislosti (base64, rand, once_cell) a zkompiluje kód.
    4.  Výsledný spustitelný soubor se bude nacházet v podadresáři `target/release/`. Název souboru bude odpovídat názvu balíčku v `Cargo.toml` (např. `network_diagnostis_tool.exe`). Profil `release` v `Cargo.toml` zajišťuje optimalizace a odstranění debug symbolů (`strip = true`).

#### **Spuštění:**

    - Zkopíruj výsledný `.exe` soubor na cílový Windows stroj.
    - Spusť `.exe` soubor (např. poklepáním nebo z příkazového řádku).
    - Klient poběží na pozadí, nebude vidět žádné okno ani výstup na konzoli, ani nebude vytvářet logovací soubor. Automaticky se připojí k serveru a začne se dotazovat na příkazy.

## Obfuskace a detekce

Klient ve finální verzi obsahuje jen velmi základní úpravy ke snížení detekce:
- Odstranění logování.
- Odstranění debug symbolů a informací pomocí `strip = true` při kompilaci.
- Některé konstantní řetězce jsou uloženy jako pole bajtů.
- Použití `CREATE_NO_WINDOW` flagu při spouštění příkazů.

**Je důležité si uvědomit, že tyto úpravy nejsou robustní obfuskací.** Antivirové programy a EDR systémy mohou nástroj stále detekovat na základě jeho chování (specifické DNS dotazy, spouštění procesů `cmd.exe`/`powershell.exe`, síťová komunikace na port 53).

## Důležité upozornění

- Tento nástroj je vytvořen **výhradně pro vzdělávací účely, bezpečnostní výzkum, testování a simulaci útoků v kontrolovaném a autorizovaném prostředí.**
-  **Nikdy nepoužívejte tento nástroj pro nelegální aktivity nebo neoprávněný přístup** k systémům, které nevlastníte nebo ke kterým nemáte explicitní povolení k testování.
-  Autor nenese **žádnou odpovědnost** za případné škody nebo nelegální použití tohoto nástroje. Uživatel přebírá veškerá rizika a odpovědnost.
-  Při testování ve firemním nebo jiném spravovaném prostředí si **vždy vyžádejte explicitní písemné povolení** před spuštěním jakýchkoli testů.