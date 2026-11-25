#!/bin/bash
# Screenshots of Pith's real windows in both themes: `make shots`.
# Usage: scripts/shots.sh <Pith.app>
# Environment: SURFACE (window|context-menu|text-size|save-failure), FIXTURE (text file), OUT (folder for the PNGs).
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

# The artboard of the size pill is at 17 pt.
size_args=()
[[ "$surface" == "text-size" ]] && size_args=(-PithTextSize 17)

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

files=()
for theme in light dark; do
    : >"$log"
    "$app/Contents/MacOS/Pith" -PithFixture "$fixture" -PithAppearance "$theme" -PithWindowSize "540 440" \
        ${args[@]+"${args[@]}"} ${size_args[@]+"${size_args[@]}"} -PithShow "$surface" -PithShots YES >"$log" 2>/dev/null &
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

printf '%s\n' "${files[@]}"
