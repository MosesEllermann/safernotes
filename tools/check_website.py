"""Validate local website links and the documentation entry points."""

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1] / "website"


class Page(HTMLParser):
    def __init__(self, path: Path):
        super().__init__()
        self.ids: set[str] = set()
        self.links: list[str] = []
        self.feed(path.read_text())

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if attributes.get("id"):
            self.ids.add(attributes["id"])
        for name in ("href", "src"):
            if attributes.get(name):
                self.links.append(attributes[name])


def main():
    pages = {path: Page(path) for path in ROOT.glob("*.html")}
    errors = []
    for path, page in pages.items():
        for link in page.links:
            url = urlsplit(link)
            if url.scheme or url.netloc:
                continue
            target = (path.parent / unquote(url.path)).resolve() if url.path else path
            if target == ROOT / "downloads/safernotes-android.apk":
                continue  # Separately signed and deployed release artifact.
            if not target.is_relative_to(ROOT) or not target.is_file():
                errors.append(f"{path.name}: missing local target {link}")
            elif url.fragment and target in pages and unquote(url.fragment) not in pages[target].ids:
                errors.append(f"{path.name}: missing anchor {link}")
    home = pages.get(ROOT / "index.html")
    docs = pages.get(ROOT / "docs.html")
    if not home or "./docs.html" not in home.links or "./docs.html#faq" not in home.links:
        errors.append("Homepage must link to documentation and FAQ.")
    if not docs or not {"docker", "faq"}.issubset(docs.ids):
        errors.append("Documentation must contain Docker instructions and FAQ.")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Website links checked across {len(pages)} pages.")


if __name__ == "__main__":
    main()
