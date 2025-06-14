# Merge-Files.ps1 – Skript pro sloučení zdrojových souborů do jednoho Markdown dokumentu

Tento skript rekurzivně prochází zadanou složku a vytvoří **jeden přehledný `.md` soubor**, který obsahuje obsah všech vybraných souborů z projektu. Je určen primárně pro **vývojáře, testery, dokumentátory a analytiky**, kteří potřebují rychlý přehled nad větším množstvím kódu.

## 🎯 Hlavní využití

### Automatická dokumentace
Může sloužit jako nástroj pro generování dokumentace projektů – zvláště užitečné, pokud potřebujete přehled zdrojového kódu ve formátu, který lze snadno sdílet nebo tisknout.

### Integrace s CloudeAI (Anthropic Claude)
Největší přínos je v možnosti využití výstupního `.md` souboru pro **nahrání do CloudeAI** (Claude od společnosti Anthropic). Claude dokáže s tímto konsolidovaným dokumentem interagovat tak, jako by „četl celý váš projekt“.

- Vhodné pro **refaktoring, dokumentaci, bezpečnostní review nebo hledání chyb**.
- Otestováno na projektu s více než **15 000 řádky kódu v 50 souborech** – skript vše úspěšně zpracoval do jednoho přehledného markdown souboru bez ztráty informací.
- Výstup je přehledný, kód je rozdělen podle souborů a zvýrazněn syntaxí.

---

## ✅ Klíčové vlastnosti skriptu

- 📁 **Rekurzivní procházení** – projde všechny podsložky
- 🧹 **Filtrování souborů** – výchozí přípony zahrnují běžné kódové typy (txt, cs, js, py, html, css, json, xml, md, sql, ps1)
- 🚫 **Ignorování složek** – automaticky vyloučí složky jako `bin`, `obj`, `node_modules`, `.git`, atd.
- 💡 **Syntax highlighting** – určuje jazyk pro každý soubor dle přípony (kompatibilní s markdown)
- 🧭 **Relativní cesty** – každý blok začíná názvem souboru a relativní cestou
- 📊 **Progress bar** – zobrazuje stav zpracování
- 🔄 **Odolnost vůči chybám** – chyby u jednotlivých souborů skript přeskakuje, ale pokračuje dál
- 🌍 **UTF-8 podpora** – zachová české znaky i jiné speciální znaky
- 📈 **Statistiky na konci** – celkový počet souborů, přípony, vyloučené složky a datum generování

---

## 🧪 Příklady použití

```powershell
# Vyloučení binárních a konfiguračních souborů
.\merge-files.ps1 -SourcePath "C:\MojeProjekt" -ExcludeExtensions @("*.exe", "*.dll", "*.config", "*.log")

# Kombinace zahrnutí a vyloučení
.\merge-files.ps1 -SourcePath "C:\MojeProjekt" -IncludeExtensions @("*.*") -ExcludeExtensions @("*.exe", "*.dll", "*.bin", "*.obj")

# Vyloučení pouze obrázků a archivů
.\merge-files.ps1 -SourcePath "C:\MojeProjekt" -ExcludeExtensions @("*.jpg", "*.png", "*.gif", "*.zip", "*.rar")
```

---

## 📌 Praktické scénáře

```powershell
# Zahrnout vše kromě binárních souborů
.\merge-files.ps1 -SourcePath "." -IncludeExtensions @("*.*") -ExcludeExtensions @("*.exe", "*.dll", "*.pdb")

# Pouze textové soubory, ale bez logů
.\merge-files.ps1 -SourcePath "." -IncludeExtensions @("*.txt", "*.md") -ExcludeExtensions @("*.log")
```

---

## 🧠 Doporučení pro použití s Claude AI

Po vygenerování Markdown souboru ho jednoduše nahrajte do CloudeAI (Claude od Anthropic) jako **přiložený soubor**. Claude pak:

- analyzuje veškerý kód,
- odpovídá na dotazy v kontextu celého projektu,
- doporučuje optimalizace, bezpečnostní úpravy nebo komentáře ke kódu.

Díky tomu můžete pracovat s celým projektem interaktivně a kontextově.

