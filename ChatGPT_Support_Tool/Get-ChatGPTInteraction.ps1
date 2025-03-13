<#
.SYNOPSIS
    Skript pro komunikaci s OpenAI GPT asistentem pomocí API s podporou SingleThread a ContinuousThread módů.

.DESCRIPTION
    Tento skript umožňuje komunikaci s OpenAI GPT asistentem prostřednictvím API. Podporuje dva módy komunikace:
    - SingleThread: Každá konverzace probíhá v novém vlákně, které je po dokončení automaticky smazáno
    - ContinuousThread: Konverzace probíhá v jednom vlákně, které perzistuje mezi jednotlivými voláními

    Skript také podporuje exportování odpovědí do souboru ve dvou režimech (Session a Append) a obsahuje 
    pokročilé logování s možností debug módu.

.PARAMETER Mode
    Určuje mód komunikace. Možné hodnoty jsou "SingleThread" nebo "ContinuousThread".
    Výchozí hodnota je "SingleThread".

.PARAMETER DeleteThread
    Přepínač pro smazání aktivního ContinuousThread vlákna.

.PARAMETER Message
    Zpráva, která bude odeslána asistentovi.

.PARAMETER EnableDebug
    Přepínač pro zapnutí rozšířeného logování.

.PARAMETER ExportPath
    Cesta k souboru pro export odpovědí.

.PARAMETER ExportMode
    Určuje způsob exportu odpovědí. Možné hodnoty jsou:
    - "Session": Vytvoří nový soubor nebo přepíše existující při prvním exportu
    - "Append": Přidává odpovědi na konec existujícího souboru
    Výchozí hodnota je "Session".

.PARAMETER Initialize
    Přepínač pro inicializaci konfigurace.

.PARAMETER ApiKey
    OpenAI API klíč (používá se při inicializaci).

.PARAMETER AssistantId
    ID GPT asistenta (používá se při inicializaci).

.PARAMETER ApiVersion
    Verze OpenAI API. Výchozí hodnota je "assistants=v2".

.EXAMPLE
    # 1. Inicializace konfigurace:
    .\script.ps1 -Initialize -ApiKey "vas-api-klic" -AssistantId "id-asistenta"

    # 2. Použití SingleThread módu:
    .\script.ps1 -Mode SingleThread -Message "Vaše zpráva"
    
    # S exportem odpovědi:
    .\script.ps1 -Mode SingleThread -Message "Vaše zpráva" -ExportPath "odpovedi.txt" -ExportMode Session

    # 3. Použití ContinuousThread módu:
    .\script.ps1 -Mode ContinuousThread -Message "Vaše zpráva"
    
    # S exportem a debugováním:
    .\script.ps1 -Mode ContinuousThread -Message "Vaše zpráva" -EnableDebug -ExportPath "odpovedi.txt" -ExportMode Append

    # 4. Smazání ContinuousThread vlákna:
    .\script.ps1 -Mode ContinuousThread -DeleteThread

.NOTES
    Název:        Get-ChatGPTInteraction.ps1
    Autor:        Daniel Hejda
    Společnost:   Cyber Rangers s.r.o.
    Verze:        1.0
    Datum:        17.1.2024
    
    Požadavky:
    - PowerShell 5.1 nebo vyšší
    - Přístup k internetu
    - Platný OpenAI API klíč
    - ID OpenAI asistenta

.POSTUP
    1. Inicializace (povinné před prvním použitím)
       .\script.ps1 -Initialize -ApiKey "vas-api-klic" -AssistantId "id-asistenta" -ApiVersion "assistants=v2"

    2. SingleThread mód
       .\script.ps1 -Mode SingleThread -Message "Vaše zpráva"

    3. ContinuousThread mód
       .\script.ps1 -Mode ContinuousThread -Message "Vaše zpráva"

    4. Smazání ContinuousThread
       .\script.ps1 -Mode ContinuousThread -DeleteThread

.OUTPUTS
    - Textové odpovědi od GPT asistenta
    - Volitelný export odpovědí do souboru
    - Logy průběhu komunikace
#>

# Parametry pro spusteni skriptu
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("SingleThread", "ContinuousThread")]
    [string]$Mode = "SingleThread",  # SingleThread nebo ContinuousThread
    
    [Parameter(Mandatory=$false)]
    [switch]$DeleteThread,  # Prepinac pro smazani vlakna
    
    [Parameter(Mandatory=$false)]
    [string]$Message,  # Zprava pro asistenta
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableDebug,  # Debug mode pro logovani

    [Parameter(Mandatory=$false)]
    [string]$ExportPath,  # Cesta pro export odpovedi

    [Parameter(Mandatory=$false)]
    [ValidateSet("Session", "Append")]
    [string]$ExportMode = "Session",  # Typ exportu - Session (novy/prepis) nebo Append (pridat na konec)

    [Parameter(Mandatory=$false)]
    [switch]$Initialize,  # Prepinac pro inicializaci konfigurace

    [Parameter(Mandatory=$false)]
    [string]$ApiKey,  # OpenAI API klic pro inicializaci

    [Parameter(Mandatory=$false)]
    [string]$AssistantId,  # ID asistenta pro inicializaci

    [Parameter(Mandatory=$false)]
    [string]$ApiVersion = "assistants=v2"  # API verze pro inicializaci
)

# Validace parametru
if (-not $Initialize -and -not $DeleteThread -and [string]::IsNullOrEmpty($Message)) {
    throw "Parametr Message je povinny, pokud neni pouzit DeleteThread nebo Initialize"
}

Add-Type -AssemblyName System.Web

# Globální proměnné
$script:SessionFileInitialized = $false
$script:ConfigPath = Join-Path $PSScriptRoot "config.json"

# Globalni promenne pro logovani
$script:LogColors = @{
    DEBUG = "Yellow"
    INFO = "Cyan"
    ERROR = "Red"
    SUCCESS = "Green"
}

# Funkce pro správu konfigurace
function Initialize-Configuration {
    param (
        [string]$ApiKey,
        [string]$AssistantId,
        [string]$ApiVersion
    )
    
    try {
        $config = @{
            OPENAI_API_KEY = $ApiKey
            AssistantId = $AssistantId
            ApiVersion = $ApiVersion
            Headers = @{
                "Authorization" = "Bearer $ApiKey"
                "OpenAI-Beta" = $ApiVersion
            }
        }

        $config | ConvertTo-Json | Out-File -FilePath $script:ConfigPath -Encoding UTF8
        Write-CustomLog "Konfigurace byla uspesne ulozena" "SUCCESS"
        return $true
    }
    catch {
        Write-CustomLog "Chyba pri inicializaci konfigurace: $_" "ERROR"
        return $false
    }
}

function Get-Configuration {
    if (-not (Test-Path $script:ConfigPath)) {
        Write-CustomLog "Konfigurace nenalezena. Provedte nejdrive inicializaci pomoci parametru -Initialize" "ERROR"
        Write-CustomLog "Priklad: .\script.ps1 -Initialize -ApiKey 'vas-api-klic' -AssistantId 'id-asistenta'" "INFO"
        return $null
    }

    try {
        $config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
        return @{
            OPENAI_API_KEY = $config.OPENAI_API_KEY
            AssistantId = $config.AssistantId
            Headers = @{
                "Authorization" = "Bearer $($config.OPENAI_API_KEY)"
                "OpenAI-Beta" = $config.ApiVersion
            }
        }
    }
    catch {
        Write-CustomLog "Chyba pri nacitani konfigurace: $_" "ERROR"
        return $null
    }
}

# Jednoducha funkce pro logovani
function Write-CustomLog {
    param (
        [string]$Message,
        [string]$Type = "INFO"  # DEBUG, INFO, ERROR, SUCCESS
    )
    
    # Pokud je typ DEBUG a neni zapnuty debug mode, nic nevypisujeme
    if ($Type -eq "DEBUG" -and -not $EnableDebug) {
        return
    }
    
    $timestamp = Get-Date -Format "dd.MM.yyyy HH:mm:ss"
    $logMessage = "[$timestamp] [$Type] $Message"
    Write-Host $logMessage -ForegroundColor $LogColors[$Type]
}

# Funkce pro export odpovedi
function Export-Response {
    param (
        [string]$Response,
        [string]$Path,
        [string]$Mode = "Session"
    )
    if (-not [string]::IsNullOrEmpty($Path)) {
        try {
            # Pokud je to první export v Session módu, smažeme existující soubor
            if ($Mode -eq "Session" -and (Test-Path $Path) -and -not $script:SessionFileInitialized) {
                Remove-Item -Path $Path -Force
                $script:SessionFileInitialized = $true
                Write-CustomLog "Vytvarim novy soubor pro session" "DEBUG"
            }

            if ($Mode -eq "Session") {
                $Response | Out-File -FilePath $Path -Encoding UTF8 -Append
            }
            else {
                # Pro Append mód vždy přidáme prázdný řádek před novou odpověď
                if (Test-Path $Path) {
                    "`n" | Out-File -FilePath $Path -Encoding UTF8 -Append
                }
                $Response | Out-File -FilePath $Path -Encoding UTF8 -Append
            }
            Write-CustomLog "Odpoved byla exportovana do: $Path (Mode: $Mode)" "SUCCESS"
        }
        catch {
            Write-CustomLog "Chyba pri exportu odpovedi: $_" "ERROR"
        }
    }
}

# Funkce pro SingleThread
function Start-SingleThread {
    param (
        [string]$Message
    )
    Write-CustomLog "Spousteni v SingleThread modu" "INFO"
    $Message = [System.Web.HttpUtility]::UrlEncode($Message)
    
    try {
        # Vytvoreni vlakna
        Write-CustomLog "Vytvareni noveho vlakna" "DEBUG"
        $apiEndpoint = "https://api.openai.com/v1/threads"
        $response = Invoke-WebRequest -Uri $apiEndpoint -Method Post -Headers $config.Headers -ContentType "application/json"
        $threadId = ($response.content | ConvertFrom-Json).id
        Write-CustomLog "Vytvoreno vlakno: $threadId" "DEBUG"

        # Odeslani zpravy
        Write-CustomLog "Odesilani zpravy" "DEBUG"
        $apiEndpoint = "https://api.openai.com/v1/threads/$threadId/messages"
        $body = @{
            role = "user"
            content = $Message
        } | ConvertTo-Json
        
        $response = Invoke-WebRequest -Uri $apiEndpoint -Method Post -Headers $config.Headers -ContentType "application/json" -Body $body
        Write-CustomLog "Zprava uspesne odeslana" "SUCCESS"

        # Spusteni asistenta
        Write-CustomLog "Spousteni asistenta" "DEBUG"
        $apiEndpoint = "https://api.openai.com/v1/threads/$threadId/runs"
        $body = @{
            assistant_id = $config.AssistantId
        } | ConvertTo-Json
        
        $response = Invoke-WebRequest -Uri $apiEndpoint -Method Post -Headers $config.Headers -ContentType "application/json" -Body $body
        $runId = ($response.content | ConvertFrom-Json).id

        # Monitoring stavu
        Write-CustomLog "Cekani na odpoved" "INFO"
        do {
            $apiEndpoint = "https://api.openai.com/v1/threads/$threadId/runs/$runId"
            $response = Invoke-WebRequest -Uri $apiEndpoint -Method Get -Headers $config.Headers
            $status = ($response.content | ConvertFrom-Json).status
            Write-CustomLog "Status: $status" "DEBUG"
            Start-Sleep -Seconds 2
        } while ($status -ne "completed")

        # Ziskani odpovedi
        Write-CustomLog "Ziskavani odpovedi" "DEBUG"
        $apiEndpoint = "https://api.openai.com/v1/threads/$threadId/messages"
        $response = Invoke-WebRequest -Uri $apiEndpoint -Method Get -Headers $config.Headers -ContentType "application/json"
        Write-CustomLog "Response: $($response)" "DEBUG"

        # Před zpracováním odpovědi
        $responseContent = $response.Content | ConvertFrom-Json
        $rawAnswer = $responseContent.data[0].content[0].text.value

        # Převod na bytes a zpět na string s správným encodingem
        $bytes = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetBytes($rawAnswer)
        $answer = [System.Text.Encoding]::UTF8.GetString($bytes)
        
        Write-CustomLog "Odpoved asistenta:" "SUCCESS"
        Write-Host $answer -ForegroundColor Green
        Export-Response -Response $answer -Path $ExportPath -Mode $ExportMode

        # Smazani vlakna
        Write-CustomLog "Mazani vlakna" "DEBUG"
        $apiEndpoint = "https://api.openai.com/v1/threads/$threadId"
        $response = Invoke-WebRequest -Uri $apiEndpoint -Method Delete -Headers $config.Headers -ContentType "application/json"
        $deleted = ($response.content | ConvertFrom-Json).deleted
        
        if ($deleted -eq "true") {
            Write-CustomLog "Thread byl uspesne smazan" "SUCCESS"
        }
        else {
            Write-CustomLog "Thread nebyl smazan" "ERROR"
        }
    }
    catch {
        Write-CustomLog "Doslo k chybe: $_" "ERROR"
    }
}

# Funkce pro ContinuousThread
function Start-ContinuousThread {
    param (
        [string]$Message
    )
    
    $threadIdFile = ".\thread_id.txt"
    $Message = [System.Web.HttpUtility]::UrlEncode($Message)
    
    try {
        if ($DeleteThread) {
            if (Test-Path $threadIdFile) {
                $threadId = Get-Content $threadIdFile
                Write-CustomLog "Mazani vlakna $threadId" "INFO"
                
                $apiEndpoint = "https://api.openai.com/v1/threads/$threadId"
                $response = Invoke-WebRequest -Uri $apiEndpoint -Method Delete -Headers $config.Headers -ContentType "application/json"
                $deleted = ($response.content | ConvertFrom-Json).deleted
                
                if ($deleted -eq "true") {
                    Write-CustomLog "ContinuousThread byl uspesne smazan" "SUCCESS"
                    Remove-Item $threadIdFile
                }
                return
            }
            Write-CustomLog "Zadne aktivni vlakno neexistuje" "INFO"
            return
        }

        # Vytvoreni nebo nacteni vlakna
        if (!(Test-Path $threadIdFile)) {
            Write-CustomLog "Vytvareni noveho vlakna" "DEBUG"
            $apiEndpoint = "https://api.openai.com/v1/threads"
            $response = Invoke-WebRequest -Uri $apiEndpoint -Method Post -Headers $config.Headers -ContentType "application/json"
            $threadId = ($response.content | ConvertFrom-Json).id
            $threadId | Out-File $threadIdFile
        }
        else {
            $threadId = Get-Content $threadIdFile
        }
        
        Write-CustomLog "Pouzivam vlakno: $threadId" "INFO"

        # Odeslani zpravy
        Write-CustomLog "Odesilani zpravy" "DEBUG"
        $apiEndpoint = "https://api.openai.com/v1/threads/$threadId/messages"
        $body = @{
            role = "user"
            content = $Message
        } | ConvertTo-Json
        
        Write-CustomLog "Pouzivam body: $body" "DEBUG"

        $response = Invoke-WebRequest -Uri $apiEndpoint -Method Post -Headers $config.Headers -ContentType "application/json" -Body $body

        # Spusteni asistenta
        Write-CustomLog "Spousteni asistenta" "DEBUG"
        $apiEndpoint = "https://api.openai.com/v1/threads/$threadId/runs"
        $body = @{
            assistant_id = $config.AssistantId
        } | ConvertTo-Json
        
        $response = Invoke-WebRequest -Uri $apiEndpoint -Method Post -Headers $config.Headers -ContentType "application/json" -Body $body
        $runId = ($response.content | ConvertFrom-Json).id

        # Monitoring stavu
        Write-CustomLog "Cekani na odpoved" "INFO"
        do {
            $apiEndpoint = "https://api.openai.com/v1/threads/$threadId/runs/$runId"
            $response = Invoke-WebRequest -Uri $apiEndpoint -Method Get -Headers $config.Headers
            $status = ($response.content | ConvertFrom-Json).status
            Write-CustomLog "Status: $status" "DEBUG"
            Start-Sleep -Seconds 2
        } while ($status -ne "completed")

        # Ziskani odpovedi
        Write-CustomLog "Ziskavani odpovedi" "DEBUG"
        $apiEndpoint = "https://api.openai.com/v1/threads/$threadId/messages"
        $response = Invoke-WebRequest -Uri $apiEndpoint -Method Get -Headers $config.Headers -ContentType "application/json"
        Write-CustomLog "Response: $($response)" "DEBUG"

        # Před zpracováním odpovědi
        $responseContent = $response.Content | ConvertFrom-Json
        $rawAnswer = $responseContent.data[0].content[0].text.value

        # Převod na bytes a zpět na string s správným encodingem
        $bytes = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetBytes($rawAnswer)
        $answer = [System.Text.Encoding]::UTF8.GetString($bytes)

        Write-CustomLog "Odpoved asistenta:" "SUCCESS"
        Write-Host $answer -ForegroundColor Green
        Export-Response -Response $answer -Path $ExportPath -Mode $ExportMode
    }
    catch {
        Write-CustomLog "Doslo k chybe: $_" "ERROR"
    }
}

# Hlavni beh skriptu
if ($Initialize) {
    if ([string]::IsNullOrEmpty($ApiKey) -or [string]::IsNullOrEmpty($AssistantId)) {
        Write-CustomLog "Pro inicializaci je potreba zadat ApiKey a AssistantId" "ERROR"
        return
    }
    Initialize-Configuration -ApiKey $ApiKey -AssistantId $AssistantId -ApiVersion $ApiVersion
    return
}

# Načtení konfigurace
$config = Get-Configuration
if ($null -eq $config) {
    return
}

if ($DeleteThread -and $Mode -eq "ContinuousThread") {
    Start-ContinuousThread -Message ""
}
elseif ($Mode -eq "SingleThread") {
    Start-SingleThread -Message $Message
}
else {
    Start-ContinuousThread -Message $Message
}