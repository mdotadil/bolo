#!/usr/bin/env python3
"""Inline CSS <style> classes into presentation attributes for Mulberry SVGs.

flutter_svg has no CSS support (no <style> element, no `class` selector
matching). SVGs exported from Mulberry Symbols use a minified CSS block like:

    <style>.st0{fill:#fff}.st1{fill:#fbee34}
    .st10,.st11,.st12,.st13{fill:none;stroke:#231f20;stroke-width:12.5;
    stroke-linecap:round;stroke-miterlimit:10}
    .st11,.st12,.st13{stroke-width:14}
    .st12,.st13{stroke-width:6.25}
    .st13{stroke-width:4.75}</style>
    ...
    <path class="st0" d="..."/>

with shapes referencing those classes via `class="stN"`. Unstyled shapes
default to black fill under flutter_svg, which is the root cause of symbols
rendering as solid black blobs on device.

This script parses the <style> block (grouped selectors, CSS cascade order:
later rules override earlier ones property-by-property, exactly like a real
browser would apply them), replaces each `class="stN"` reference with the
fully-resolved inline presentation attributes (fill, stroke, stroke-width,
stroke-linecap, stroke-miterlimit, ...), and removes the <style> element.

If a `class="..."` attribute has no matching rule (e.g. leftover semantic
markers such as class="aac-skin-fill" with no backing <style> block at all),
it is simply dropped -- flutter_svg ignores `class` either way, and in every
observed case the element already carries its own inline `fill` attribute,
so dropping the attribute changes nothing visually.

Everything else in the file is preserved byte-for-byte: this is a targeted
text transform, not a full XML parse/re-serialize.

Usage:
    python3 tool/inline_svg_styles.py assets/symbols/eat.svg [more.svg ...]
"""
from __future__ import annotations

import re
import sys

STYLE_RE = re.compile(r"<style>(.*?)</style>", re.DOTALL)
RULE_RE = re.compile(r"([^{}]+)\{([^{}]*)\}")
CLASS_ATTR_RE = re.compile(r'\s+class="([^"]+)"')


def parse_style_rules(style_content: str) -> dict[str, dict[str, str]]:
    """Parse minified CSS into {class_name: {prop: value}}, cascade applied.

    Rules are walked in document order. Grouped selectors (`.st11,.st12{...}`)
    apply the same declarations to every listed class. When a later rule
    touches a property a class already has, it overwrites just that
    property -- matching normal CSS cascade behavior -- while leaving the
    property's original position in the accumulated dict (and hence in the
    eventual inline-attribute output) alone.
    """
    class_props: dict[str, dict[str, str]] = {}
    for selector_list, body in RULE_RE.findall(style_content):
        selectors = [s.strip() for s in selector_list.split(",") if s.strip()]
        declarations: list[tuple[str, str]] = []
        for decl in body.split(";"):
            decl = decl.strip()
            if not decl or ":" not in decl:
                continue
            prop, _, val = decl.partition(":")
            declarations.append((prop.strip(), val.strip()))
        for sel in selectors:
            if not sel.startswith("."):
                continue
            cls = sel[1:]
            props = class_props.setdefault(cls, {})
            for prop, val in declarations:
                props[prop] = val
    return class_props


def build_attr_string(props: dict[str, str]) -> str:
    return " ".join(f'{prop}="{val}"' for prop, val in props.items())


def process_svg(path: str) -> None:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    style_match = STYLE_RE.search(content)
    class_props: dict[str, dict[str, str]] = {}
    if style_match:
        class_props = parse_style_rules(style_match.group(1))
        content = content[: style_match.start()] + content[style_match.end() :]

    def replace_class(m: re.Match[str]) -> str:
        cls = m.group(1)
        if cls in class_props:
            return " " + build_attr_string(class_props[cls])
        # No backing CSS rule for this class (e.g. inert app metadata like
        # class="aac-skin-fill"/"aac-hair-fill" with no <style> block).
        # flutter_svg ignores `class` regardless, so just drop it.
        return ""

    content = CLASS_ATTR_RE.sub(replace_class, content)

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: inline_svg_styles.py <file.svg> [file2.svg ...]", file=sys.stderr)
        return 1
    for path in argv[1:]:
        process_svg(path)
        print(f"inlined: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
