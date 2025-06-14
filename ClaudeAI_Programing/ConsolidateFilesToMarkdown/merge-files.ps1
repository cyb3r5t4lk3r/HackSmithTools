<#
.SYNOPSIS
    Skript pro rekurzivní sloučení vybraných souborů ze zadané složky do jednoho Markdown (.md) souboru.

.DESCRIPTION
    Tento PowerShell skript prochází zadaný adresář (včetně podsložek), vyhledává soubory podle zadaných přípon
    a filtruje je na základě definovaných pravidel (např. vyloučení složek jako node_modules či git).
    Následně vytvoří výstupní Markdown soubor, ve kterém jsou jednotlivé soubory agregovány včetně jejich relativní cesty,
    názvu, a syntax highlightingu pro čitelnější prezentaci. Vhodné například pro kódové review, archivaci nebo sdílení.

.PARAMETER SourcePath
    Cesta ke zdrojové složce, která bude rekurzivně prohledávána.

.PARAMETER OutputFile
    Název výstupního Markdown souboru (výchozí: "merged-files.md").

.PARAMETER IncludeExtensions
    Pole přípon souborů, které budou zahrnuty do výstupu (např. *.ps1, *.cs, *.py).

.PARAMETER ExcludeFolders
    Seznam složek, které budou ignorovány při procházení adresáře.

.PARAMETER ExcludeExtensions
    Seznam přípon, které mají být ze zpracování vyloučeny.

.EXAMPLE
    .\Merge-Files.ps1 -SourcePath "C:\projekty\mojeapp"

    Rekurzivně prohledá složku `C:\projekty\mojeapp`, sloučí všechny výchozí přípony (txt, js, py, ...) a uloží do `merged-files.md`.

.EXAMPLE
    .\Merge-Files.ps1 -SourcePath "./src" -OutputFile "source.md" -ExcludeExtensions ".json",".md"

    Sloučí soubory z "./src", ale vynechá všechny s příponou `.json` a `.md`. Výstupní soubor bude `source.md`.

.NOTES
    Autor: Daniel Hejda (Cyber Rangers s.r.o.)
    Verze: 1.0
    Datum: 2025-06-14
    Požadavky: PowerShell 5.1+ (pro Get-Content -Raw), přístupová práva ke složkám/souborům
#>


param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "merged-files.md",
    
    [Parameter(Mandatory=$false)]
    [string[]]$IncludeExtensions = @("*.txt", "*.cs", "*.js", "*.py", "*.html", "*.css", "*.json", "*.xml", "*.md", "*.sql", "*.ps1", "*.sh",".env"),
    
    [Parameter(Mandatory=$false)]
    [string[]]$ExcludeFolders = @("bin", "obj", "node_modules", ".git", ".vs", "packages"),
    
    [Parameter(Mandatory=$false)]
    [string[]]$ExcludeExtensions = @()
)

# Ověření existence zdrojové složky
if (-not (Test-Path $SourcePath)) {
    Write-Error "Zdrojová složka '$SourcePath' neexistuje."
    exit 1
}

# Získání absolutní cesty
$SourcePath = Resolve-Path $SourcePath

Write-Host "Zpracovávám složku: $SourcePath"
Write-Host "Výstupní soubor: $OutputFile"

# Vytvoření/vymazání výstupního souboru
if (Test-Path $OutputFile) {
    Remove-Item $OutputFile
}

# Přidání hlavičky do Markdown souboru
$header = @"
# Agregace souborů ze složky: $SourcePath

Vygenerováno: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

---

"@

Add-Content -Path $OutputFile -Value $header -Encoding UTF8

# Funkce pro získání relativní cesty
function Get-RelativePath {
    param($BasePath, $FullPath)
    return $FullPath.Substring($BasePath.Length).TrimStart('\')
}

# Získání všech souborů rekurzivně s filtrováním
$allFiles = @()
foreach ($extension in $IncludeExtensions) {
    $files = Get-ChildItem -Path $SourcePath -Filter $extension -Recurse -File
    $allFiles += $files
}

# Filtrování souborů (vyloučení složek a přípon)
$filteredFiles = $allFiles | Where-Object {
    $filePath = $_.FullName
    $fileExtension = $_.Extension.ToLower()
    
    # Kontrola vyloučených složek
    $shouldExcludeFolder = $false
    foreach ($excludeFolder in $ExcludeFolders) {
        if ($filePath -like "*\$excludeFolder\*" -or $filePath -like "*/$excludeFolder/*") {
            $shouldExcludeFolder = $true
            break
        }
    }
    
    # Kontrola vyloučených přípon
    $shouldExcludeExtension = $false
    if ($ExcludeExtensions.Count -gt 0) {
        foreach ($excludeExt in $ExcludeExtensions) {
            $cleanExcludeExt = $excludeExt.TrimStart('*').ToLower()
            if ($fileExtension -eq $cleanExcludeExt) {
                $shouldExcludeExtension = $true
                break
            }
        }
    }
    
    # Zahrnout soubor pouze pokud není vyloučen ani složkou ani příponou
    -not $shouldExcludeFolder -and -not $shouldExcludeExtension
}

Write-Host "Nalezeno $($filteredFiles.Count) souborů k zpracování."

# Zpracování každého souboru
$processedCount = 0
foreach ($file in $filteredFiles) {
    try {
        $processedCount++
        $relativePath = Get-RelativePath -BasePath $SourcePath.Path -FullPath $file.FullName
        
        Write-Progress -Activity "Zpracovávám soubory" -Status "Soubor: $relativePath" -PercentComplete (($processedCount / $filteredFiles.Count) * 100)
        
        # Vytvoření nadpisu z názvu souboru a cesty
        $title = "## $($file.Name) - $relativePath"
        
        # Přidání nadpisu do výstupního souboru
        Add-Content -Path $OutputFile -Value "`n$title`n" -Encoding UTF8
        
        # Určení jazyka pro syntax highlighting na základě přípony
        $extension = $file.Extension.ToLower()
        $language = switch ($extension) {
            ".sh" { "bash" }
            ".cs" { "csharp" }
            ".js" { "javascript" }
            ".py" { "python" }
            ".html" { "html" }
            ".css" { "css" }
            ".json" { "json" }
            ".xml" { "xml" }
            ".md" { "markdown" }
            ".sql" { "sql" }
            ".ps1" { "powershell" }
            ".txt" { "text" }
            ".env" { "dotenv" }
            default { "text" }
        }
        
        # Přidání začátku code bloku
        Add-Content -Path $OutputFile -Value "``````$language" -Encoding UTF8
        
        # Načtení a přidání obsahu souboru
        try {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            if ($content) {
                Add-Content -Path $OutputFile -Value $content -Encoding UTF8 -NoNewline
            } else {
                Add-Content -Path $OutputFile -Value "# Soubor je prázdný nebo nelze načíst obsah" -Encoding UTF8
            }
        }
        catch {
            Add-Content -Path $OutputFile -Value "# Chyba při čtení souboru: $($_.Exception.Message)" -Encoding UTF8
        }
        
        # Přidání konce code bloku
        Add-Content -Path $OutputFile -Value "`n``````" -Encoding UTF8
        
        # Přidání oddělovače
        Add-Content -Path $OutputFile -Value "`n---`n" -Encoding UTF8
        
    }
    catch {
        Write-Warning "Chyba při zpracování souboru '$($file.FullName)': $($_.Exception.Message)"
    }
}

Write-Progress -Activity "Zpracovávám soubory" -Completed

# Přidání statistik na konec
$footer = @"

## Statistiky

- **Celkem zpracováno souborů:** $processedCount
- **Zdrojová složka:** $SourcePath
- **Datum vytvoření:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
- **Zahrnuté přípony:** $($IncludeExtensions -join ", ")
- **Vyloučené složky:** $($ExcludeFolders -join ", ")
- **Vyloučené přípony:** $($ExcludeExtensions -join ", ")

"@

Add-Content -Path $OutputFile -Value $footer -Encoding UTF8

Write-Host "Hotovo! Vytvořen soubor: $OutputFile"
Write-Host "Zpracováno souborů: $processedCount"