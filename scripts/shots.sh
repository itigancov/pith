#!/bin/bash
# Screenshots of Pith's real windows in both themes: `make shots`.
# Usage: scripts/shots.sh <Pith.app>
# Environment: SURFACE (window|context-menu|text-size|save-failure|recorder|stack|stack-new|jump-latest|search-all|
# search-results|search-empty), FIXTURE (text file, or a .json of Notes for Search), OUT (folder for the PNGs).
set -euo pipefail

app="${1:?usage: shots.sh <Pith.app>}"
surface="${SURFACE:-window}"
fixture="${FIXTURE:?FIXTURE is not set}"
selected="One idea per line."

if [[ -z "${OUT:-}" ]]; then
    case "$PWD" in
        */.claude/worktrees/*) slug="$(basename "$PWD")" ;;
        *) slug="main" ;;
    esac
    OUT="$HOME/.scratch/pith/mvp/shots/$slug"
fi
mkdir -p "$OUT"

# `grep -b` counts bytes; the text is ASCII, so they are UTF-16 offsets too.
args=()
if offset="$(LC_ALL=C grep -boF -m1 "$selected" "$fixture" | head -n1 | cut -d: -f1)" && [[ -n "$offset" ]]; then
    args=(-PithSelection "$offset ${#selected}")
fi

# What the artboard of the surface needs: the size pill is at 17 pt; the footer of the Stack is on note 12 of 40, on a Blank
# after 7 notes, and on the Latest note, 10 of 10.
size_args=()
case "$surface" in
    text-size) size_args=(-PithTextSize 17) ;;
    stack) size_args=(-PithStackSize 40 -PithStackIndex 12) ;;
    stack-new) size_args=(-PithStackSize 7 -PithStackIndex blank) ;;
    jump-latest) size_args=(-PithStackSize 10 -PithStackIndex 10) ;;
esac

# The times of Search's rows are counted from this moment: the first row of Search-All reads "10:42".
now_args=()
[[ "$surface" == search-* ]] && now_args=(-PithNow 2026-11-26T11:00:00)

log="$(mktemp)"
pid=""
cleanup() {
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    rm -f "$log"
}
trap cleanup EXIT

# The recorder window is photographed once per state, at its own size.
states=("")
size="540 440"
if [[ "$surface" == "recorder" ]]; then
    states=(idle recording error)
    size="520 440"
fi

files=()
for state in "${states[@]}"; do
for theme in light dark; do
    : >"$log"
    state_args=()
    [[ -n "$state" ]] && state_args=(-PithRecorderState "$state")
    "$app/Contents/MacOS/Pith" -PithFixture "$fixture" -PithAppearance "$theme" -PithWindowSize "$size" \
        ${args[@]+"${args[@]}"} ${size_args[@]+"${size_args[@]}"} ${state_args[@]+"${state_args[@]}"} ${now_args[@]+"${now_args[@]}"} -PithShow "$surface" -PithShots YES >"$log" 2>/dev/null &
    pid=$!

    for _ in $(seq 100); do
        grep -q '^PithShot done' "$log" && break
        sleep 0.1
    done
    if ! grep -q '^PithShot done' "$log"; then
        echo "shots: Pith did not report its windows within 10 s" >&2
        exit 1
    fi

    before=${#files[@]}
    while read -r _ role id; do
        [[ "$role" == "done" || -z "$id" ]] && continue
        # `screencapture -l` of a popup menu returns the window with the menu open, the same as for the window itself,
        # so the context menu gets its PNG from its menu window; every other surface is in the window itself.
        if [[ "$surface" == "context-menu" ]]; then
            [[ "$role" == "menu" ]] || continue
            name="$surface-$theme.png"
        elif [[ "$surface" == "window" ]]; then
            name="window-$theme.png"
        elif [[ "$surface" == "recorder" ]]; then
            [[ "$role" == "window" ]] || continue
            name="recorder-$state-$theme.png"
        else
            [[ "$role" == "window" ]] || continue
            name="$surface-$theme.png"
        fi
        if ! screencapture -x -o -l "$id" "$OUT/$name" || [[ ! -s "$OUT/$name" ]]; then
            echo "shots: screencapture failed; give the terminal Screen Recording in System Settings → Privacy & Security" >&2
            exit 1
        fi
        files+=("$OUT/$name")
    done < <(grep '^PithShot ' "$log")

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    pid=""
    if [[ ${#files[@]} -eq $before ]]; then
        echo "shots: no '$surface' window reported in the $theme theme" >&2
        exit 1
    fi
done
done

printf '%s\n' "${files[@]}"
