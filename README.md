# alfred-terminalfinder

Alfred workflow that opens the current Finder (or Path Finder) folder in your terminal, and the terminal's current directory in Finder (or Path Finder).

<img src="tf_icon_sm.png" width="128" height="128">

Supports Terminal, iTerm, [Ghostty](https://ghostty.org), Rex and [Warp](https://www.warp.dev). Works with Alfred 5 and 6 (Powerpack required).

## Install

Download `TerminalFinder.alfredworkflow` from the [latest release](https://github.com/vcarus/alfred-terminalfinder/releases/latest) and double-click it.

The first time you use a keyword, macOS asks whether Alfred may control the apps involved. Allow it; you can review this later in System Settings → Privacy & Security → Automation.

## Usage

A keyword is two letters: where from, then where to.

| | Finder `f` | Path Finder `p` |
|---|---|---|
| Terminal `t` | `ft` / `tf` | `pt` / `tp` |
| iTerm `i` | `fi` / `if` | `pi` / `ip` |
| Ghostty `g` | `fg` / `gf` | `pg` / `gp` |
| Rex `r` | `fr` / `rf` | `pr` / `rp` |
| Warp `w` | `fw` | `pw` |

For example, `fg` opens the current **Finder** folder in **Ghostty**, and `gf` opens the current **Ghostty** directory in **Finder**.

The result in Alfred shows what the keyword will do:

![Finder → Terminal](screenshot_ft.png)

## Notes

- **Nothing is typed into your terminal.** The terminal's directory is read from the app or the process table, so it works while an editor, a pager or ssh is in the foreground, and it leaves your shell history alone.
- **Ghostty** needs version 1.3 or later for `gf` / `gp`. A folder opens in a new tab of the front window.
- **Rex** opens a folder in a new tab. `rf` / `rp` work for sessions on this Mac, not for remote sessions.
- **Warp** can't report its current directory, so it only works as a destination.
- **Finder** windows without a folder (search results, Recents) use the folder of the selected item, or the Desktop.
- If something goes wrong, a notification says what.

## Development

The workflow is built from source; the `.alfredworkflow` file is not kept in the repository.

```sh
python3 scripts/build.py --version 2.0.0   # writes dist/TerminalFinder.alfredworkflow
```

- `workflow/terminalfinder.sh` does the work: `terminalfinder.sh <from> <to>`, for example `terminalfinder.sh finder ghostty`.
- `scripts/build.py` generates `info.plist` (one keyword per route) and packs the bundle. To add an app, add a line to `FILE_MANAGERS` or `TERMINALS` there and its `dir_of_…` / `open_in_…` handlers to the script.

### Releasing

Push a version tag and GitHub Actions builds the workflow and publishes a release with the file attached:

```sh
git tag v2.0.0
git push origin v2.0.0
```

## Credits

This is a continuation of [LeEnno/alfred-terminalfinder](https://github.com/LeEnno/alfred-terminalfinder) by Enrico Herrmann, with Path Finder support by @olibob and Warp support by [@raghavpillai](https://github.com/raghavpillai). The original was inspired by [ssgreg's *Terminal in Finder's folder*](https://github.com/ssgreg/AlfredWorkflows/).
