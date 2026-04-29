#!/usr/bin/env python3
"""
Recursive sourcemap audit helper for an authorized website.

What it does:
  - crawls same-origin HTML pages from a start URL
  - can also audit related external JS origins such as CDN or tag-manager hosts
  - discovers script src="..." references on every visited page
  - resolves absolute and relative URLs correctly
  - deduplicates JavaScript URLs across the whole site
  - detects sourcemaps by SourceMap/X-SourceMap headers, sourceMappingURL comments,
    and the common .js.map fallback
  - optionally extracts embedded sourcesContent from found sourcemaps while preserving
    the source tree structure from the sourcemap instead of putting everything under
    opaque hash folders

Usage:
  python3 sourcemap_site_crawler_v4.py https://example.com --max-pages 200 --json report.json
  python3 sourcemap_site_crawler_v4.py https://example.com --max-depth 5 --include-related-script-origins --extract ./sources --json report.json
  python3 sourcemap_site_crawler_v4.py https://example.com --extract ./sources --extract-layout per-map

Use only against systems where you have authorization.
"""

from __future__ import annotations

import argparse
import base64
import collections
import hashlib
import json
import re
import sys
import time
from dataclasses import asdict, dataclass, field
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from typing import NamedTuple
from urllib.error import HTTPError
from urllib.parse import unquote, urldefrag, urljoin, urlparse, urlunparse
from urllib.request import Request, urlopen

SOURCE_MAPPING_RE = re.compile(r"(?://[#@]\s*sourceMappingURL=([^\s*]+)|/\*[#@]\s*sourceMappingURL=([^*]+)\*/)")
JS_PATH_RE = re.compile(r"\.m?js$", re.IGNORECASE)
HTML_CT_RE = re.compile(r"\b(text/html|application/xhtml\+xml)\b", re.IGNORECASE)
SKIP_EXT_RE = re.compile(
    r"\.(?:css|png|jpe?g|gif|svg|webp|ico|pdf|zip|rar|7z|gz|tgz|mp4|mp3|avi|mov|woff2?|ttf|eot)(?:[?#].*)?$",
    re.IGNORECASE,
)
WINDOWS_FORBIDDEN_RE = re.compile(r"[<>:\"|?*]")


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
    extracted_files: int = 0
    extract_dir: str | None = None
    note: str | None = None


def normalize_url(url: str) -> str:
    url, _frag = urldefrag(url)
    p = urlparse(url)
    scheme = p.scheme.lower()
    netloc = p.netloc.lower()
    path = p.path or "/"
    return urlunparse((scheme, netloc, path, "", p.query, ""))


def fetch(url: str, timeout: int, accept: str = "*/*") -> Response:
    req = Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 sourcemap-site-crawler/1.2 (+authorized-security-testing)",
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


def origin(url: str) -> str:
    p = urlparse(url)
    return f"{p.scheme.lower()}://{p.netloc.lower()}"


def host_matches_pattern(host: str, pattern: str) -> bool:
    """
    Supports:
      example.com              exact host
      *.example.com            subdomains only
      .example.com             example.com and subdomains
      https://cdn.example.com  exact origin host part is used
    """
    host = host.lower().strip()
    pattern = pattern.lower().strip()
    if not pattern:
        return False
    if "://" in pattern:
        pattern = urlparse(pattern).netloc.lower()
    if pattern.startswith("*."):
        suffix = pattern[1:]  # .example.com
        return host.endswith(suffix) and host != suffix[1:]
    if pattern.startswith("."):
        suffix = pattern[1:]
        return host == suffix or host.endswith(pattern)
    return host == pattern


def allowed_by_patterns(url: str, patterns: list[str]) -> bool:
    if not patterns:
        return False
    host = urlparse(url).netloc.lower()
    return any(host_matches_pattern(host, p) for p in patterns)


def allowed_script_url(
    start_url: str,
    candidate: str,
    include_related_script_origins: bool,
    allowed_origins: list[str],
) -> bool:
    p = urlparse(candidate)
    if p.scheme not in {"http", "https"}:
        return False
    if not looks_like_js(candidate):
        return False
    if same_origin(start_url, candidate):
        return True
    if allowed_by_patterns(candidate, allowed_origins):
        return True
    return include_related_script_origins


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
    if not data_url.startswith("data:") or "," not in data_url:
        return None
    meta, payload = data_url.split(",", 1)
    if ";base64" in meta.lower():
        return base64.b64decode(payload)
    from urllib.parse import unquote_to_bytes

    return unquote_to_bytes(payload)


def map_identity(map_url: str, js_url: str) -> str:
    """Stable readable folder name for optional per-map extraction layout."""
    url = map_url if map_url and map_url != "data:" else js_url
    p = urlparse(url)
    base = PurePosixPath(unquote(p.path)).name or "inline-sourcemap"
    base = base.replace(".js.map", "").replace(".map", "")
    digest = hashlib.sha256(url.encode()).hexdigest()[:10]
    return sanitize_path_part(f"{base}-{digest}")


def sanitize_path_part(part: str) -> str:
    part = unquote(part).strip()
    if part in {"", "."}:
        return "_"
    if part == "..":
        return "__up__"
    return WINDOWS_FORBIDDEN_RE.sub("_", part)


def split_source_path(raw: str) -> list[str]:
    """
    Convert sourcemap source names to a safe relative path while preserving useful structure.

    Examples:
      webpack:///./src/app.js              -> webpack/src/app.js
      webpack://project/./src/app.js      -> webpack/project/src/app.js
      /assets/src/app.js                  -> webroot/assets/src/app.js
      https://host/assets/src/app.js      -> url/host/assets/src/app.js
      ../src/app.js                       -> __up__/src/app.js
      node_modules/pkg/index.js           -> node_modules/pkg/index.js
    """
    s = str(raw or "").replace("\\", "/")
    s = unquote(s)

    # Remove loader prefixes like babel-loader!.../src/app.js and keep the real source path.
    if "!" in s:
        s = s.split("!")[-1]

    parsed = urlparse(s)
    parts: list[str]

    if parsed.scheme in {"http", "https"}:
        parts = ["url", parsed.netloc] + [p for p in parsed.path.split("/") if p]
    elif parsed.scheme == "webpack":
        # urlparse('webpack://project/./src/a.js') => netloc='project', path='/./src/a.js'
        tail = [p for p in parsed.path.split("/") if p]
        parts = ["webpack"]
        if parsed.netloc:
            parts.append(parsed.netloc)
        parts.extend(tail)
    elif parsed.scheme:
        # Unknown virtual scheme, keep it visible but safe.
        parts = [parsed.scheme]
        if parsed.netloc:
            parts.append(parsed.netloc)
        parts.extend([p for p in parsed.path.split("/") if p])
    else:
        if s.startswith("/"):
            parts = ["webroot"] + [p for p in s.split("/") if p]
        else:
            parts = [p for p in s.split("/") if p]

    cleaned: list[str] = []
    for part in parts:
        if part == ".":
            continue
        cleaned.append(sanitize_path_part(part))

    return cleaned or ["unknown-source.txt"]


def source_output_path(base_dir: Path, source_name: str, source_root: str | None = None) -> Path:
    if source_root:
        # sourceRoot can be a virtual root such as webpack:// or a relative prefix.
        root = source_root.replace("\\", "/")
        if root and not root.endswith("/"):
            root += "/"
        combined = root + str(source_name).lstrip("/")
    else:
        combined = str(source_name)

    relative_parts = split_source_path(combined)
    path = (base_dir.joinpath(*relative_parts)).resolve()
    base = base_dir.resolve()
    if not str(path).startswith(str(base)):
        digest = hashlib.sha256(combined.encode()).hexdigest()[:16]
        path = base / f"unsafe_path_{digest}.txt"
    return path


def unique_path(path: Path, content: str, overwrite: bool) -> Path:
    if overwrite or not path.exists():
        return path
    try:
        existing = path.read_text(encoding="utf-8", errors="replace")
        if existing == content:
            return path
    except Exception:
        pass
    digest = hashlib.sha256(content.encode("utf-8", errors="replace")).hexdigest()[:8]
    return path.with_name(f"{path.stem}.{digest}{path.suffix}")


def extract_sources(map_data: dict, output_dir: Path, overwrite: bool = False) -> int:
    sources = map_data.get("sources") or []
    sources_content = map_data.get("sourcesContent") or []
    source_root = map_data.get("sourceRoot")
    count = 0
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, content in zip(sources, sources_content):
        if content is None:
            continue
        content_s = str(content)
        path = source_output_path(output_dir, str(name), source_root=source_root)
        path = unique_path(path, content_s, overwrite=overwrite)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content_s, encoding="utf-8", errors="replace")
        count += 1
    return count


def audit_js(
    js_url: str,
    pages: list[str],
    timeout: int,
    delay: float,
    extract_dir: Path | None,
    extract_layout: str,
    overwrite: bool,
) -> MapResult:
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
                if extract_layout == "per-map":
                    target_dir = extract_dir / map_identity(result.map_url or "data:", js_url)
                else:
                    target_dir = extract_dir
                written = extract_sources(map_data, target_dir, overwrite=overwrite)
                result.extracted_files = written
                result.extract_dir = str(target_dir)
                extra = f"Extracted {written} embedded source files to {target_dir}"
                result.note = f"{result.note} {extra}" if result.note else extra
            return result
        except json.JSONDecodeError:
            tried.append(f"{map_url} -> not valid JSON")
        except Exception as e:
            tried.append(f"{map_url} -> error: {e}")

    return MapResult(js_url=js_url, discovered_on_pages=pages, status="not_found", note="; ".join(tried[:12]))


def crawl_site(
    start_url: str,
    max_pages: int,
    max_depth: int,
    timeout: int,
    delay: float,
    all_origins: bool,
    include_related_script_origins: bool,
    allowed_origins: list[str],
) -> tuple[list[PageResult], dict[str, set[str]], dict[str, set[str]]]:
    """
    Crawl HTML pages and collect JavaScript files.

    Important behavior:
      - HTML crawling is same-origin by default.
      - When --include-related-script-origins is enabled, the crawler still crawls
        same-origin HTML pages, but it also audits external JS files referenced
        by those pages. This matches what DevTools Sources shows for CDN scripts.
      - --all-origins changes HTML crawling too, so use it carefully.
      - --allowed-origin can whitelist selected external hosts/patterns.
    """
    start_url = normalize_url(start_url)
    same_origin_only_for_pages = not all_origins
    queue: collections.deque[tuple[str, int]] = collections.deque([(start_url, 0)])
    visited: set[str] = set()
    page_results: list[PageResult] = []
    js_to_pages: dict[str, set[str]] = collections.defaultdict(set)
    related_script_origins: dict[str, set[str]] = collections.defaultdict(set)

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
                if urlparse(absolute).scheme not in {"http", "https"}:
                    continue
                if looks_like_js(absolute):
                    related_script_origins[origin(absolute)].add(absolute)
                if allowed_script_url(start_url, absolute, include_related_script_origins, allowed_origins):
                    js_to_pages[absolute].add(resolved_page_url)

            for href in parser.links:
                absolute = normalize_url(urljoin(resolved_page_url, href))
                # HTML crawling remains controlled separately from JS auditing.
                if not allowed_page_url(start_url, absolute, same_origin_only=same_origin_only_for_pages):
                    # Optional whitelist for selected related HTML origins.
                    if not (allowed_origins and allowed_by_patterns(absolute, allowed_origins)):
                        continue
                if absolute not in visited and depth + 1 <= max_depth:
                    queue.append((absolute, depth + 1))

            page_results.append(PageResult(resolved_page_url, resp.status, len(parser.scripts), len(parser.links)))
        except Exception as e:
            page_results.append(PageResult(page_url, None, note=str(e)))

    return page_results, js_to_pages, related_script_origins

def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Recursively discover JavaScript sourcemaps for an authorized website.")
    ap.add_argument("url", help="Start URL")
    ap.add_argument("--timeout", type=int, default=15)
    ap.add_argument("--delay", type=float, default=0.15, help="Delay between HTTP requests in seconds")
    ap.add_argument("--max-pages", type=int, default=200, help="Maximum HTML pages to crawl")
    ap.add_argument("--max-depth", type=int, default=5, help="Maximum link depth from start URL")
    ap.add_argument("--all-origins", action="store_true", help="Also crawl third-party HTML pages. Usually not recommended.")
    ap.add_argument(
        "--include-related-script-origins",
        action="store_true",
        help="Audit external JavaScript files referenced by crawled pages, such as CDN and tag-manager scripts, without crawling their HTML pages.",
    )
    ap.add_argument(
        "--allowed-origin",
        action="append",
        default=[],
        help="Allow selected external hosts/origins for JS auditing and optional HTML crawling. Can be repeated. Examples: a.examplecdn.com, *.examplecdn.com, https://cdn.example.com",
    )
    ap.add_argument("--json", dest="json_path", help="Write JSON report")
    ap.add_argument("--extract", help="Directory for extracting embedded sourcesContent. Use only when authorized.")
    ap.add_argument(
        "--extract-layout",
        choices=["source-tree", "per-map"],
        default="source-tree",
        help="source-tree merges all recovered files into the original sourcemap paths. per-map puts each sourcemap into its own readable folder.",
    )
    ap.add_argument("--overwrite", action="store_true", help="Overwrite extracted files if paths collide. By default conflicting files are kept with a short hash suffix.")
    args = ap.parse_args(argv)

    extract_dir = Path(args.extract) if args.extract else None
    pages, js_to_pages, related_script_origins = crawl_site(
        args.url,
        args.max_pages,
        args.max_depth,
        args.timeout,
        args.delay,
        args.all_origins,
        args.include_related_script_origins,
        args.allowed_origin,
    )

    results: list[MapResult] = []
    for js_url in sorted(js_to_pages):
        pages_for_js = sorted(js_to_pages[js_url])[:25]
        results.append(audit_js(js_url, pages_for_js, args.timeout, args.delay, extract_dir, args.extract_layout, args.overwrite))

    report = {
        "target": args.url,
        "crawl": {
            "pages_visited": len(pages),
            "max_pages": args.max_pages,
            "max_depth": args.max_depth,
            "same_origin_only": not args.all_origins,
            "include_related_script_origins": args.include_related_script_origins,
            "allowed_origins": args.allowed_origin,
        },
        "javascript_files_discovered": len(js_to_pages),
        "related_script_origins_discovered": {k: len(v) for k, v in sorted(related_script_origins.items())},
        "sourcemaps_found": sum(1 for r in results if r.status == "found"),
        "sourcemaps_with_embedded_sources": sum(1 for r in results if r.has_embedded_sources),
        "extracted_files": sum(r.extracted_files for r in results),
        "pages": [asdict(p) for p in pages],
        "results": [asdict(r) for r in results],
    }

    print(json.dumps(report, indent=2, ensure_ascii=False))
    if args.json_path:
        Path(args.json_path).write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
