# ChatGPT Interaction Tool

## Popis
PowerShell skript pro pokročilou komunikaci s OpenAI GPT asistentem pomocí oficiálního API. Skript podporuje různé módy komunikace, správu vláken a export odpovědí, což ho činí ideálním nástrojem pro automatizaci a integraci GPT asistenta do bezpečnostních workflows.

## Klíčové vlastnosti
- **Dva módy komunikace**: SingleThread a ContinuousThread pro různé typy interakcí
- **Bezpečné ukládání konfigurace**: Oddělené ukládání citlivých údajů (API klíč, ID asistenta)
- **Pokročilý export**: Možnost exportu odpovědí do souboru s podporou různých módů
- **Debug mód**: Rozšířené logování pro diagnostiku a ladění
- **Podpora diakritiky**: Plná podpora UTF-8 pro komunikaci v různých jazycích

## Instalace a požadavky
### Prerekvizity
- PowerShell 5.1 nebo vyšší
- Přístup k internetu
- OpenAI API klíč
- ID OpenAI asistenta
- Oprávnění pro zápis do lokálního adresáře

### Instalační postup
1. Stáhněte skript `Get-ChatGPTInteraction.ps1`
2. Umístěte ho do požadovaného adresáře
3. Proveďte inicializační konfiguraci (viz Použití)

## Použití

### 1. Inicializace (povinné před prvním použitím)
```powershell
.\Get-ChatGPTInteraction.ps1 -Initialize -ApiKey "vas-api-klic" -AssistantId "id-asistenta"
```

### 2. SingleThread mód
```powershell
# Základní použití
.\Get-ChatGPTInteraction.ps1 -Mode SingleThread -Message "Vaše zpráva"

# S exportem a debugováním
.\Get-ChatGPTInteraction.ps1 -Mode SingleThread -Message "Vaše zpráva" -ExportPath "output.txt" -ExportMode Session -EnableDebug
```

### 3. ContinuousThread mód
```powershell
# Základní použití
.\Get-ChatGPTInteraction.ps1 -Mode ContinuousThread -Message "Vaše zpráva"

# S exportem odpovědí
.\Get-ChatGPTInteraction.ps1 -Mode ContinuousThread -Message "Vaše zpráva" -ExportPath "chat_history.txt" -ExportMode Append
```

### 4. Smazání ContinuousThread vlákna
```powershell
.\Get-ChatGPTInteraction.ps1 -Mode ContinuousThread -DeleteThread
```

## Parametry
| Parametr | Popis | Povinný | Výchozí hodnota |
|----------|--------|----------|-----------------|
| Mode | Mód komunikace ("SingleThread"/"ContinuousThread") | Ne | "SingleThread" |
| Message | Zpráva pro asistenta | Ano* | - |
| DeleteThread | Smazání ContinuousThread vlákna | Ne | False |
| EnableDebug | Zapnutí debug módu | Ne | False |
| ExportPath | Cesta pro export odpovědí | Ne | - |
| ExportMode | Mód exportu ("Session"/"Append") | Ne | "Session" |
| Initialize | Inicializace konfigurace | Ne | False |
| ApiKey | OpenAI API klíč | Při inicializaci | - |
| AssistantId | ID asistenta | Při inicializaci | - |
| ApiVersion | Verze API | Ne | "assistants=v2" |

*Povinné, pokud není použit -DeleteThread nebo -Initialize

## Bezpečnostní poznámky
- Uchovávejte API klíč bezpečně
- Nesdílejte konfigurační soubor obsahující citlivé údaje
- Pravidelně obměňujte API klíče
- Kontrolujte exportované soubory na citlivé informace

## Video návod na použití
![Alt text](https://github.com/cyb3r5t4lk3r/HackSmithTools/blob/main/Media/ChatGPT_PowerShell.gif)

## Disclaimer
Tento nástroj je určen pro legitimní použití v rámci etického hackingu a penetračního testování. Autoři se zříkají odpovědnosti za jakékoliv zneužití nebo škody způsobené použitím tohoto nástroje.
