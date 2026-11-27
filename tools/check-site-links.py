from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urljoin, urlsplit

site = Path(sys.argv[1] if len(sys.argv) > 1 else "_site").resolve()
base = "https://msaadasif.github.io/easyNIS/"

class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.links = []
        self.nav = []
        self.words = []
        self.in_main = False
        self.in_nav = False
        self.in_link = False
        self.skip = 0
        self.feed(path.read_text(encoding="utf-8"))

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        self.ids.update(attrs[key] for key in ("id", "name") if key in attrs)
        if tag == "main":
            self.in_main = True
        if tag == "nav":
            self.in_nav = True
        if tag in {"pre", "script", "style"}:
            self.skip += 1
        if tag in {"a", "link"} and "href" in attrs:
            self.links.append(attrs["href"])
        if tag in {"img", "script"} and "src" in attrs:
            self.links.append(attrs["src"])
        if tag == "a" and self.in_nav:
            self.nav.append([attrs.get("href", ""), []])
            self.in_link = True

    def handle_endtag(self, tag):
        if tag == "main":
            self.in_main = False
        if tag == "nav":
            self.in_nav = False
        if tag == "a":
            self.in_link = False
        if tag in {"pre", "script", "style"}:
            self.skip -= 1

    def handle_data(self, data):
        if self.in_main and not self.skip:
            self.words.extend(re.findall(r"[\w]+(?:[-'][\w]+)*", data))
        if self.in_link:
            self.nav[-1][1].append(data.strip())

pages = {p: Page(p) for p in sorted(site.rglob("*.html"))}
if not pages:
    raise SystemExit(f"No HTML in {site}")
broken = []
checked = 0
for source, page in pages.items():
    for href in page.links:
        if href in {"", "#"} or href.startswith(("data:", "mailto:", "javascript:")):
            continue
        url = urljoin(base + source.relative_to(site).as_posix(), href)
        if not url.startswith(base):
            continue
        checked += 1
        parts = urlsplit(url[len(base):])
        target = site / unquote(parts.path)
        if target.is_dir():
            target /= "index.html"
        if not target.is_file() or (
            parts.fragment and target in pages and unquote(parts.fragment) not in pages[target].ids
        ):
            broken.append((source.relative_to(site).as_posix(), href))
print(f"{len(pages)} HTML files, {checked} internal targets, {len(broken)} broken")
for (source, href), count in sorted(Counter(broken).items()):
    print(f"{source}  {href} ({count})")
print("\nNavbar")
for href, label in pages[site / "index.html"].nav:
    print(" ".join(filter(None, label)), href)
print("\nRendered prose (words, excluding code blocks)")
for path, page in pages.items():
    relative = path.relative_to(site)
    if relative.parts[0] != "reference" or relative.name == "index.html":
        print(f"{relative.as_posix():55} {len(page.words):5}")
sys.exit(bool(broken))
