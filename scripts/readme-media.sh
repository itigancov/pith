#!/bin/bash
# The README's pictures from the real windows: a framed Panel PNG and a GIF (Panel → Search → results), light and dark, into docs/images.
# Usage: scripts/readme-media.sh <Pith.app>   (`make readme-media`; needs Screen Recording for the terminal and ffmpeg)
set -euo pipefail

app="${1:?usage: readme-media.sh <Pith.app>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/docs/images"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v ffmpeg >/dev/null || { echo "readme-media: ffmpeg is not installed (brew install ffmpeg)" >&2; exit 1; }
swiftc -O "$root/scripts/frame.swift" -o "$work/frame"

shoot() { (cd "$root" && SURFACE="$1" FIXTURE="$root/Fixtures/$2" OUT="$work" scripts/shots.sh "$app" >/dev/null); }
shoot window Panel.md
shoot search-all Search.json
shoot search-results Search.json

mkdir -p "$out"
rm -f "$out"/panel-*.png "$out"/search-*.png "$out"/demo-*.gif
for theme in light dark; do
    for shot in window search-all search-results; do
        "$work/frame" "$work/$shot-$theme.png" "$work/framed-$shot-$theme.png" "$theme"
    done
    cp "$work/framed-window-$theme.png" "$out/panel-$theme.png"

    # Panel, Search, results, Panel again (the same frame as the first, so the loop has no jump), cross-faded.
    width=760
    ffmpeg -v error -y \
        -loop 1 -t 3.0 -i "$work/framed-window-$theme.png" \
        -loop 1 -t 2.2 -i "$work/framed-search-all-$theme.png" \
        -loop 1 -t 3.0 -i "$work/framed-search-results-$theme.png" \
        -loop 1 -t 1.0 -i "$work/framed-window-$theme.png" \
        -filter_complex "
            [0:v]scale=$width:-1,fps=15,setsar=1[a];[1:v]scale=$width:-1,fps=15,setsar=1[b];
            [2:v]scale=$width:-1,fps=15,setsar=1[c];[3:v]scale=$width:-1,fps=15,setsar=1[d];
            [a][b]xfade=transition=fade:duration=0.5:offset=2.5[ab];
            [ab][c]xfade=transition=fade:duration=0.5:offset=4.2[abc];
            [abc][d]xfade=transition=fade:duration=0.5:offset=6.7,split[s0][s1];
            [s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=sierra2_4a" \
        "$out/demo-$theme.gif"
done
ls -l "$out"
