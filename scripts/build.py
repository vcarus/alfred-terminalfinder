#!/usr/bin/env python3
"""Build TerminalFinder.alfredworkflow from the files in workflow/.

    scripts/build.py [--version 2.0.0] [--out dist]
    scripts/build.py --icons    # redraw workflow/icons/routes (macOS only)

info.plist is generated here, so adding an app means adding one line to
FILE_MANAGERS or TERMINALS (plus its handlers in workflow/terminalfinder.sh).
Only the Python standard library is used.
"""

import argparse
import plistlib
import subprocess
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "workflow"

NAME = "TerminalFinder"
BUNDLE_ID = "com.vcarus.terminalfinder"
WEBSITE = "https://github.com/vcarus/alfred-terminalfinder"

# (keyword letter, id used by terminalfinder.sh, display name)
FILE_MANAGERS = [
    ("f", "finder", "Finder"),
    ("p", "pathfinder", "Path Finder"),
]
# The last field says whether the terminal can report its current directory.
TERMINALS = [
    ("t", "terminal", "Terminal", True),
    ("i", "iterm", "iTerm", True),
    ("g", "ghostty", "Ghostty", True),
    ("r", "rex", "Rex", True),
    ("w", "warp", "Warp", False),
]

README = """# TerminalFinder

Open the current Finder (or Path Finder) folder in your terminal, and the
terminal's current directory in Finder (or Path Finder).

A keyword is two letters: where from, then where to.

| | Finder `f` | Path Finder `p` |
|---|---|---|
| Terminal `t` | `ft` / `tf` | `pt` / `tp` |
| iTerm `i` | `fi` / `if` | `pi` / `ip` |
| Ghostty `g` | `fg` / `gf` | `pg` / `gp` |
| Rex `r` | `fr` / `rf` | `pr` / `rp` |
| Warp `w` | `fw` | `pw` |

Warp can't report its current directory, so it only works as a destination.

The first time you use a keyword, macOS asks whether Alfred may control the
apps involved. Allow it; you can review this later in System Settings →
Privacy & Security → Automation.

Ghostty needs version 1.3 or later.
"""


def uid(*parts):
    """A stable UID, so reinstalling keeps keywords the user has changed."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "/".join((WEBSITE,) + parts))).upper()


def routes():
    """Every (keyword, from, to) the workflow offers, as (letter, id, name)."""
    for fm in FILE_MANAGERS:
        for term in TERMINALS:
            yield fm[0] + term[0], fm[:3], term[:3]
        for term in TERMINALS:
            if term[3]:
                yield term[0] + fm[0], term[:3], fm[:3]


def route_icon(keyword, src):
    """The drawn source-and-destination icon, or just the source app's."""
    combined = SRC / "icons" / "routes" / f"{keyword}.png"
    return combined if combined.exists() else SRC / "icons" / f"{src[1]}.png"


def draw_route_icons():
    """Redraw workflow/icons/routes from the app icons in workflow/icons.

    The results are committed, so a normal build needs neither Swift nor macOS.
    Routes whose apps have no icon there are skipped.
    """
    out = SRC / "icons" / "routes"
    out.mkdir(exist_ok=True)
    binary = ROOT / "dist" / "compose_icon"
    binary.parent.mkdir(exist_ok=True)
    subprocess.run(["swiftc", "-O", "-o", str(binary),
                    str(ROOT / "scripts" / "compose_icon.swift")], check=True)
    for keyword, src, dst in routes():
        parts = [SRC / "icons" / f"{app[1]}.png" for app in (src, dst)]
        if all(part.exists() for part in parts):
            subprocess.run([str(binary), *map(str, parts),
                            str(out / f"{keyword}.png")], check=True)
            print(f"{keyword}: {src[2]} → {dst[2]}")
        else:
            print(f"{keyword}: skipped, no icon for one of the apps")
    binary.unlink()


def build_plist(version):
    notify = uid("notification")
    objects, connections, uidata, icons = [], {}, {}, {}

    for row, (keyword, src, dst) in enumerate(routes()):
        kw_uid, run_uid = uid(keyword, "keyword"), uid(keyword, "script")
        objects.append({
            "type": "alfred.workflow.input.keyword",
            "uid": kw_uid,
            "version": 1,
            "config": {
                "argumenttype": 2,  # no argument
                "keyword": keyword,
                "text": f"{src[2]} → {dst[2]}",
                "subtext": f"Open current {src[2]} directory in {dst[2]}",
                "withspace": False,
            },
        })
        objects.append({
            "type": "alfred.workflow.action.script",
            "uid": run_uid,
            "version": 2,
            "config": {
                "type": 5,  # /bin/zsh
                "script": f"/bin/zsh ./terminalfinder.sh {src[1]} {dst[1]}",
                "scriptfile": "",
                "scriptargtype": 1,  # argv
                "escaping": 102,
                "concurrently": False,
            },
        })
        connections[kw_uid] = [{
            "destinationuid": run_uid,
            "modifiers": 0,
            "modifiersubtext": "",
            "vitoclose": False,
        }]
        connections[run_uid] = [{
            "destinationuid": notify,
            "modifiers": 0,
            "modifiersubtext": "",
            "vitoclose": False,
        }]
        y = 20 + row * 110
        uidata[kw_uid] = {"xpos": 60, "ypos": y}
        uidata[run_uid] = {"xpos": 300, "ypos": y}
        icons[kw_uid] = route_icon(keyword, src)

    # The script prints only when something went wrong.
    objects.append({
        "type": "alfred.workflow.output.notification",
        "uid": notify,
        "version": 1,
        "config": {
            "title": NAME,
            "text": "{query}",
            "onlyshowifquerypopulated": True,
            "lastpathcomponent": False,
            "removeextension": False,
        },
    })
    uidata[notify] = {"xpos": 560, "ypos": 20}

    plist = {
        "name": NAME,
        "bundleid": BUNDLE_ID,
        "version": version,
        "createdby": "vcarus (originally by LeEnno)",
        "webaddress": WEBSITE,
        "category": "Productivity",
        "description": "Open the current Finder or Path Finder folder in "
                       "Terminal, iTerm, Ghostty, Rex or Warp, and back",
        "readme": README,
        "disabled": False,
        "objects": objects,
        "connections": connections,
        "uidata": uidata,
        "userconfigurationconfig": [],
        "variablesdontexport": [],
    }
    return plist, icons


def add(archive, name, data, executable=False):
    # Fixed timestamps and order make the build reproducible.
    info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = (0o755 if executable else 0o644) << 16
    archive.writestr(info, data)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", default="0.0.0-dev")
    parser.add_argument("--out", default=str(ROOT / "dist"))
    parser.add_argument("--icons", action="store_true",
                        help="redraw the route icons and exit")
    args = parser.parse_args()
    if args.icons:
        draw_route_icons()
        return
    version = args.version.removeprefix("v")

    plist, icons = build_plist(version)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    target = out / f"{NAME}.alfredworkflow"

    with zipfile.ZipFile(target, "w") as archive:
        add(archive, "info.plist", plistlib.dumps(plist, sort_keys=True))
        add(archive, "icon.png", (SRC / "icon.png").read_bytes())
        add(archive, "terminalfinder.sh",
            (SRC / "terminalfinder.sh").read_bytes(), executable=True)
        for key, icon in sorted(icons.items()):
            if icon.exists():  # others fall back to the workflow icon
                add(archive, f"{key}.png", icon.read_bytes())

    keywords = " ".join(keyword for keyword, _, _ in routes())
    print(f"{target} (version {version})")
    print(f"keywords: {keywords}")


if __name__ == "__main__":
    main()
