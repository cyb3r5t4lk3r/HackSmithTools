# SourceMapExtractor

## Popis

Tento nástroj slouží k automatizované detekci a extrakci JavaScript source map (`.map`) souborů z webových aplikací.

Primárním cílem je:
- identifikace veřejně dostupných source map
- extrakce původního zdrojového kódu (`sourcesContent`)
- rekonstrukce původní adresářové struktury aplikace
- analýza JavaScriptu napříč celým webem včetně CDN a externích zdrojů

---

## Jak to funguje

### 1. Crawling webu
- rekurzivně prochází web (v rámci stejného originu)
- sbírá HTML stránky a odkazy
- extrahuje `<script src="...">`

### 2. Analýza JavaScriptu
- hledá `sourceMappingURL`
- kontroluje HTTP header `SourceMap`
- fallback: zkouší `.js.map`

### 3. Multi-origin analýza (novinka)
- detekuje JS z CDN a externích domén
- analyzuje jejich `.map` bez crawlování cizích webů

---

## Instalace

### Vytvoření virtuálního prostředí

```bash
python3 -m venv venv
```

### Aktivace

Linux / macOS:
```bash
source venv/bin/activate
```

Windows:
```bash
venv\Scripts\activate
```

### Instalace závislostí

```bash
pip install requests beautifulsoup4 tldextract
```

---

## Použití

Základní:

```bash
python3 sourcemap_site_crawler_v4.py https://reactjs.org --json report.json
```

---

## Extrakce zdrojového kódu

```bash
python3 sourcemap_site_crawler_v4.py https://reactjs.org --extract ./sources --json report.json
```

---

## CDN a externí skripty

Automaticky:

```bash
--include-related-script-origins
```

Příklad:

```bash
python3 sourcemap_site_crawler_v4.py https://reactjs.org \
  --include-related-script-origins \
  --extract ./sources
```

---

## Omezení domén

```bash
--allowed-origin cdnjs.cloudflare.com
--allowed-origin "*.examplecdn.com"
```

---

## Výstup

### JSON

```json
{
  "pages": [...],
  "results": [...],
  "related_script_origins_discovered": {}
}
```

### Zdrojový kód

```
sources/
└── webpack/
    └── src/
```

---

## Režimy extrakce

Default:
```bash
--extract-layout source-tree
```

Alternativa:
```bash
--extract-layout per-map
```

---

## Bezpečnostní význam

Nástroj umožňuje odhalit:
- nechráněné source mapy
- interní logiku aplikace
- API endpointy
- debug informace

---

## Doporučení

- používej pouze s oprávněním
- vhodné pro ASM / OSINT / pentest

---

## Shrnutí

- rekurzivní crawling
- detekce sourcemap
- podpora CDN
- extrakce zdrojáků
