<#
.SYNOPSIS
    LinkedIn People Scraper - nastroj pro extrakci osob pridruzených ke konkretni spolecnosti na LinkedIn.

.DESCRIPTION
    Tento skript extrahuje informace o osobach pracujicich v zadane spolecnosti z LinkedIn.
    Extrahuje jmeno, pozici, lokalitu, URL profilu a profilovy obrazek.
    Vystupy uklada ve formatech JSON a CSV. 
    
    POZOR: Je nutne aby bylo prostredi LinkedIn prepnuto do Cestiny, jinak nebude fungovat hledani pro pagging.

.PARAMETER CompanyId
    ID spolecnosti na LinkedIn. 

.PARAMETER ManualLogin
    Prepinac pro manualni prihlaseni uzivatelem (podporuje MFA).

.PARAMETER Visible
    Prepinac pro zobrazeni prohlizece behem scrapovani.

.EXAMPLE
    .\LinkedInPeopleScraper.ps1 -CompanyId "000000" -ManualLogin -Visible

.NOTES
    Autor: Daniel Hejda
    Company: Cyber Rangers s.r.o.
    Datum: 20.03.2025
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$CompanyId,
    
    [Parameter(Mandatory = $false)]
    [switch]$ManualLogin,
    
    [Parameter(Mandatory = $false)]
    [switch]$Visible
)

# Funkce pro logovani s barvami
function Write-ColorLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Color = "White",
        
        [Parameter(Mandatory = $false)]
        [switch]$NoNewLine
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($NoNewLine) {
        Write-Host -ForegroundColor $Color "[$($timestamp)] $($Message)" -NoNewline
    } else {
        Write-Host -ForegroundColor $Color "[$($timestamp)] $($Message)"
    }
}

# Funkce pro instalaci pozadovanych modulu
function Install-RequiredModules {
    Write-ColorLog "Kontrola a instalace pozadovanych modulu..." "Cyan"
    
    # Seznam pozadovanych modulu
    $requiredModules = @("Selenium", "ImportExcel")
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-ColorLog "Instalace modulu $module..." "Yellow"
            try {
                Install-Module -Name $module -Force -Scope CurrentUser -AllowClobber
                Write-ColorLog "Modul $module uspesne nainstalovan." "Green"
            } catch {
                Write-ColorLog "Chyba pri instalaci modulu $($module): $($_.Exception.Message)" "Red"
                exit 1
            }
        } else {
            Write-ColorLog "Modul $module je jiz nainstalovan." "Green"
        }
    }
}

# Funkce pro stahovani a instalaci WebDriver pro Edge
function Install-EdgeWebDriver {
    Write-ColorLog "Kontrola a instalace WebDriver pro Microsoft Edge..." "Cyan"
    
    try {
        # Ziskani verze Edge z Procesu
        $edgeVersion = $null
        try {
            $edgePath = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe').'(Default)'
            if ($edgePath) {
                $edgeVersion = (Get-Item $edgePath).VersionInfo.ProductVersion
            }
        } catch {
            Write-ColorLog "Nelze ziskat verzi Edge z cesty k procesu..." "Yellow"
        }

        # Pokud stale nemame verzi, zkusime ziskat ji z AppxPackage
        if (-not $edgeVersion) {
            try {
                $edgeVersion = (Get-AppxPackage -Name Microsoft.MicrosoftEdge.Stable).Version
            } catch {
                Write-ColorLog "Nelze ziskat verzi Edge pomoci AppxPackage, zkousim registr..." "Yellow"
            }
        }        
        
        # Pokud stale nemame verzi, zkusime ziskat ji z Registru
        if (-not $edgeVersion) {
            try {
                $edgeVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Edge\BLBeacon').version
            } catch {
                Write-ColorLog "Nelze ziskat verzi Edge z registru, zkousim alternativni cestu..." "Yellow"
            }
        }
        
        # Kdyz ji nenajdeme vratime chybu
        if (-not $edgeVersion) {
            throw "Nelze zjistit verzi Microsoft Edge. Prosim nainstalujte Microsoft Edge."
        }
        
        Write-ColorLog "Zjistena verze Microsoft Edge: $($edgeVersion)" "Green"
        
        # Extrakce hlavni verze Edge (pro nalezeni spravneho WebDriveru)
        $majorVersion = $edgeVersion.Split('.')[0]
        Write-ColorLog "Hlavni verze Edge: $($majorVersion)" "Green"
        
        # Vytvoreni adresare pro WebDriver, pokud neexistuje
        $driverPath = "$($env:USERPROFILE)\EdgeWebDriver"
        if (-not (Test-Path $driverPath)) {
            New-Item -Path $driverPath -ItemType Directory -Force | Out-Null
        }
        
        # Kontrola, zda WebDriver jiz existuje
        $driverExe = "$($driverPath)\msedgedriver.exe"

        $WebDriverInfo = Get-Item $driverExe -ErrorAction SilentlyContinue
        If(-not ($WebDriverInfo.VersionInfo.ProductVersion -eq $edgeVersion)){
            Remove-Item -LiteralPath $driverPath -Force  -Recurse -Confirm:$false
            Write-ColorLog "WebDriver smazan, protoze byl ve verzi $($WebDriverInfo.VersionInfo.ProductVersion) a aktualni verze prohlizece je  $($edgeVersion)" "Green"
        }

        if (-not (Test-Path $driverExe)) {
            # Nalezeni spravneho WebDriveru z noveho uloziste Microsoft
            Write-ColorLog "Hledani dostupnych verzi WebDriveru pro Edge..." "Yellow"
            
            # Pouzijeme nove uloziste WebDriveru Microsoft
            $coreUrl = "https://msedgedriver.azureedge.net"
            $baseUrl = "$($coreUrl)/$($edgeVersion)/edgedriver_win64.zip"
            
            Write-ColorLog "Stahovani WebDriveru z $($driverUrl)..." "Yellow"
            $zipPath = "$($env:TEMP)\edgedriver_win64.zip"
            $webContent = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -OutFile $zipPath
            
            # Rozbaleni WebDriveru
            Write-ColorLog "Rozbalovani WebDriveru..." "Yellow"
            Expand-Archive -Path $zipPath -DestinationPath $driverPath -Force
            Remove-Item $zipPath -Force
            
            Write-ColorLog "WebDriver uspesne nainstalovan do $($driverPath)" "Green"
        } else {
            Write-ColorLog "WebDriver je jiz nainstalovan v $($driverPath)" "Green"
        }
        
        # Pridani cesty k WebDriver do PATH, pokud tam jeste neni
        $env:PATH = "$($driverPath);$($env:PATH)"
        return $driverPath
    } catch {
        Write-ColorLog "Chyba pri instalaci WebDriver pro Edge: $($_.Exception.Message)" "Red"
        exit 1
    }
}

# Funkce pro inicializaci prohlizece
function Initialize-Browser {
    param (
        [bool]$Visible
    )
    
    Write-ColorLog "Inicializace prohlizece Microsoft Edge..." "Cyan"
    
    try {
        # Nacteni Selenium modulu
        Import-Module Selenium
        
        # Nastaveni cesty k WebDriver
        $driverPath = Install-EdgeWebDriver
        
        # Konfigurace Edge
        $edgeOptions = New-Object OpenQA.Selenium.Edge.EdgeOptions
        
        # Zjistime dostupne metody a vlastnosti objektu EdgeOptions
        $methods = $edgeOptions | Get-Member -MemberType Method
        $properties = $edgeOptions | Get-Member -MemberType Property
        
        Write-ColorLog "Dostupne metody EdgeOptions: $($methods.Name -join ', ')" "Yellow"
        
        try {
            # Pouzivame dostupnou metodu AddAdditionalCapability pro nastaveni argumentu
            Write-ColorLog "Pouzivam metodu AddAdditionalCapability pro nastaveni argumentu" "Green"
            
            # Vytvoreni seznamu argumentu
            $args = New-Object System.Collections.Generic.List[string]
            
            if (-not $Visible) {
                $args.Add('headless')
            }
            $args.Add('disable-gpu')
            $args.Add('no-sandbox')
            $args.Add('disable-dev-shm-usage')
            $args.Add('disable-extensions')
            $args.Add('disable-popup-blocking')
            
            # Pridani argumentu pomoci AddAdditionalCapability
            $edgeOptions.AddAdditionalCapability("args", $args)
        }
        catch {
            Write-ColorLog "Chyba pri nastavovani argumentu: $($_.Exception.Message)" "Red"
            # Pokracujeme i pri chybe nastaveni argumentu
        }
        
        # Nastaveni systemove promenne PATH pro spravnou cestu k WebDriveru
        $oldPath = $env:PATH
        $env:PATH = "$($driverPath);$($env:PATH)"
        
        # Vytvoreni instance prohlizece primo, bez EdgeDriverService
        Write-ColorLog "Vytvarim instanci EdgeDriver s cestou v PATH: $($driverPath)" "Yellow"

        # Nastaveni cesty Selenium Driveru
        $msedgedriverPath = "$($driverPath)\msedgedriver.exe"

        # Oprava - Pouziti EdgeDriverService s rucne nastavenou cestou
        $edgeService = [OpenQA.Selenium.Edge.EdgeDriverService]::CreateDefaultService([System.IO.Path]::GetDirectoryName($msedgedriverPath), "msedgedriver.exe")
        $edgeService.HideCommandPromptWindow = $true  # Skryti CMD okna WebDriveru

        # Vytvoreni instance prohlizece s opravenou cestou k WebDriveru
        $driver = New-Object OpenQA.Selenium.Edge.EdgeDriver($edgeService, $edgeOptions)
                
        if ($driver -eq $null) {
            $env:PATH = $oldPath  # Obnoveni puvodni PATH v pripade selhani
            throw "Nepodarilo se vytvorit instanci EdgeDriver"
        }

        Write-ColorLog "EdgeDriver uspesne vytvoren, nastavuji timeouty a okno..." "Green"
        $driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds(10)
        
        # Maximalizace okna
        $driver.Manage().Window.Maximize()

        # Obnoveni puvodni PATH
        $env:PATH = $oldPath
        
        Write-ColorLog "Prohlizec uspesne inicializovan." "Green"
        return $driver
    } catch {
        Write-ColorLog "Chyba pri inicializaci prohlizece: $($_.Exception.Message)" "Red"
        Write-ColorLog "Stack trace: $($_.Exception.StackTrace)" "Red"
        
        # Pokusime se zjistit vice informaci o dostupnem WebDriveru
        $possibleDrivers = Get-ChildItem -Path "$($env:USERPROFILE)\EdgeWebDriver" -Filter *.exe -ErrorAction SilentlyContinue
        if ($possibleDrivers) {
            Write-ColorLog "Nalezene soubory WebDriveru:" "Yellow"
            foreach ($driver in $possibleDrivers) {
                Write-ColorLog "  - $($driver.FullName)" "Yellow"
            }
        } else {
            Write-ColorLog "Zadne soubory WebDriveru nebyly nalezeny v adresari $($env:USERPROFILE)\EdgeWebDriver" "Yellow"
        }
        
        exit 1
    }
}

# Funkce pro prihlaseni do LinkedIn
function Login-LinkedIn {
    param (
        [Parameter(Mandatory = $true)]
        $Driver,
        
        [Parameter(Mandatory = $true)]
        [bool]$ManualLogin
    )
    
    Write-ColorLog "Prihlasovani do LinkedIn..." "Cyan"
    
    try {
        $Driver.Navigate().GoToUrl("https://www.linkedin.com/login")
        
        if ($ManualLogin) {
            Write-ColorLog "Rezim manualniho prihlaseni. Prosim, prihlaste se do LinkedIn..." "Yellow"
            Write-ColorLog "Cekam na dokonceni prihlaseni (max. 2 minuty)..." "Yellow"
            
            # Cekani na dokonceni prihlaseni (kontrola, zda jsme na homepage)
            $timeout = 120 # sekundy
            $start = Get-Date
            $loggedIn = $false
            
            while (((Get-Date) - $start).TotalSeconds -lt $timeout) {
                if ($Driver.Url -like "*linkedin.com/feed*" -or $Driver.Url -like "*linkedin.com/home*") {
                    $loggedIn = $true
                    break
                }
                Start-Sleep -Seconds 1
            }
            
            if ($loggedIn) {
                Write-ColorLog "Prihlaseni uspesne!" "Green"
            } else {
                Write-ColorLog "Cas pro manualni prihlaseni vyprsel. Ukoncuji..." "Red"
                $Driver.Quit()
                exit 1
            }
        } else {
            Write-ColorLog "Automaticke prihlaseni neni implementovano, pouzijte parametr -ManualLogin" "Red"
            $Driver.Quit()
            exit 1
        }
    } catch {
        Write-ColorLog "Chyba pri prihlaseni do LinkedIn: $($_.Exception.Message)" "Red"
        $Driver.Quit()
        exit 1
    }
}

# Funkce pro ziskani poctu stranek s vysledky
function Get-TotalPages {
    param (
        [Parameter(Mandatory = $true)]
        $Driver
    )
    
    Write-ColorLog "Zjistovani celkoveho poctu stranek s vysledky..." "Cyan"
    
    try {
        # Cekani na nacteni strankovani
        Start-Sleep -Seconds 10
        
        # Hledani posledniho tlacitka strankovani
        $paginationButtons = $Driver.FindElements([OpenQA.Selenium.By]::XPath("//button[contains(@aria-label, 'Str�nka �.')]"))
        
        Write-ColorLog "Nalezeno celkem $($paginationButtons.count) tlacitek." "Green"

        if ($paginationButtons.Count -gt 0) {
            # Ziskani cisla stranky z posledniho tlacitka
            $lastButton = $paginationButtons[$paginationButtons.Count - 1]
            $lastPageNumber = [int]$lastButton.Text
            
            Write-ColorLog "Nalezeno celkem $lastPageNumber stranek s vysledky." "Green"
            return $lastPageNumber
        } else {
            # Pokud neni nalezeno strankovani, predpokladame 1 stranku
            Write-ColorLog "Nenalezeno strankovani, predpokladam 1 stranku s vysledky." "Yellow"
            return 1
        }
    } catch {
        Write-ColorLog "Chyba pri zjistovani poctu stranek: $($_.Exception.Message)" "Red"
        return 1
    }
}

# Funkce pro extrakci osob ze vsech stranek
function Extract-People {
    param (
        [Parameter(Mandatory = $true)]
        $Driver,
        
        [Parameter(Mandatory = $true)]
        [string]$CompanyId,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFolder
    )

    Write-ColorLog "Zacinam extrakci osob pro spolecnost s ID: $($CompanyId)" "Cyan"
    
    try {
        $baseUrl = "https://www.linkedin.com/search/results/people/?currentCompany=%5B%22$CompanyId%22%5D&origin=COMPANY_PAGE_CANNED_SEARCH"
        $Driver.Navigate().GoToUrl($baseUrl)
        
        # Cekani na nacteni stranky
        Start-Sleep -Seconds 10
        
        # Zjisteni celkoveho poctu stranek
        $totalPages = Get-TotalPages -Driver $Driver
        
        # Seznam pro ulozeni vsech osob
        $people = @()

        # Inicializujeme prazdne pole pro vysledky
        $peopleData = @()
        
        # Prochazeni vsech stranek
        for ($page = 1; $page -le $totalPages; $page++) {
            Write-ColorLog "Zpracovavam stranku $page z $totalPages..." "Cyan"
            
            if ($page -gt 1) {
                # Prechod na dalsi stranku
                $pageUrl = "$baseUrl&page=$page"
                $Driver.Navigate().GoToUrl($pageUrl)
                Start-Sleep -Seconds 10
            }
            
            # Najdeme vsechny osoby na strance pomoci spravneho XPath
            $nameElement = ($Driver.FindElements([OpenQA.Selenium.By]::XPath(".//span[@dir='ltr']/span[@aria-hidden='true']"))).Text
            Write-ColorLog "Nalezeno $($nameElement.count) osob na strance $page" "Green"
            
            # najdeme vsechny pozice
            $positionElement = ($Driver.FindElements([OpenQA.Selenium.By]::XPath("//div[contains(@class, 'search-results-container')]//div[contains(@class, 't-14') and contains(@class, 't-black') and contains(@class, 't-normal')]"))).Text
            Write-ColorLog "Nalezeno pro $($nameElement.count) osob na strance $page celkem $($positionElement.count) pozic" "Green"

            # najdeme vsechny country
            $countryElement = ($Driver.FindElements([OpenQA.Selenium.By]::XPath("//div[contains(@class, 'search-results-container')]//div[contains(@class, 't-14') and contains(@class, 't-normal') and not(contains(@class, 't-black'))]"))).Text
            Write-ColorLog "Nalezeno pro $($nameElement.count) osob na strance $page celkem $($countryElement.count) lokaci" "Green"

            # najdeme vsechny url profilu
            $urlElement = ($Driver.FindElements([OpenQA.Selenium.By]::XPath("//div[contains(@class, 'search-results-container')]//div[contains(@class, 'display-flex') and contains(@class, 'align-items-center')]//a[contains(@class, 'scale-down')]"))).GetAttribute("href")
            Write-ColorLog "Nalezeno pro $($nameElement.count) osob na strance $page celkem $($countryElement.count) url profilu" "Green"
            
            # Najdeme vsechny "ivm-image-view-model" kontejnery (zajistime spravne poradi)
            $imageContainers = $Driver.FindElements([OpenQA.Selenium.By]::XPath("//div[contains(@class, 'search-results-container')]//a[contains(@class, 'scale-down')]//div[contains(@class, 'ivm-image-view-model')]"))
            Write-ColorLog "Nalezeno $($imageContainers.Count) obrazovych kontejneru." "Green"
            
            # Extrakce obrazku
            $pictureElement = @()

            # Iterujeme pres kazdy nalezeny div a hledame v nem bud obrazek, nebo placeholder
            foreach ($container in $imageContainers) {
                try {
                    # Pokusime se najit IMG uvnitr aktualniho divu
                    try {
                        $imageElement = $container.FindElement([OpenQA.Selenium.By]::XPath(".//img[starts-with(@src, 'https://media.licdn.com/dms/image')]"))
                        $imageURL = $imageElement.GetAttribute("src")
                        $pictureElement += $imageURL
                    } catch {
                        # Pokud IMG neexistuje, hledame placeholder
                        $placeholderElement = $container.FindElement([OpenQA.Selenium.By]::XPath(".//div[contains(@class, 'EntityPhoto-circle-3-ghost-person')]/div[contains(@class, 'visually-hidden')]"))
                        $imageURL = "Zadny obrazek (placeholder: " + $placeholderElement.GetAttribute("innerText") + ")"
                        $pictureElement += $imageURL
                    }
                } catch {
                    # ochrana jen pred rozpadem pozice na strance
                    $imageURL = "Error neplatny element v obrazku."
                    $pictureElement += $imageURL
                    Write-ColorLog "Chyba pri extrakci obrazku: $($_.Exception.Message)" "Red"
                }
            }
            Write-ColorLog "Pocet nalezenych obrazku na strance je $($pictureElement.count)" "Green"
            
            # Zjistime maximalni pocet zaznamu (mely by byt stejne)
            $recordCount = ($nameElement.Count, $positionElement.Count, $countryElement.Count, $urlElement.Count, $pictureElement.Count | Measure-Object -Maximum).Maximum
            Write-ColorLog "Maximalni pocet zaznamu na strance je $($recordCount)" "Green"

            # Iterujeme pres vsechny indexy a vytvarime objekt pro kazdou osobu
            for ($i = 0; $i -lt $recordCount; $i++) {
                # Vytvorime objekt s vlastnostmi
                $person = [PSCustomObject]@{
                    Name       = if ($i -lt $nameElement.Count) { $nameElement[$i] } else { "Nezname jmeno" }
                    Position   = if ($i -lt $positionElement.Count) { $positionElement[$i] } else { "Neznama pozice" }
                    Country    = if ($i -lt $countryElement.Count) { $countryElement[$i] } else { "Neznama lokalita" }
                    ProfileURL = if ($i -lt $urlElement.Count) { $urlElement[$i] } else { "Neznamy odkaz" }
                    Picture    = if ($i -lt $pictureElement.Count) { $pictureElement[$i] } else { "Zadny obrazek" }
                }

                # Pridame objekt do seznamu
                $peopleData += $person
            }            

            # Kratke cekani mezi strankami
            Start-Sleep -Seconds 2
        }
        
        Write-ColorLog "Extrakce dokoncena. Celkem extrahovano $($peopleData.Count) osob." "Green"
        return $peopleData
    } catch {
        Write-ColorLog "Chyba pri extrakci osob: $($_.Exception.Message)" "Red"
        return @()
    }
}

# Funkce pro ulozeni dat do souboru
function Save-PeopleData {
    param (
        [Parameter(Mandatory = $true)]
        $People,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFolder,
        
        [Parameter(Mandatory = $true)]
        [string]$CompanyId,

        [Parameter(Mandatory = $true)]
        [string]$ImageFolder
    )
    
    Write-ColorLog "Ukladani dat do souboru..." "Cyan"
    
    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $jsonFile = Join-Path -Path $OutputFolder -ChildPath "linkedin_people_$($CompanyId)_$($timestamp).json"
        $csvFile = Join-Path -Path $OutputFolder -ChildPath "linkedin_people_$($CompanyId)_$($timestamp).csv"
        
        # Ulozeni do JSON
        $People | ConvertTo-Json -Depth 4 | Out-File $jsonFile -Encoding UTF8
        Write-ColorLog "Data ulozena do JSON souboru: $($jsonFile)" "Green"
        
        # Ulozeni do CSV
        $People | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
        Write-ColorLog "Data ulozena do CSV souboru: $($csvFile)" "Green"
        
        # Ulozeni obrazku
        foreach($PeopleImage in $People){
            $imageURL = $PeopleImage.Picture
            $imageName = $PeopleImage.Name -replace "[^a-zA-Z0-9]", ""
            $imagePath = Join-Path -Path $imagesFolder -ChildPath "$($imageName).jpg"
            
            if ($imageURL -like "http*") {
                $imageBytes = Invoke-WebRequest -Uri $imageURL -UseBasicParsing -OutFile $imagePath
                Write-ColorLog "Obrazek ulozen: $($imagePath)" "Green"
            } else {
                Write-ColorLog "Obrazek nenalezen pro: $($PeopleImage.Name)" "Yellow"
            }
        }

        return @{
            JsonFile = $jsonFile
            CsvFile = $csvFile
        }
    } catch {
        Write-ColorLog "Chyba pri ukladani dat: $($_.Exception.Message)" "Red"
        return $null
    }
}

# Funkce pro zajisteni spravneho kodovani vystupu
function Set-OutputEncoding {
    try {
        # Nastavime vychozi vystupni kodovani konzole
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

        Write-ColorLog "Kodovani vystupu nastaveno na UTF-8" "Green"
    } catch {
        Write-ColorLog "Chyba pri nastavovani kodovani: $($_.Exception.Message)" "Red"
    }
}


# Hlavni funkce
function Start-LinkedInScraper {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CompanyId,
        
        [Parameter(Mandatory = $false)]
        [bool]$ManualLogin = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$Visible = $false
    )
    
    #$CompanyId = "20120844"
    # Nastaveni spravneho kodovani vystupu
    Set-OutputEncoding
    
    Write-ColorLog "===============================================" "Magenta"
    Write-ColorLog "      LinkedIn People Scraper - Start         " "Magenta"
    Write-ColorLog "===============================================" "Magenta"
    Write-ColorLog "Spolecnost ID: $($CompanyId)" "Magenta"
    Write-ColorLog "Manualni prihlaseni: $($ManualLogin)" "Magenta"
    Write-ColorLog "Viditelny prohlizec: $($Visible)" "Magenta"
    Write-ColorLog "===============================================" "Magenta"
    
    # Vytvoreni vystupniho adresare
    $outputFolder = Join-Path -Path $PWD -ChildPath "LinkedInData_$($CompanyId)"
    $imagesFolder = Join-Path -Path $outputFolder -ChildPath "images"
    
    if (-not (Test-Path $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Test-Path $imagesFolder)) {
        New-Item -Path $imagesFolder -ItemType Directory -Force | Out-Null
    }
    
    Write-ColorLog "Vystupni adresar: $($outputFolder)" "Magenta"
    
    # Instalace pozadovanych modulu
    Install-RequiredModules


    
    # Inicializace prohlizece
    $driver = Initialize-Browser -Visible $Visible
    
    try {
        # Prihlaseni do LinkedIn
        Login-LinkedIn -Driver $driver -ManualLogin $ManualLogin
        
        # Extrakce osob
        $people = Extract-People -Driver $driver -CompanyId $CompanyId -OutputFolder $outputFolder

        # Ulozeni dat
        if ($people.Count -gt 0) {
            $files = Save-PeopleData -People $people -OutputFolder $outputFolder -CompanyId $CompanyId -ImageFolder $imagesFolder
            
            Write-ColorLog "===============================================" "Magenta"
            Write-ColorLog "      LinkedIn People Scraper - Vysledek      " "Magenta"
            Write-ColorLog "===============================================" "Magenta"
            Write-ColorLog "Celkem extrahovano osob: $($people.Count)" "Magenta"
            if ($files -ne $null) {
                Write-ColorLog "JSON soubor: $($files.JsonFile)" "Magenta"
                Write-ColorLog "CSV soubor: $($files.CsvFile)" "Magenta"
            }
            Write-ColorLog "Adresar s obrazky: $($imagesFolder)" "Magenta"
            Write-ColorLog "===============================================" "Magenta"
        } else {
            Write-ColorLog "Nebyla nalezena zadna data k ulozeni." "Yellow"
        }
    } catch {
        Write-ColorLog "Necekana chyba pri behu scraperu: $($_.Exception.Message)" "Red"
    } finally {
        # Ukonceni prohlizece
        Write-ColorLog "Ukoncovani prohlizece..." "Cyan"
        $choice = Read-Host "Ukoncit webovy driver pro Selenium? (ano/ne)"

        # Normalizace vstupu (konverze na malá písmena pro lepší rozpoznání)
        $choice = $choice.ToLower()

        if ($choice -eq "ano" -or $choice -eq "a" -or $choice -eq "yes" -or $choice -eq "y") {
            $driver.Quit()
            Write-ColorLog "Prohlizec ukoncen." "Green"
        } elseif ($choice -eq "ne" -or $choice -eq "n" -or $choice -eq "no") {
            Write-ColorLog "Prohlizec ponechan bezici." "Yellow"
        } else {
            Write-ColorLog "Neplatna odpoved, ocekavano 'ano' nebo 'ne'." "Red"
        }
    }
    Write-ColorLog "Scraper dokoncil praci." "Magenta"
}

# Spusteni hlavni funkce
Start-LinkedInScraper -CompanyId $CompanyId -ManualLogin $ManualLogin.IsPresent -Visible $Visible.IsPresent