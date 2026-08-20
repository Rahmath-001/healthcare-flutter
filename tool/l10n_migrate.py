"""Rewrites hardcoded UI strings in a screen to `context.l10n` lookups.

Applied once per file with an explicit mapping, then deleted or kept as a record
of what moved. It refuses silently-failing edits: every replacement must match,
so a typo in a mapping is a loud error rather than a string that quietly stayed
in English.

Run as:  python tool/l10n_migrate.py <file> <<'MAP'
    'Old literal' => l10nKey
    MAP
"""

import io
import re
import sys


def migrate(path: str, pairs: list[tuple[str, str]], *, ref: str = "context") -> int:
    src = io.open(path, encoding="utf-8").read()
    original = src
    missed = []

    for literal, key in pairs:
        # Match the literal only where it is a Dart single-quoted string, so a
        # word appearing inside a comment or an identifier is left alone.
        needle = "'" + literal.replace("'", r"\'") + "'"
        if needle not in src:
            missed.append(literal)
            continue
        src = src.replace(needle, f"{ref}.l10n.{key}")

    if missed:
        raise SystemExit(
            f"{path}: {len(missed)} literal(s) not found:\n  "
            + "\n  ".join(repr(m) for m in missed)
        )

    if src == original:
        return 0

    src = drop_const_around_lookups(src, ref)

    # Add the import if anything changed and it is not already there.
    if "l10n/l10n.dart" not in src:
        # Directories between lib/ and the file decide how far up to reach.
        depth = len(path.split("/")) - 2  # drop "lib" and the filename
        src = _add_import(src, "../" * depth + "l10n/l10n.dart")

    io.open(path, "w", encoding="utf-8").write(src)
    return len(pairs)


def drop_const_around_lookups(src: str, ref: str = "context") -> str:
    """Removes `const` from any constructor whose arguments now contain a lookup.

    A `const` expression cannot hold a runtime value, and that is the whole cost
    of localising: these were only const because the string was baked in. Done
    by matching parentheses rather than by pattern, because the offending
    `const` is often several lines above the string it invalidates.
    """
    marker = f"{ref}.l10n."
    changed = True

    while changed:
        changed = False
        for match in re.finditer(r"const\s+([A-Z]\w*)\s*\(", src):
            open_paren = match.end() - 1
            depth = 0
            close = -1
            for i in range(open_paren, len(src)):
                if src[i] == "(":
                    depth += 1
                elif src[i] == ")":
                    depth -= 1
                    if depth == 0:
                        close = i
                        break
            if close < 0:
                continue
            if marker in src[open_paren:close]:
                src = src[: match.start()] + src[match.start() + len("const ") :]
                changed = True
                break

    return src


def _add_import(src: str, target: str) -> str:
    """Inserts a relative import in alphabetical position among the others."""
    lines = src.split("\n")
    imports = [i for i, l in enumerate(lines) if re.match(r"^import '(?!package:)", l)]
    stmt = f"import '{target}';"

    if imports:
        for i in imports:
            if lines[i] > stmt:
                lines.insert(i, stmt)
                break
        else:
            lines.insert(imports[-1] + 1, stmt)
    else:
        pkg = [i for i, l in enumerate(lines) if l.startswith("import 'package:")]
        lines.insert((pkg[-1] + 1) if pkg else 0, "\n" + stmt)

    return "\n".join(lines)


if __name__ == "__main__":
    target_path = sys.argv[1]
    mapping = []
    for line in sys.stdin.read().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        left, _, right = line.partition("=>")
        left = left.strip()
        # Quoted keeps whitespace verbatim — a trailing space is part of the
        # string ("New here? ") and stripping it makes the match fail.
        if len(left) >= 2 and left[0] == left[-1] == "'":
            left = left[1:-1]
        mapping.append((left, right.strip()))

    print(f"{target_path}: {migrate(target_path, mapping)} replaced")
