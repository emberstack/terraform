#!/usr/bin/env python3
"""Documentation and module-structure consistency checks.

Run locally from the repository root:

    python .github/scripts/check-docs.py

Verifies four things that would otherwise rot silently:

  1. every relative link and heading anchor resolves
  2. every module on disk is linked exactly once from a family guide
  3. every module count written in prose matches what is on disk
  4. every module has the four required files, and every variable and output
     carries a description

Exits non-zero if any category fails.
"""

import os
import re
from pathlib import PurePosixPath
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES_DIR = ROOT / "src" / "modules"
FAMILIES = ("azure", "entra", "fortios", "github")

failures = []


def note(category, message):
    failures.append("%s: %s" % (category, message))


def doc_files():
    files = sorted((ROOT / "docs").rglob("*.md"))
    extras = (
        "README.md",
        "CLAUDE.md",
        "SECURITY.md",
        "CODE_OF_CONDUCT.md",
        ".github/PULL_REQUEST_TEMPLATE.md",
    )
    for extra in extras:
        path = ROOT / extra
        if path.exists():
            files.append(path)
    return files


def slugify(heading):
    text = heading.strip().lower().replace("`", "")
    text = re.sub(r"[^\w\s-]", "", text)
    # One hyphen per whitespace character, not per run. GitHub does it that way,
    # so a heading like "a — b" leaves two spaces once the dash is stripped and
    # anchors as `a--b`. Collapsing runs here would reject that real link.
    return re.sub(r"\s", "-", text).strip("-")


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


# ---------------------------------------------------------------------------
# 1. links and anchors
# ---------------------------------------------------------------------------

def resolve_cased(base, target):
    """Resolve a relative link, matching case exactly. None if it does not exist.

    `Path.exists()` is case-insensitive on Windows and case-sensitive on the
    ubuntu runner, so a mis-cased link passed the documented local command and
    failed only in CI. Comparing each component against the directory listing is
    a plain string match, so both platforms agree.
    """
    current = base
    for part in PurePosixPath(target).parts:
        if part == ".":
            continue
        if part == "..":
            current = current.parent
            continue
        try:
            if part not in os.listdir(current):
                return None
        except OSError:
            return None
        current = current / part
    return current


def strip_fences(text):
    """Blank out fenced code blocks, keeping line count intact.

    Headings and links are markdown syntax; inside a fence they are neither. A
    `# comment` in a shell example was being slugified into the anchor set, so a
    link to a heading that had since been renamed could still resolve — against
    a slug supplied by a code comment. Same reasoning for links: a markdown
    example inside a fence is illustration, not a reference to check.
    """
    out, fence = [], None
    for line in text.split("\n"):
        opener = re.match(r"(`{3,}|~{3,})", line.lstrip())
        if fence is None:
            if opener:
                fence = opener.group(1)
                out.append("")
                continue
            out.append(line)
            continue
        closer = re.match(r"(`{3,}|~{3,})\s*$", line.lstrip())
        if closer and closer.group(1)[0] == fence[0] and len(closer.group(1)) >= len(fence):
            fence = None
        out.append("")
    return "\n".join(out)


def check_links(files):
    prose = {path: strip_fences(path.read_text(encoding="utf-8")) for path in files}

    anchors = {}
    for path in files:
        anchors[rel(path)] = {
            slugify(m.group(2)) for m in re.finditer(r"^(#{1,6})\s+(.*)$", prose[path], re.M)
        }

    checked = 0
    link_re = re.compile(r"\[([^\]]*)\]\(([^)\s]+)\)")
    for path in files:
        text = prose[path]
        for match in link_re.finditer(text):
            target = match.group(2)
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            checked += 1
            file_part, _, anchor = target.partition("#")
            if file_part:
                resolved = resolve_cased(path.parent, file_part)
                if resolved is None:
                    note("links", "%s -> missing path %s" % (rel(path), target))
                    continue
                key = rel(resolved)
            else:
                key = rel(path)
            if anchor:
                if key not in anchors:
                    note("links", "%s -> anchor on non-doc %s" % (rel(path), target))
                elif anchor not in anchors[key]:
                    note("links", "%s -> missing anchor %s" % (rel(path), target))
    return checked


# ---------------------------------------------------------------------------
# 2. inventory
# ---------------------------------------------------------------------------

def check_inventory(on_disk):
    linked = Counter()
    for guide in sorted((ROOT / "docs" / "modules").glob("*.md")):
        text = guide.read_text(encoding="utf-8")
        for match in re.finditer(r"\(\.\./\.\./src/modules/([^/)]+)/\)", text):
            linked[match.group(1)] += 1

    for name in sorted(on_disk - set(linked)):
        note("inventory", "%s is not linked from any family guide" % name)
    for name in sorted(set(linked) - on_disk):
        note("inventory", "%s is linked but does not exist on disk" % name)
    for name, count in sorted(linked.items()):
        if count > 1:
            note("inventory", "%s is linked %d times (expected once)" % (name, count))
    return len(linked)


# ---------------------------------------------------------------------------
# 3. counts written in prose
# ---------------------------------------------------------------------------

def expect(label, pattern, text, source, actual):
    """Assert the single capture group of `pattern` equals `actual`."""
    match = re.search(pattern, text, re.M)
    if not match:
        note("counts", "%s: pattern for %s no longer matches — update the checker "
                       "or restore the sentence" % (source, label))
        return
    found = int(match.group(1))
    if found != actual:
        note("counts", "%s: %s says %d, disk says %d" % (source, label, found, actual))


def check_counts(on_disk):
    per_family = {f: len([m for m in on_disk if m.startswith(f + "-")]) for f in FAMILIES}
    total = len(on_disk)
    # Same exclusions as module_dirs(). Without them a local `terraform init`
    # leaves .terraform/ caches behind and an examples/basic/versions.tf counts
    # as a submodule, so the check would disagree with itself depending on
    # whether you had validated first.
    submodules = len([
        p for p in MODULES_DIR.glob("*/**/versions.tf")
        if p.parent != MODULES_DIR / p.relative_to(MODULES_DIR).parts[0]
        and ".terraform" not in p.parts
        and "examples" not in p.parts
    ])

    for family in FAMILIES:
        guide = ROOT / "docs" / "modules" / ("%s.md" % family)
        expect("header count", r"^(\d+) modules on ", guide.read_text(encoding="utf-8"),
               rel(guide), per_family[family])

    docs_index = (ROOT / "docs" / "README.md").read_text(encoding="utf-8")
    root_readme = (ROOT / "README.md").read_text(encoding="utf-8")
    for family in FAMILIES:
        expect("%s row" % family,
               r"\[[^\]]+\]\(modules/%s\.md\)[^|]*\|[^|]*\|\s*(\d+)\s*\|" % family,
               docs_index, "docs/README.md", per_family[family])
        expect("%s row" % family,
               r"\|[^|]*\|[^|]*\|\s*(\d+)\s*\|[^|]*docs/modules/%s\.md" % family,
               root_readme, "README.md", per_family[family])

    expect("module total", r"^(\d+) modules plus \d+ nested submodules",
           root_readme, "README.md", total)
    expect("submodule total", r"^\d+ modules plus (\d+) nested submodules",
           root_readme, "README.md", submodules)

    claude = (ROOT / "CLAUDE.md").read_text(encoding="utf-8")
    expect("module total", r"\*\*(\d+)\*\* modules plus", claude, "CLAUDE.md", total)
    expect("submodule total", r"\*\*\d+\*\* modules plus (\d+)\s*\n?nested submodules",
           claude, "CLAUDE.md", submodules)
    expect("directory total", r"\*\*(\d+) module directories\*\*",
           claude, "CLAUDE.md", total + submodules)


# ---------------------------------------------------------------------------
# 4. module structure
# ---------------------------------------------------------------------------

REQUIRED_FILES = ("main.tf", "variables.tf", "outputs.tf", "versions.tf")


def module_dirs():
    """Every directory holding .tf files, excluding examples and provider caches."""
    found = {p.parent for p in MODULES_DIR.rglob("*.tf") if ".terraform" not in p.parts}
    return sorted(d for d in found if "examples" not in d.parts)


def block_body(text, open_brace, limit=None):
    """Return the text between a block's braces, found by depth counting.

    Braces inside strings, comments and heredocs are skipped. Counting them was
    wrong in both directions: a `default = "}"` closed the body early and a
    described variable was reported as undescribed, failing a valid pull
    request; a `default = "{"` ran on into the next block and borrowed its
    description, passing an undescribed one.

    `limit` is a hard stop at the next block's declaration, so even an unhandled
    quoting form can only truncate a body — never annex the following one.
    """
    n = len(text) if limit is None else limit
    depth, i = 0, open_brace
    while i < n:
        c = text[i]
        if c == "#" or text[i:i + 2] == "//":
            nl = text.find("\n", i)
            i = n if nl == -1 else nl + 1
            continue
        if text[i:i + 2] == "/*":
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
            continue
        if c == '"':
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        heredoc = re.match(r"<<-?([A-Za-z_]\w*)", text[i:n])
        if heredoc:
            line_end = text.find("\n", i)
            close = None
            if line_end != -1:
                close = re.compile(r"^[ \t]*%s[ \t]*$" % re.escape(heredoc.group(1)),
                                   re.M).search(text, line_end, n)
            i = close.end() if close else n
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace + 1:i]
        i += 1
    return text[open_brace + 1:n]


def check_structure(dirs):
    """Four required files per module, and a description on every variable and output.

    The tree is at 100% description coverage and CLAUDE.md says to keep it there.
    Nothing enforced that before this check existed.
    """
    # A sweep that checks nothing must never report success.
    if not dirs:
        note("structure", "no module directories found — refusing to pass")
        return 0

    for directory in dirs:
        for name in REQUIRED_FILES:
            if not (directory / name).exists():
                note("structure", "%s is missing %s" % (rel(directory), name))

    described = 0
    for directory in dirs:
        for name in ("variables.tf", "outputs.tf"):
            path = directory / name
            if not path.exists():
                continue
            text = path.read_text(encoding="utf-8")
            blocks = list(re.finditer(r'^(variable|output)\s+"([^"]+)"\s*\{', text, re.M))
            for index, match in enumerate(blocks):
                # Bound each body at the next declaration so no block can claim
                # the following one's description.
                stop = blocks[index + 1].start() if index + 1 < len(blocks) else len(text)
                body = block_body(text, match.end() - 1, stop)
                if re.search(r"^\s{2}description\s*=", body, re.M):
                    described += 1
                else:
                    note("structure", "%s: %s %s has no description"
                         % (rel(path), match.group(1), match.group(2)))
    return described


def main():
    if not MODULES_DIR.is_dir():
        print("error: %s not found — run from the repository root" % rel(MODULES_DIR))
        return 2

    on_disk = {p.name for p in MODULES_DIR.iterdir() if p.is_dir()}

    files = doc_files()
    checked = check_links(files)
    linked = check_inventory(on_disk)
    check_counts(on_disk)

    dirs = module_dirs()
    described = check_structure(dirs)

    print("docs checked      : %d" % len(files))
    print("links resolved    : %d" % checked)
    print("modules on disk   : %d" % len(on_disk))
    print("modules linked    : %d" % linked)
    print("module dirs       : %d" % len(dirs))
    print("described vars    : %d" % described)

    if failures:
        print("\n%d problem(s):\n" % len(failures))
        for line in failures:
            print("  %s" % line)
        return 1

    print("\nall documentation checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
