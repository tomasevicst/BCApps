#!/usr/bin/env python3

import argparse
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\((?P<target><[^>]+>|[^)\s]+)(?:\s+[^)]*)?\)")
AL_FILENAME = re.compile(r"`[^`\r\n]+\.al`", re.IGNORECASE)
VOLATILE_COUNT = re.compile(
    r"\b(?:about\s+|approximately\s+|roughly\s+|~\s*)?\d+\s+"
    r"(?:AL\s+)?(?:objects?|files?|tables?|table\s+extensions?|codeunits?|interfaces?|"
    r"events?|subscribers?|procedures?|tests?|test\s+codeunits?|helper\s+codeunits?)\b",
    re.IGNORECASE,
)


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def markdown_files(scope: Path) -> list[Path]:
    return sorted(path for path in scope.rglob("*.md") if path.is_file())


def relative_link_errors(files: list[Path]) -> tuple[int, list[str]]:
    checked = 0
    errors: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        for match in MARKDOWN_LINK.finditer(text):
            target = match.group("target").strip("<>")
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            checked += 1
            resolved = path.parent / unquote(parsed.path)
            if not resolved.exists():
                errors.append(f"{path}:{line_number(text, match.start())}: broken link '{target}'")
    return checked, errors


def bare_al_filename_errors(files: list[Path]) -> list[str]:
    errors: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        link_spans = [(match.start(), match.end()) for match in MARKDOWN_LINK.finditer(text)]
        for match in AL_FILENAME.finditer(text):
            if not any(start <= match.start() and match.end() <= end for start, end in link_spans):
                errors.append(
                    f"{path}:{line_number(text, match.start())}: AL filename is not a Markdown link: {match.group()}"
                )
    return errors


def volatile_count_warnings(files: list[Path]) -> list[str]:
    warnings: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        for match in VOLATILE_COUNT.finditer(text):
            warnings.append(
                f"{path}:{line_number(text, match.start())}: review volatile count: {match.group()!r}"
            )
    return warnings


def boundary_errors(scope: Path, source_root: Path) -> list[str]:
    entry_point = scope / "AGENTS.md"
    if not entry_point.is_file() or not source_root.is_dir():
        return []

    text = entry_point.read_text(encoding="utf-8").replace("\\", "/").casefold()
    errors: list[str] = []
    for child in sorted(path for path in source_root.iterdir() if path.is_dir()):
        if not any(child.rglob("*.al")):
            continue
        relative_child = child.relative_to(scope).as_posix().casefold()
        if relative_child not in text:
            errors.append(
                f"{entry_point}: immediate AL-owning child '{relative_child}' has no visible document/link/omit entry"
            )
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate BC AL code-adjacent Markdown documentation.")
    parser.add_argument("--scope", required=True, type=Path, help="Physical documentation owner to validate.")
    parser.add_argument(
        "--source-root",
        type=Path,
        help="Source root whose immediate AL-owning children must be accounted for. Defaults to <scope>/src when present.",
    )
    parser.add_argument("--skip-boundary-check", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    scope = args.scope.resolve()
    if not scope.is_dir():
        print(f"ERROR: scope does not exist: {scope}")
        return 2

    files = markdown_files(scope)
    if not files:
        print(f"ERROR: no Markdown files found under: {scope}")
        return 2

    source_root = args.source_root.resolve() if args.source_root else (scope / "src" if (scope / "src").is_dir() else scope)
    relative_link_count, errors = relative_link_errors(files)
    errors.extend(bare_al_filename_errors(files))
    if not args.skip_boundary_check:
        errors.extend(boundary_errors(scope, source_root))
    warnings = volatile_count_warnings(files)

    print(f"Markdown files: {len(files)}")
    print(f"Relative links checked: {relative_link_count}")
    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}")
    print(f"Result: {'FAIL' if errors else 'PASS'} ({len(errors)} error(s), {len(warnings)} warning(s))")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())