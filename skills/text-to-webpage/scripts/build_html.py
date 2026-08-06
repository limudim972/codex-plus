#!/usr/bin/env python3
"""Inject an HTML fragment into the supplied RTL HTML template."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def read_utf8(path: Path) -> str:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return handle.read()


def write_utf8(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def build(template: str, fragment: str, title: str | None) -> str:
    matches = list(re.finditer(r"<main\b[^>]*>.*?</main\s*>", template, flags=re.IGNORECASE | re.DOTALL))
    if len(matches) != 1:
        raise ValueError("Template must contain exactly one <main>...</main> region.")
    if len(re.findall(r"<main\b", template, flags=re.IGNORECASE)) != 1:
        raise ValueError("Template must contain exactly one opening <main> tag.")

    match = matches[0]
    replacement = "<main>\n" + fragment.rstrip() + "\n</main>"
    result = template[: match.start()] + replacement + template[match.end() :]

    if title is not None:
        result, count = re.subn(
            r"(<title\b[^>]*>).*?(</title\s*>)",
            lambda m: m.group(1) + title + m.group(2),
            result,
            count=1,
            flags=re.IGNORECASE | re.DOTALL,
        )
        if count != 1:
            raise ValueError("--title was provided but the template has no <title> element.")

    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument("--content", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--title")
    args = parser.parse_args()

    template = read_utf8(args.template)
    fragment = read_utf8(args.content)
    output = build(template, fragment, args.title)
    write_utf8(args.output, output)
    print(f"Wrote {args.output} ({len(output.encode('utf-8'))} UTF-8 bytes)")


if __name__ == "__main__":
    main()
