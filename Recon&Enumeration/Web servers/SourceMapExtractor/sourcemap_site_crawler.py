#!/usr/bin/env python3
"""
Recursive sourcemap audit helper for an authorized website.

What it does:
  - crawls same-origin HTML pages from a start URL
  - discovers script src="..." references on every visited page
  - resolves absolute and relative URLs correctly
  - deduplicates JavaScript URLs across the whole site
  - detects sourcemaps by SourceMap/X-SourceMap headers, sourceMappingURL comments,
    and the common .js.map fallback
  - optionally extracts embedded sourcesContent from found sourcemaps

Usage:
  python3 sourcemap_site_crawler.py https://example.com --max-pages 200 --json report.json
  python3 sourcemap_site_crawler.py https://example.com --max-depth 5 --extract ./sources --json report.json

Use only against systems where you have authorization.
"""

from __future__ import annotations

import argparse
import base64
import collections
import hashlib
import json
import os
import re
import sys
import time
from dataclasses import asdict, dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from typing import NamedTuple
from urllib.error import HTTPError, URLError
from urllib.parse import urldefrag, urljoin, urlparse, urlunparse
from urllib.request import Request, urlopen

SOURCE_MAPPING_RE = re.compile(r"(?://[#@]\s*sourceMappingURL=([^\s*]+)|/\*[#@]\s*sourceMappingURL=([^*]+)\*/)")
JS_PATH_RE = re.compile(r"\.m?js$", re.IGNORECASE)
HTML_CT_RE = re.compile(r"\b(text/html|application/xhtml\+xml)\b", re.IGNORECASE)
SKIP_EXT_RE = re.compile(
    r"\.(?:css|png|jpe?g|gif|svg|webp|ico|pdf|zip|rar|7z|gz|tgz|mp4|mp3|avi|mov|woff2?|ttf|eot)(?:[?#].*)?$",
    re.IGNORECASE,
)


class Response(NamedTuple):
    url: str
    status: int
    headers: dict[str, str]
    body: bytes

    @property
    def text(self) -> str:
        charset = "utf-8"
        ctype = self.headers.get("content-type", "")
        m = re.search(r"charset=([^;]+)", ctype, re.I)
        if m:
            charset = m.group(1).strip()
        return self.body.decode(charset, errors="replace")


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.scripts: list[str] = []
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr = {k.lower(): v for k, v in attrs if k}
        tag_l = tag.lower()
        if tag_l == "script":
            src = attr.get("src")
            if src:
                self.scripts.append(src)
            return
        if tag_l in {"a", "area"}:
            href = attr.get("href")
            if href:
                self.links.append(href)
            return
        # Some SPAs preload chunks this way.
        if tag_l == "link":
            rel = (attr.get("rel") or "").lower()
            href = attr.get("href")
            as_attr = (attr.get("as") or "").lower()
            if href and ("modulepreload" in rel or as_attr == "script"):
                self.scripts.append(href)


@dataclass
class PageResult:
    url: str
    status: int | None
    scripts_found: int = 0
    links_found: int = 0
    note: str | None = None


@dataclass
class MapResult:
    js_url: str
    discovered_on_pages: list[str] = field(default_factory=list)
    status: str = "not_checked"
    map_url: str | None = None
    map_status_code: int | None = None
    map_bytes: int | None = None
    map_sha256: str | None = None
    version: int | None = None
    file: str | None = None
    source_root: str | None = None
    sources_count: int = 0
    sources_content_count: int = 0
    has_embedded_sources: bool = False
    sample_sources: list[str] = field(default_factory=list)
    note: str | None = None


def normalize_url(url: str) -> str:
    url, _frag = urldefrag(url)
    p = urlparse(url)
    scheme = p.scheme.lower()
    netloc = p.netloc.lower()
    # Keep query because hashed assets and routed pages may use it, but normalize empty path.
    path = p.path or "/"
    return urlunparse((scheme, netloc, path, "", p.query, ""))


def fetch(url: str, timeout: int, accept: str = "*/*") -> Response:
    req = Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 sourcemap-site-crawler/1.0 (+authorized-security-testing)",
            "Accept": accept,
        },
        method="GET",
    )
    try:
        with urlopen(req, timeout=timeout) as r:
            headers = {k.lower(): v for k, v in r.headers.items()}
            return Response(r.geturl(), int(getattr(r, "status", 200)), headers, r.read())
    except HTTPError as e:
        headers = {k.lower(): v for k, v in e.headers.items()}
        return Response(e.geturl(), e.code, headers, e.read())


def same_origin(base: str, candidate: str) -> bool:
    b = urlparse(base)
    c = urlparse(candidate)
    return (b.scheme, b.netloc) == (c.scheme, c.netloc)


def allowed_page_url(start_url: str, candidate: str, same_origin_only: bool) -> bool:
    p = urlparse(candidate)
    if p.scheme not in {"http", "https"}:
        return False
    if same_origin_only and not same_origin(start_url, candidate):
        return False
    if SKIP_EXT_RE.search(p.path):
        return False
    return True


def looks_like_js(url: str) -> bool:
    p = urlparse(url)
    return bool(JS_PATH_RE.search(p.path))


def extract_mapping_url(js_text: str) -> str | None:
    matches = list(SOURCE_MAPPING_RE.finditer(js_text))
    if not matches:
        return None
    raw = (matches[-1].group(1) or matches[-1].group(2) or "").strip()
    return raw or None


def candidate_map_urls(js_resp: Response, js_text: str) -> list[str]:
    candidates: list[str] = []
    for header in ("sourcemap", "x-sourcemap"):
        value = js_resp.headers.get(header)
        if value:
            candidates.append(urljoin(js_resp.url, value.strip()))
    comment_url = extract_mapping_url(js_text)
    if comment_url:
        candidates.append(comment_url if comment_url.startswith("data:") else urljoin(js_resp.url, comment_url))
    fallback = js_resp.url.split("#", 1)[0].split("?", 1)[0] + ".map"
    candidates.append(fallback)

    out: list[str] = []
    seen: set[str] = set()
    for c in candidates:
        key = c if c.startswith("data:") else normalize_url(c)
        if key not in seen:
            out.append(c)
            seen.add(key)
    return out


def parse_map_payload(map_url: str, content: bytes) -> tuple[dict, MapResult]:
    sha = hashlib.sha256(content).hexdigest()
    data = json.loads(content.decode("utf-8", errors="replace"))
    sources = data.get("sources") or []
    sources_content = data.get("sourcesContent") or []
    result = MapResult(
        js_url="",
        status="found",
        map_url=map_url,
        map_bytes=len(content),
        map_sha256=sha,
        version=data.get("version"),
        file=data.get("file"),
        source_root=data.get("sourceRoot"),
        sources_count=len(sources),
        sources_content_count=sum(1 for item in sources_content if item is not None),
        has_embedded_sources=any(item is not None for item in sources_content),
        sample_sources=[str(x) for x in sources[:15]],
    )
    return data, result


def parse_data_sourcemap(data_url: str) -> bytes | None:
    # Handles: data:application/json;charset=utf-8;base64,....
    if not data_url.startswith("data:") or "," not in data_url:
        return None
    meta, payload = data_url.split(",", 1)
    if ";base64" in meta.lower():
        return base64.b64decode(payload)
    from urllib.parse import unquote_to_bytes
    return unquote_to_bytes(payload)


def safe_source_path(base_dir: Path, source_name: str) -> Path:
    cleaned = source_name.replace("webpack://", "webpack/").replace("..", "__")
    cleaned = cleaned.lstrip("/\\")
    cleaned = re.sub(r"[<>:\"|?*]", "_", cleaned)
    path = (base_dir / cleaned).resolve()
    if not str(path).startswith(str(base_dir.resolve())):
        digest = hashlib.sha256(source_name.encode()).hexdigest()[:16]
        path = base_dir / f"unsafe_path_{digest}.txt"
    return path


def extract_sources(map_data: dict, output_dir: Path) -> int:
    sources = map_data.get("sources") or []
    sources_content = map_data.get("sourcesContent") or []
    count = 0
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, content in zip(sources, sources_content):
        if content is None:
            continue
        path = safe_source_path(output_dir, str(name))
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(str(content), encoding="utf-8", errors="replace")
        count += 1
    return count


def audit_js(js_url: str, pages: list[str], timeout: int, delay: float, extract_dir: Path | None) -> MapResult:
    try:
        time.sleep(delay)
        js_resp = fetch(js_url, timeout, accept="application/javascript,text/javascript,*/*")
    except Exception as e:
        return MapResult(js_url=js_url, discovered_on_pages=pages, status="js_fetch_error", note=str(e))

    if js_resp.status >= 400:
        return MapResult(js_url=js_url, discovered_on_pages=pages, status="js_http_error", note=f"HTTP {js_resp.status}")

    js_text = js_resp.text
    candidates = candidate_map_urls(js_resp, js_text)
    tried: list[str] = []

    for map_url in candidates:
        try:
            if map_url.startswith("data:"):
                payload = parse_data_sourcemap(map_url)
                if payload is None:
                    tried.append("inline data sourcemap -> could not decode")
                    continue
                map_data, result = parse_map_payload("data:", payload)
                result.js_url = js_url
                result.discovered_on_pages = pages
                result.note = "Inline data sourcemap decoded."
            else:
                time.sleep(delay)
                mr = fetch(map_url, timeout, accept="application/json,text/plain,*/*")
                tried.append(f"{map_url} -> HTTP {mr.status}")
                if mr.status != 200:
                    continue
                map_data, result = parse_map_payload(map_url, mr.body)
                result.js_url = js_url
                result.discovered_on_pages = pages
                result.map_status_code = mr.status

            if extract_dir and result.has_embedded_sources:
                subdir = extract_dir / hashlib.sha256(js_url.encode()).hexdigest()[:12]
                written = extract_sources(map_data, subdir)
                extra = f"Extracted {written} embedded source files to {subdir}"
                result.note = f"{result.note} {extra}" if result.note else extra
            return result
        except json.JSONDecodeError:
            tried.append(f"{map_url} -> not valid JSON")
        except Exception as e:
            tried.append(f"{map_url} -> error: {e}")

    return MapResult(js_url=js_url, discovered_on_pages=pages, status="not_found", note="; ".join(tried[:12]))


def crawl_site(start_url: str, max_pages: int, max_depth: int, timeout: int, delay: float, all_origins: bool) -> tuple[list[PageResult], dict[str, set[str]]]:
    start_url = normalize_url(start_url)
    same_origin_only = not all_origins
    queue: collections.deque[tuple[str, int]] = collections.deque([(start_url, 0)])
    visited: set[str] = set()
    page_results: list[PageResult] = []
    js_to_pages: dict[str, set[str]] = collections.defaultdict(set)

    while queue and len(visited) < max_pages:
        page_url, depth = queue.popleft()
        page_url = normalize_url(page_url)
        if page_url in visited or depth > max_depth:
            continue
        visited.add(page_url)

        try:
            time.sleep(delay)
            resp = fetch(page_url, timeout, accept="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            ctype = resp.headers.get("content-type", "")
            if resp.status >= 400:
                page_results.append(PageResult(page_url, resp.status, note=f"HTTP {resp.status}"))
                continue
            if not HTML_CT_RE.search(ctype):
                page_results.append(PageResult(page_url, resp.status, note=f"Skipped non-HTML content-type: {ctype}"))
                continue

            parser = PageParser()
            parser.feed(resp.text)
            resolved_page_url = normalize_url(resp.url)

            for src in parser.scripts:
                absolute = normalize_url(urljoin(resolved_page_url, src))
                if same_origin_only and not same_origin(start_url, absolute):
                    continue
                if looks_like_js(absolute):
                    js_to_pages[absolute].add(resolved_page_url)

            for href in parser.links:
                absolute = normalize_url(urljoin(resolved_page_url, href))
                if not allowed_page_url(start_url, absolute, same_origin_only=same_origin_only):
                    continue
                if absolute not in visited and depth + 1 <= max_depth:
                    queue.append((absolute, depth + 1))

            page_results.append(PageResult(resolved_page_url, resp.status, len(parser.scripts), len(parser.links)))
        except Exception as e:
            page_results.append(PageResult(page_url, None, note=str(e)))

    return page_results, js_to_pages


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Recursively discover JavaScript sourcemaps for an authorized website.")
    ap.add_argument("url", help="Start URL")
    ap.add_argument("--timeout", type=int, default=15)
    ap.add_argument("--delay", type=float, default=0.15, help="Delay between HTTP requests in seconds")
    ap.add_argument("--max-pages", type=int, default=200, help="Maximum HTML pages to crawl")
    ap.add_argument("--max-depth", type=int, default=5, help="Maximum link depth from start URL")
    ap.add_argument("--all-origins", action="store_true", help="Also crawl/check third-party origins. Usually not recommended.")
    ap.add_argument("--json", dest="json_path", help="Write JSON report")
    ap.add_argument("--extract", help="Directory for extracting embedded sourcesContent. Use only when authorized.")
    args = ap.parse_args(argv)

    extract_dir = Path(args.extract) if args.extract else None
    pages, js_to_pages = crawl_site(args.url, args.max_pages, args.max_depth, args.timeout, args.delay, args.all_origins)

    results: list[MapResult] = []
    for js_url in sorted(js_to_pages):
        pages_for_js = sorted(js_to_pages[js_url])[:25]
        results.append(audit_js(js_url, pages_for_js, args.timeout, args.delay, extract_dir))

    report = {
        "target": args.url,
        "crawl": {
            "pages_visited": len(pages),
            "max_pages": args.max_pages,
            "max_depth": args.max_depth,
            "same_origin_only": not args.all_origins,
        },
        "javascript_files_discovered": len(js_to_pages),
        "sourcemaps_found": sum(1 for r in results if r.status == "found"),
        "sourcemaps_with_embedded_sources": sum(1 for r in results if r.has_embedded_sources),
        "pages": [asdict(p) for p in pages],
        "results": [asdict(r) for r in results],
    }

    print(json.dumps(report, indent=2, ensure_ascii=False))
    if args.json_path:
        Path(args.json_path).write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
