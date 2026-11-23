#!/bin/zsh
#
# terminalfinder.sh <from> <to>
#
# Opens the current directory of the frontmost <from> window in <to>.
#
#   file managers: finder, pathfinder
#   terminals:     terminal, iterm, ghostty, rex, warp (warp only as <to>)
#
# On failure a short message goes to stdout, which the workflow shows as a
# notification. Nothing is printed on success.

set -u
setopt extended_glob

# Alfred runs scripts without a locale. In the C locale lsof escapes non-ASCII
# path names, which would break folders with such names.
export LC_ALL=en_US.UTF-8

fail() {
  print -rn -- "$1"
  print -ru2 -- "$1"
  # Alfred only needs the message; a shell caller also gets a failing status.
  [[ -n ${alfred_version:-} ]] && exit 0
  exit 1
}

# Bundle IDs, so apps are found whatever they are named ("Rex Beta", "iTerm2").
typeset -A BUNDLE=(
  finder      com.apple.finder
  pathfinder  com.cocoatech.PathFinder
  terminal    com.apple.Terminal
  iterm       com.googlecode.iterm2
  ghostty     com.mitchellh.ghostty
  rex         com.superlogical.rex
  warp        dev.warp.Warp-Stable
)
typeset -A LABEL=(
  finder "Finder"  pathfinder "Path Finder"  terminal "Terminal"  iterm "iTerm"
  ghostty "Ghostty"  rex "Rex"  warp "Warp"
)

is_running() {
  [[ "$(osascript -e "application id \"${BUNDLE[$1]}\" is running" 2>/dev/null)" == true ]]
}

# ---------------------------------------------------------------------------
# Reading the current directory
# ---------------------------------------------------------------------------

# Working directory of whatever runs in the foreground of a tty, read from the
# process table. Nothing is typed into the terminal, so this also works while
# an editor, a pager or ssh is running.
cwd_of_tty() {
  local tty=${1#/dev/} pid dir
  [[ -n $tty ]] || return 1
  local -a pids
  # Foreground process group first, then everything else, newest first.
  pids=(
    ${(f)"$(ps -t "$tty" -o pid=,pgid=,tpgid= 2>/dev/null | awk '$2 == $3 { print $1 }')"}
    ${(Oa)${(f)"$(ps -t "$tty" -o pid= 2>/dev/null)"}}
  )
  for pid in $pids; do
    pid=${pid// /}
    [[ -n $pid ]] || continue
    dir=$(lsof -a -d cwd -p "$pid" -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)
    if [[ -n $dir && -d $dir ]]; then
      print -r -- "$dir"
      return 0
    fi
  done
  return 1
}

# file://host/some%20path -> /some path
path_of_file_url() {
  local p=${1#file://}
  p=/${p#*/}
  # Percent-decode byte by byte, so UTF-8 names survive.
  printf '%b\n' "${p//\%/\\x}"
}

dir_of_finder() {
  osascript <<'EOF'
tell application id "com.apple.finder"
  -- The front Finder window's folder. Search results, Recents and the like
  -- have no folder, so fall back to the selection's folder, then the Desktop.
  try
    return POSIX path of (target of front Finder window as alias)
  end try
  try
    return POSIX path of (container of (item 1 of (get selection)) as alias)
  end try
  return POSIX path of (desktop as alias)
end tell
EOF
}

dir_of_pathfinder() {
  osascript <<'EOF'
tell application id "com.cocoatech.PathFinder"
  return POSIX path of the target of the front finder window
end tell
EOF
}

dir_of_terminal() {
  cwd_of_tty "$(osascript -e 'tell application id "com.apple.Terminal" to get tty of selected tab of front window')"
}

dir_of_iterm() {
  cwd_of_tty "$(osascript -e 'tell application id "com.googlecode.iterm2" to get tty of current session of current window')"
}

dir_of_ghostty() {
  local out dir
  # Needs Ghostty 1.3+, which added AppleScript support.
  out=$(osascript <<'EOF'
tell application id "com.mitchellh.ghostty"
  set t to focused terminal of selected tab of front window
  return (working directory of t) & linefeed & (tty of t)
end tell
EOF
  ) || return 1
  dir=${out%%$'\n'*}
  if [[ -n $dir && -d $dir ]]; then
    print -r -- "$dir"
  else
    cwd_of_tty "${out#*$'\n'}"
  fi
}

rex_cli() {
  local c
  for c in \
    "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex" \
    "$(osascript -e 'POSIX path of (path to application id "com.superlogical.rex")' 2>/dev/null)Contents/Helpers/Rex Server.rex/Contents/MacOS/rex" \
    "$(command -v rex 2>/dev/null)"; do
    if [[ -x $c ]]; then
      print -r -- "$c"
      return 0
    fi
  done
  return 1
}

dir_of_rex() {
  # Returns 3 when the session runs on another computer.
  local rex session out dir
  rex=$(rex_cli) || return 1
  out=$(osascript <<'EOF'
tell application id "com.superlogical.rex"
  set s to current session
  if s is missing value then error "no session"
  if remote of s then return "remote"
  return id of s
end tell
EOF
  ) || return 1
  [[ $out == remote ]] && return 3
  session=${out#*/} # "<window>/session:<id>"

  # Without a block the CLI uses the focused block of the session's active
  # window. Drop REX_BLOCK so a caller running inside Rex doesn't override it.
  # "pwd" is what the shell last reported; "process" asks the OS instead.
  out=$(env -u REX_BLOCK "$rex" block call -s "$session" pwd 2>/dev/null)
  dir=$(print -r -- "$out" | plutil -extract pwd raw -o - - 2>/dev/null)
  [[ $dir == file://* ]] && dir=$(path_of_file_url "$dir")
  if [[ -z $dir || ! -d $dir ]]; then
    out=$(env -u REX_BLOCK "$rex" block call -s "$session" process 2>/dev/null)
    dir=$(print -r -- "$out" | plutil -extract foreground.cwd raw -o - - 2>/dev/null)
  fi
  [[ -n $dir && -d $dir ]] || return 1
  print -r -- "$dir"
}

# ---------------------------------------------------------------------------
# Opening a directory
# ---------------------------------------------------------------------------

open_in_app() {
  open -b "${BUNDLE[$1]}" -- "$2" 2>/dev/null
}

open_in_ghostty() {
  # "open" on a running Ghostty is fine, but AppleScript lets us add a tab to
  # the front window, or make a window when there is none.
  if is_running ghostty && osascript - "$1" >/dev/null 2>&1 <<'EOF'
on run argv
  tell application id "com.mitchellh.ghostty"
    set cfg to new surface configuration
    set initial working directory of cfg to (item 1 of argv)
    if (count of windows) > 0 then
      new tab in front window with configuration cfg
    else
      new window with configuration cfg
    end if
    activate
  end tell
end run
EOF
  then
    return 0
  fi
  open_in_app ghostty "$1"
}

open_in_warp() {
  # Warp has no AppleScript; its URL scheme opens a tab in a given folder.
  local LC_ALL=C encoded
  encoded=${1//(#m)[^A-Za-z0-9._~\/-]/%${(l:2::0:)$(([##16]#MATCH))}}
  open "warp://action/new_tab?path=$encoded" 2>/dev/null || open_in_app warp "$1"
}

# ---------------------------------------------------------------------------

from=${1:-} to=${2:-}
if (( ! ${+BUNDLE[$from]} )) || (( ! ${+BUNDLE[$to]} )) || [[ $from == $to ]]; then
  fail "Usage: terminalfinder.sh <from> <to>"
fi
(( ${+functions[dir_of_$from]} )) || fail "${LABEL[$from]} can't report its current directory."

is_running $from || fail "${LABEL[$from]} isn't running."

dir=$(dir_of_$from 2>/dev/null)
(( $? == 3 )) && fail "This ${LABEL[$from]} session runs on another computer."
[[ -n $dir && -d $dir ]] || fail "Couldn't get the current directory from ${LABEL[$from]}."

if (( ${+functions[open_in_$to]} )); then
  open_in_$to "$dir"
else
  open_in_app $to "$dir"
fi || fail "Couldn't open ${LABEL[$to]}. Is it installed?"
