#!/usr/bin/env python3
"""Add a Swift source file to MacTorn.xcodeproj.

The project keeps hand-written, human-readable object ids (AAA0xxxx for build files,
AAA1xxxx for file references), so adding a file is three mechanical insertions rather
than a full pbxproj parse:

  1. a PBXBuildFile entry,
  2. a PBXFileReference entry,
  3. membership in the owning PBXGroup and in the target's PBXSourcesBuildPhase.

Usage:
    scripts/add-source-file.py <group-name> <target> <file.swift> [<file.swift> ...]

    group-name  the PBXGroup to file it under, e.g. Networking, Models, ViewModels.
                Names repeat across targets; disambiguate as Models@TornEndpointTests.swift.
    target      MacTorn | MacTornTests

Idempotent: a file already referenced in the project is skipped.
"""
import re
import sys
from pathlib import Path

PROJ = Path(__file__).resolve().parent.parent / "MacTorn" / "MacTorn.xcodeproj" / "project.pbxproj"

def next_ids(text, count):
    used = set(re.findall(r"AAA0([0-9A-F]{4})", text))
    n = max(int(u, 16) for u in used)
    return [(f"AAA0{n + i + 1:04X}", f"AAA1{n + i + 1:04X}") for i in range(count)]


def sources_phase_span(text, target):
    """Return (start, end) offsets of the PBXSourcesBuildPhase files list for `target`."""
    # Sources phases appear in order: app target first, then test targets. Locate each
    # phase's files list and pick by the order the targets are declared.
    phases = [m.start() for m in re.finditer(r"isa = PBXSourcesBuildPhase;", text)]
    targets = re.findall(r"/\* (\w+) \*/ = \{\s*isa = PBXNativeTarget;", text)
    if target not in targets:
        raise SystemExit(f"target {target} not found; have {targets}")
    idx = targets.index(target)
    if idx >= len(phases):
        raise SystemExit(f"no Sources phase for {target}")
    start = text.index("files = (", phases[idx])
    end = text.index(");", start)
    return start + len("files = ("), end


def group_span(text, group):
    """Locate a PBXGroup's children list.

    Group *names* are not unique — the app target and the test target both have a
    `Models` and a `ViewModels`. So a group may also be addressed as `Group@sibling.swift`,
    naming a file already inside the intended one, which disambiguates exactly.
    """
    if "@" in group:
        group, sibling = group.split("@", 1)
        for m in re.finditer(r"/\* " + re.escape(group) + r" \*/ = \{\s*isa = PBXGroup;", text):
            start = text.index("children = (", m.start())
            end = text.index(");", start)
            if f"/* {sibling} */" in text[start:end]:
                return start + len("children = ("), end
        raise SystemExit(f"group {group} containing {sibling} not found")

    matches = list(re.finditer(r"/\* " + re.escape(group) + r" \*/ = \{\s*isa = PBXGroup;", text))
    if not matches:
        raise SystemExit(f"group {group} not found")
    if len(matches) > 1:
        raise SystemExit(f"group {group} is ambiguous; use {group}@<sibling-file.swift>")
    start = text.index("children = (", matches[0].start())
    end = text.index(");", start)
    return start + len("children = ("), end


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    group, target, *files = sys.argv[1:]
    text = PROJ.read_text()

    files = [f for f in files if f"/* {Path(f).name} */" not in text]
    if not files:
        print("nothing to add (all files already referenced)")
        return

    ids = next_ids(text, len(files))

    # 1 + 2: object declarations, appended next to an existing pair so they land inside
    # the right isa sections.
    build_anchor = "\t\tAAA00030 /* TornEndpoint.swift in Sources */"
    ref_anchor = "\t\tAAA10030 /* TornEndpoint.swift */ = {isa = PBXFileReference;"
    build_lines, ref_lines = [], []
    for (bid, fid), f in zip(ids, files):
        name = Path(f).name
        build_lines.append(
            f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};\n"
        )
        ref_lines.append(
            f"\t\t{fid} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n"
        )
    text = text.replace(build_anchor, "".join(build_lines) + build_anchor, 1)
    text = text.replace(ref_anchor, "".join(ref_lines) + ref_anchor, 1)

    # 3a: group membership
    gs, _ = group_span(text, group)
    entries = "".join(
        f"\n\t\t\t\t{fid} /* {Path(f).name} */," for (_, fid), f in zip(ids, files)
    )
    text = text[:gs] + entries + text[gs:]

    # 3b: compile membership
    ss, _ = sources_phase_span(text, target)
    entries = "".join(
        f"\n\t\t\t\t{bid} /* {Path(f).name} in Sources */," for (bid, _), f in zip(ids, files)
    )
    text = text[:ss] + entries + text[ss:]

    PROJ.write_text(text)
    for (bid, fid), f in zip(ids, files):
        print(f"added {Path(f).name} -> group {group}, target {target} ({bid}/{fid})")


if __name__ == "__main__":
    main()
