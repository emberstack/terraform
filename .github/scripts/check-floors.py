#!/usr/bin/env python3
"""Validate every module against the provider floors it declares.

Run locally from the repository root:

    python .github/scripts/check-floors.py                          # whole tree
    python .github/scripts/check-floors.py src/modules/<module>     # one module

The main `validate` sweep resolves the newest provider inside each declared
range, so it never exercises the floor — the one version a module actually
promises. A module that starts using an attribute added in azapi 2.13 while
still declaring `>= 2.12` passes that sweep and breaks every consumer on 2.12.

This sweep pins each provider to the newest patch of its floor's minor
(`>= 2.12` becomes `~> 2.12.0`), the same rule CI applies to
`required_version`, then runs `init -backend=false` + `validate` over the same
directories the main sweep covers. The pins are `floor_override.tf` files
written into a temporary copy of src/, so the working tree and its lock files
are never touched.

Needs terraform on PATH and registry access. Exits non-zero if any directory
fails.
"""

import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC_DIR = ROOT / "src"
OVERRIDE = "floor_override.tf"
GITHUB = os.environ.get("GITHUB_ACTIONS") == "true"

# Borrowed rather than copied: check-docs.py's parser already skips braces inside
# strings, comments and heredocs, and two parsers would drift apart.
_spec = importlib.util.spec_from_file_location(
    "check_docs", Path(__file__).with_name("check-docs.py"))
_check_docs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_check_docs)
block_body = _check_docs.block_body

failures = []


def note(category, message):
    failures.append("%s: %s" % (category, message))


def report(category, where, file, message, output=""):
    note(category, "%s: %s" % (where, message))
    if GITHUB:
        print("::error file=%s/%s::%s" % (where, file, message))
    if output:
        print(output.rstrip())


def rel(path, base=ROOT):
    return os.path.relpath(path, base).replace(os.sep, "/")


# ---------------------------------------------------------------------------
# constraints
# ---------------------------------------------------------------------------

def requirements(directory):
    """Each provider a directory declares: {local name: (element body, source, constraint)}."""
    found = {}
    for path in sorted(directory.glob("*.tf")):
        text = path.read_text(encoding="utf-8")
        for block in re.finditer(r"^\s*required_providers\s*\{", text, re.M):
            body = block_body(text, block.end() - 1)
            for element in re.finditer(r"^\s*([\w-]+)\s*=\s*\{", body, re.M):
                inner = block_body(body, element.end() - 1)
                source = re.search(r'^\s*source\s*=\s*"([^"]+)"', inner, re.M)
                version = re.search(r'^\s*version\s*=\s*"([^"]+)"', inner, re.M)
                found[element.group(1)] = (
                    inner,
                    source.group(1) if source else "hashicorp/" + element.group(1),
                    version.group(1) if version else None,
                )
    return found


def floor_of(constraint):
    """The `>=` clause of a constraint, padded to three parts. None if there is none."""
    for clause in (constraint or "").split(","):
        match = re.match(r"^>=\s*v?(\d+(?:\.\d+){0,2})$", clause.strip())
        if match:
            parts = match.group(1).split(".")
            return ".".join(parts + ["0"] * (3 - len(parts)))
    return None


def minor(version):
    return tuple(version.split(".")[:2])


def lock_address(source):
    parts = source.lower().split("/")
    return "/".join(["registry.terraform.io"] * (3 - len(parts)) + parts)


def override(declared, floors):
    # An override file merges `required_providers` element by element, and each
    # element it names is replaced whole. So the element is copied with only its
    # version swapped — writing a fresh one would drop `configuration_aliases`.
    lines = ["terraform {", "  required_providers {"]
    for name, (inner, _, _) in sorted(declared.items()):
        pinned = re.sub(r'^(\s*version\s*=\s*)"[^"]*"',
                        lambda m: '%s"~> %s"' % (m.group(1), floors[name]),
                        inner, count=1, flags=re.M)
        lines.append("    %s = {%s}" % (name, pinned))
    lines += ["  }", "}", ""]
    return "\n".join(lines)


def locked(directory):
    path = directory / ".terraform.lock.hcl"
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8")
    return dict(re.findall(r'provider\s+"([^"]+)"\s*\{\s*version\s*=\s*"([^"]+)"', text))


# ---------------------------------------------------------------------------
# sweep
# ---------------------------------------------------------------------------

def terraform(binary, directory, env, *args):
    return subprocess.run([binary, "-chdir=%s" % directory, *args, "-no-color"],
                          capture_output=True, text=True, encoding="utf-8",
                          errors="replace", env=env)


def main():
    if not (SRC_DIR / "modules").is_dir():
        print("error: src/modules not found — run from the repository root")
        return 2
    binary = shutil.which("terraform")
    if binary is None:
        print("error: terraform not found on PATH")
        return 2

    targets = []
    for arg in sys.argv[1:]:
        target = Path(arg).resolve()
        if not target.is_dir() or SRC_DIR not in target.parents:
            print("error: %s is not a directory under src/" % arg)
            return 2
        targets.append(rel(target, SRC_DIR))

    env = dict(os.environ)
    # The same directory CI and the documented local sweep use, so a run after
    # either reuses what they downloaded. Resolved to an absolute path because
    # `-chdir` moves Terraform into the copy: on Windows a drive-relative path
    # would then land on the temp directory's drive, not the one created here.
    cache = Path(env.get("TF_PLUGIN_CACHE_DIR")
                 or Path.home() / ".terraform.d" / "plugin-cache").expanduser().resolve()
    cache.mkdir(parents=True, exist_ok=True)
    env["TF_PLUGIN_CACHE_DIR"] = str(cache)
    # Terraform takes a provider from the cache only when a lock file already
    # records its checksum, and the copy has no lock files — so without this every
    # init downloads afresh. The breakage the name warns about is a lock file
    # holding one platform's checksums; these lock files are thrown away.
    env["TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE"] = "true"

    with tempfile.TemporaryDirectory(prefix="check-floors-", ignore_cleanup_errors=True) as tmp:
        base = Path(tmp)
        copy = base / "src"
        # A gitignored local override never reaches CI, so it does not reach the
        # copy either.
        shutil.copytree(SRC_DIR, copy, ignore=shutil.ignore_patterns(
            ".terraform", ".terraform.lock.hcl",
            "override.tf", "override.tf.json", "*_override.tf", "*_override.tf.json"))

        dirs = sorted({p.parent for p in copy.rglob("*.tf")})

        # Every pin is written before anything is validated. Override files apply
        # wherever a directory is loaded, child modules included, so a composition
        # module that declares no providers of its own is validated against its
        # children's floors. A parent whose floor sits below a child's has no
        # version satisfying both pins and fails init — correctly, because its
        # declared floor was never reachable.
        floors = {}
        pinned = 0
        for directory in dirs:
            declared = requirements(directory)
            if not declared:
                continue
            found = {}
            for name, (_, source, constraint) in declared.items():
                floor = floor_of(constraint)
                if floor is None:
                    report("floor", rel(directory, base), "versions.tf",
                           "%s declares no `>=` floor (%s)" % (name, constraint))
                    continue
                found[name] = floor
                floors.setdefault(lock_address(source), set()).add(floor)
            if len(found) == len(declared):
                (directory / OVERRIDE).write_text(override(declared, found), encoding="utf-8")
                pinned += 1

        if targets:
            dirs = [d for d in dirs
                    if any(rel(d, copy) == t or rel(d, copy).startswith(t + "/") for t in targets)]

        # A sweep that checks nothing must never report success.
        if not dirs:
            note("sweep", "no module directories found — refusing to pass")

        resolved = {}
        for index, directory in enumerate(dirs, 1):
            where = rel(directory, base)
            print("[%3d/%d] %s" % (index, len(dirs), where), flush=True)

            result = terraform(binary, directory, env, "init", "-backend=false")
            if result.returncode:
                report("init", where, "versions.tf", "terraform init failed at the floor",
                       result.stdout + result.stderr)
                continue

            # Read the lock back rather than trusting the pin. An override that
            # stopped applying would resolve the newest version and pass, having
            # tested nothing the main sweep had not.
            for address, version in sorted(locked(directory).items()):
                expected = floors.get(address, set())
                if minor(version) in {minor(f) for f in expected}:
                    resolved.setdefault(address, set()).add(version)
                else:
                    report("pin", where, "versions.tf", "%s resolved %s, outside the %s floor"
                           % (address, version, ", ".join(sorted(expected)) or "undeclared"))

            result = terraform(binary, directory, env, "validate")
            if result.returncode:
                report("validate", where, "main.tf", "terraform validate failed at the floor",
                       result.stdout + result.stderr)

    rows = [(address.removeprefix("registry.terraform.io/"),
             ", ".join(sorted(floors[address])),
             ", ".join(sorted(resolved.get(address, ()))) or "-")
            for address in sorted(floors)]

    print()
    print("directories       : %d" % len(dirs))
    print("pinned            : %d" % pinned)
    for provider, floor, got in rows:
        print("  %-28s floor %-8s resolved %s" % (provider, floor, got))

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write("## Provider floors\n\n| Provider | Floor | Resolved |\n|---|---|---|\n")
            for provider, floor, got in rows:
                fh.write("| `%s` | %s | %s |\n" % (provider, floor, got))
            fh.write("\n")
            if failures:
                fh.write("**%d** directories validated at their floors, **%d** problem(s):\n\n"
                         % (len(dirs), len(failures)))
                for line in failures:
                    fh.write("- `%s`\n" % line)
            else:
                fh.write("**%d** directories validated at their floors. No failures.\n" % len(dirs))

    if failures:
        print("\n%d problem(s):\n" % len(failures))
        for line in failures:
            print("  %s" % line)
        return 1

    print("\nall floor checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
